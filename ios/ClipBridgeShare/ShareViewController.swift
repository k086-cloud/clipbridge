//
//  ShareViewController.swift
//  ClipBridgeShare
//

import ClipBridgeKit
import UIKit
import UniformTypeIdentifiers

/// 手机 → 电脑：在任何 App 里选中文字 → 分享 → ClipBridge，文字 POST /clip 写进电脑剪贴板。
/// 共享扩展没有「允许完全访问」这种限制；本地网络权限继承主 App。
/// 必须等 POST 完成再 completeRequest：调用后进程立即被回收，没发完的请求会被取消。
final class ShareViewController: UIViewController {
    private enum ShareError: LocalizedError {
        case noText
        case notPaired
        case misconfigured

        var errorDescription: String? {
            switch self {
            case .noText: return "分享的内容里没有文字（只支持纯文本）"
            case .notPaired: return "尚未配对。先打开 ClipBridge App，扫描电脑终端里的二维码。"
            case .misconfigured: return "工程配置错误：读不到配对信息（AppIdentifierPrefix / App Group entitlement）。"
            }
        }
    }

    /// 分享面板里多等一会儿没关系，别用键盘那套 3 秒超时。
    private static let session = ClipBridgeClient.makeSession(requestTimeout: 8, resourceTimeout: 12)
    private static let successDismissDelay: TimeInterval = 0.8

    private let pairingStore: (any PairingStore)? = SharedPairingStore.live()

    private let titleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private let hintLabel = UILabel()
    private let retryButton = UIButton(configuration: .filled())
    private let cancelButton = UIButton(configuration: .gray())

    private var sharedText: String?
    private var task: Task<Void, Never>?
    private var lastFailure: String?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        start()
    }

    private func start() {
        task?.cancel()
        setBusy("正在读取分享的内容…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await Self.extractText(from: extensionContext?.inputItems ?? [])
                guard !Task.isCancelled else { return }
                sharedText = text
                await send(text)
            } catch {
                guard !Task.isCancelled else { return }
                fail(error.localizedDescription, hint: nil, retryable: false)
            }
        }
    }

    private func retry() {
        guard let sharedText else {
            start()
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            await self?.send(sharedText)
        }
    }

    private func send(_ text: String) async {
        guard let pairingStore else {
            fail(ShareError.misconfigured.localizedDescription, hint: nil, retryable: false)
            return
        }
        switch pairingStore.load() {
        case .notPaired:
            fail(ShareError.notPaired.localizedDescription, hint: nil, retryable: false)
        case let .tokenUnavailable(endpoint, reason):
            fail("已配对 \(endpoint.host)，但读不到 token：\(reason.localizedDescription)", hint: "在 ClipBridge App 里重新配对一次即可。", retryable: false)
        case let .paired(info):
            setBusy("正在发送到电脑 \(info.host)…")
            let client = ClipBridgeClient(pairing: info, session: Self.session)
            do {
                try await client.send(text)
                guard !Task.isCancelled else { return }
                succeed(characterCount: text.count)
            } catch {
                guard !Task.isCancelled else { return }
                fail(Self.message(for: error), hint: Self.hint(for: error, port: info.port), retryable: Self.isRetryable(error))
            }
        }
    }

    // MARK: - 结束扩展

    private func succeed(characterCount: Int) {
        spinner.stopAnimating()
        statusLabel.text = "已发送到电脑（\(characterCount) 个字符）"
        hintLabel.text = "在电脑上 Ctrl+V 即可粘贴。"
        retryButton.isHidden = true
        cancelButton.isHidden = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.successDismissDelay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    private func fail(_ message: String, hint: String?, retryable: Bool) {
        spinner.stopAnimating()
        lastFailure = message
        statusLabel.text = message
        hintLabel.text = hint
        retryButton.isHidden = !retryable
        cancelButton.isHidden = false
        cancelButton.configuration?.title = "关闭"
    }

    /// 取消 / 失败后关闭：把原因交给宿主（宿主一般不显示，但按 Apple 的契约应该这样结束）。
    private func cancel() {
        task?.cancel()
        let error: NSError
        if let lastFailure {
            error = NSError(
                domain: "com.charleschen.ClipBridge.share",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: lastFailure]
            )
        } else {
            error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        }
        extensionContext?.cancelRequest(withError: error)
    }

    // MARK: - 取分享的文字

    /// 依次尝试：public.plain-text 的 Data → 富文本（NSAttributedString）→ NSExtensionItem 自带的 attributedContentText。
    /// 用 loadDataRepresentation / loadObject 而不是 loadItem（后者在 iOS 27 SDK 里已标记到期）。
    private static func extractText(from inputItems: [Any]) async throws -> String {
        for item in inputItems.compactMap({ $0 as? NSExtensionItem }) {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    let data = try await provider.loadData(for: .plainText)
                    if let text = decodeText(data), !text.isEmpty {
                        return text
                    }
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let attributed = try await provider.loadAttributedString(), !attributed.string.isEmpty {
                        return attributed.string
                    }
                }
            }
            if let text = item.attributedContentText?.string, !text.isEmpty {
                return text
            }
        }
        throw ShareError.noText
    }

    private static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16)
    }

    // MARK: - 文案

    private static func message(for error: Error) -> String {
        guard let error = error as? ClipBridgeError else {
            return error.localizedDescription
        }
        if error.isOfflineOrLocalNetworkDenied {
            return "本地网络被拒或没有 Wi-Fi。"
        }
        if error.isUnreachable {
            return "连不上电脑：\(error.localizedDescription)"
        }
        return error.localizedDescription
    }

    private static func hint(for error: Error, port: Int) -> String? {
        guard let error = error as? ClipBridgeError else {
            return nil
        }
        switch error {
        case .unauthorized:
            return "在 ClipBridge App 里重新扫码配对。"
        case .notFound, .invalidResponse:
            return "配对的地址上不是 ClipBridge 服务，在 App 里检查 host 和端口。"
        case .payloadTooLarge, .contentTooLarge:
            return "只能发送 100 KB 以内的文字。"
        case .clipboardUnavailable:
            return "电脑端写剪贴板失败，稍后重试。"
        default:
            break
        }
        if error.isOfflineOrLocalNetworkDenied {
            return "先在 ClipBridge App 里点「测试连接」并允许本地网络。"
        }
        if error.isUnreachable {
            return "确认电脑上的服务在运行、防火墙放行了 \(port) 端口、手机和电脑在同一个 Wi-Fi。"
        }
        return nil
    }

    /// 网络没通、电脑临时写不了剪贴板 → 可以重试；token 错、内容太大 → 重试也没用。
    private static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? ClipBridgeError else {
            return false
        }
        switch error {
        case .transport, .underlying, .clipboardUnavailable, .unexpectedStatus:
            return true
        default:
            return false
        }
    }

    // MARK: - UI

    private func setBusy(_ text: String) {
        spinner.startAnimating()
        statusLabel.text = text
        hintLabel.text = nil
        retryButton.isHidden = true
        cancelButton.isHidden = false
        cancelButton.configuration?.title = "取消"
    }

    private func buildUI() {
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 360, height: 280)

        titleLabel.text = "发送到电脑"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textAlignment = .center

        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        hintLabel.font = .preferredFont(forTextStyle: .footnote)
        hintLabel.textColor = .secondaryLabel
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 0

        spinner.hidesWhenStopped = true

        retryButton.configuration?.title = "重试"
        retryButton.addAction(UIAction { [weak self] _ in self?.retry() }, for: .touchUpInside)
        cancelButton.configuration?.title = "取消"
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [retryButton, cancelButton])
        buttons.axis = .horizontal
        buttons.spacing = 12
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [titleLabel, spinner, statusLabel, hintLabel, buttons])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }
}

private extension NSItemProvider {
    func loadData(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadDataRepresentation(for: type) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadCorruptFile))
                }
            }
        }
    }

    func loadAttributedString() async throws -> NSAttributedString? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: NSAttributedString.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: object as? NSAttributedString)
                }
            }
        }
    }
}
