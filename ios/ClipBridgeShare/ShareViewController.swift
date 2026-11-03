//
//  ShareViewController.swift
//  ClipBridgeShare
//

import ClipBridgeKit
import UIKit
import UniformTypeIdentifiers
import os

/// 手机 → 电脑：在任何 App 里选中文字 → 分享 → ClipBridge，文字 POST /clip 写进电脑剪贴板。
/// 共享扩展没有「允许完全访问」这种限制；本地网络权限继承主 App。
/// 必须等 POST 完成再 completeRequest：调用后进程立即被回收，没发完的请求会被取消。
/// iPhone 上系统把它显示成整屏的 sheet，用户可以下拉关闭——那也必须以 cancelRequest 结束，否则宿主的分享面板会挂住。
final class ShareViewController: UIViewController {
    private enum ShareError: LocalizedError {
        case noText(types: [String])
        case attachmentTooLarge(bytes: Int)
        case notPaired
        case misconfigured

        var errorDescription: String? {
            switch self {
            case let .noText(types):
                let list = types.isEmpty ? "无" : types.joined(separator: ", ")
                return "分享的内容里没有可用的纯文字，没有发送。\n附件类型：\(list)"
            case let .attachmentTooLarge(bytes):
                return "分享的内容太大（\(bytes / 1024) KB），只能发送 \(ClipBridgeIdentifiers.defaultMaxTextBytes / 1024) KB 以内的文字。"
            case .notPaired:
                return "尚未配对。先打开 ClipBridge App，扫描电脑终端里的二维码。"
            case .misconfigured:
                return "工程配置错误：读不到配对信息（AppIdentifierPrefix / App Group entitlement）。"
            }
        }
    }

    /// 分享面板里多等一会儿没关系，别用键盘那套 3 秒超时。
    private static let session = ClipBridgeClient.makeSession(requestTimeout: 8, resourceTimeout: 12)
    private static let successDismissDelay: TimeInterval = 0.8
    /// 先看附件大小再读进内存：从「文件」分享一个几十 MB 的 .txt 会把扩展（约 120 MB 上限）直接撑死。
    /// 真正的上限由 send() 按 UTF-8 字节数判定；这里只拦明显离谱的。
    private static let maxAttachmentBytes = 2 * 1024 * 1024
    private static let logger = Logger(subsystem: "com.charleschen.ClipBridge", category: "share")

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
    /// extensionContext 只能结束一次：成功、取消、下拉关闭三条路都经过这个标记。
    private var finished = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
        start()
    }

    /// 用户下拉关掉 sheet（没点任何按钮）：停掉请求，按「用户取消」结束。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard !finished else { return }
        finished = true
        task?.cancel()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil))
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
                fail(error.localizedDescription, hint: "只支持分享纯文字（选中文字 → 分享）。", retryable: false)
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
                fail(
                    Self.message(for: error, endpoint: info.endpoint),
                    hint: Self.hint(for: error, endpoint: info.endpoint),
                    retryable: Self.isRetryable(error)
                )
            }
        }
    }

    // MARK: - 结束扩展

    private func succeed(characterCount: Int) {
        guard !finished else { return }
        // POST 已经成功：之后再下拉也不算取消，只等 completeRequest
        finished = true
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
        guard !finished else { return }
        finished = true
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

    /// 每个附件依次尝试，拿到非空文字就用；全部失败才报错（错误里带附件类型，便于排查）。
    /// 顺序：⓪ 先看附件大小，离谱的直接拒；
    /// ① loadObject(NSString)——系统按 NSItemProviderReading 规则给 String；
    /// ② loadItem(forTypeIdentifier: public.plain-text)——按 Apple 的强制转换规则给 String / NSAttributedString / Data，
    ///    是唯一会把老式注册的 NSString 还原出来的接口（iOS 27 SDK 标 deprecated，仍可用）；
    /// ③ loadObject(NSAttributedString)——富文本取 .string（它会把归档字节当文本解，所以也要过 nonEmpty 的 bplist 检查）；
    /// ④ loadDataRepresentation——原始 Data，必须是合法 UTF-8 或能解开的归档，二进制一律不当文本（2026-11-04 的乱码 bug）；
    /// ⑤ NSExtensionItem.attributedContentText。
    private static func extractText(from inputItems: [Any]) async throws -> String {
        var seenTypes: [String] = []
        for item in inputItems.compactMap({ $0 as? NSExtensionItem }) {
            for provider in item.attachments ?? [] {
                let types = provider.registeredTypeIdentifiers
                seenTypes.append(contentsOf: types)
                logger.info("attachment registeredTypeIdentifiers: \(types.joined(separator: ", "), privacy: .public)")

                let hasPlainText = provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)

                if hasPlainText, let size = await provider.representationSize(for: .plainText) {
                    logger.info("plain-text representation size: \(size) bytes")
                    if size > maxAttachmentBytes {
                        throw ShareError.attachmentTooLarge(bytes: size)
                    }
                }

                if provider.canLoadObject(ofClass: NSString.self) {
                    do {
                        if let text = try await provider.loadString(), let ok = SharedTextDecoder.nonEmpty(text) {
                            logger.info("text via loadObject(NSString), \(ok.count) chars")
                            return ok
                        }
                    } catch {
                        logger.info("loadObject(NSString) failed: \(String(describing: error), privacy: .public)")
                    }
                }

                if hasPlainText {
                    do {
                        let loaded = try await provider.loadLegacyItem(for: .plainText)
                        let kind = loaded.map { String(describing: type(of: $0)) } ?? "nil"
                        if let text = SharedTextDecoder.text(fromLoadedItem: loaded) {
                            logger.info("text via loadItem (\(kind, privacy: .public)), \(text.count) chars")
                            return text
                        }
                        logger.info("loadItem returned \(kind, privacy: .public) that is not usable text")
                    } catch {
                        logger.info("loadItem failed: \(String(describing: error), privacy: .public)")
                    }
                }

                if provider.canLoadObject(ofClass: NSAttributedString.self) {
                    do {
                        if let attributed = try await provider.loadAttributedString(), let ok = SharedTextDecoder.nonEmpty(attributed.string) {
                            logger.info("text via loadObject(NSAttributedString), \(ok.count) chars")
                            return ok
                        }
                    } catch {
                        logger.info("loadObject(NSAttributedString) failed: \(String(describing: error), privacy: .public)")
                    }
                }

                if hasPlainText {
                    do {
                        let data = try await provider.loadData(for: .plainText)
                        if let text = SharedTextDecoder.text(from: data) {
                            logger.info("text via loadDataRepresentation, \(text.count) chars")
                            return text
                        }
                        logger.error("plain-text data is not text: \(data.count) bytes, starts with \(SharedTextDecoder.hexPrefix(of: data), privacy: .public)")
                    } catch {
                        logger.info("loadDataRepresentation failed: \(String(describing: error), privacy: .public)")
                    }
                }
            }
            if let text = item.attributedContentText?.string, let ok = SharedTextDecoder.nonEmpty(text) {
                logger.info("text via attributedContentText, \(ok.count) chars")
                return ok
            }
        }
        throw ShareError.noText(types: Array(Set(seenTypes)).sorted())
    }

    // MARK: - 文案

    private static func message(for error: Error, endpoint: PairingEndpoint) -> String {
        guard let error = error as? ClipBridgeError else {
            return error.localizedDescription
        }
        if error.isOfflineOrLocalNetworkDenied {
            return "本地网络被拒或没有 Wi-Fi。"
        }
        if error.isUnreachable {
            return "连不上电脑 \(endpoint.host):\(String(endpoint.port))：\(error.localizedDescription)"
        }
        return error.localizedDescription
    }

    private static func hint(for error: Error, endpoint: PairingEndpoint) -> String? {
        guard let error = error as? ClipBridgeError else {
            return nil
        }
        switch error {
        case .unauthorized:
            return "在 ClipBridge App 里重新扫码配对。"
        case .notFound, .invalidResponse:
            return "\(endpoint.host):\(String(endpoint.port)) 上不是 ClipBridge 服务，在 App 里检查 host 和端口。"
        case .payloadTooLarge, .contentTooLarge:
            return "超过了电脑端允许的大小（config.json 的 max_text_bytes，默认 100 KB）。"
        case .clipboardUnavailable:
            return "电脑端写剪贴板失败，稍后重试。"
        default:
            break
        }
        if error.isOfflineOrLocalNetworkDenied {
            return "先在 ClipBridge App 里点「测试连接」并允许本地网络。"
        }
        if error.isUnreachable {
            return "确认电脑上的服务在运行、IP 没变、防火墙放行了 \(endpoint.port) 端口，并且手机和电脑在同一个 Wi-Fi。"
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

    /// 新一轮尝试开始：清掉上一次的失败原因，此后点「取消」是用户取消，不是上次的失败。
    private func setBusy(_ text: String) {
        lastFailure = nil
        spinner.startAnimating()
        statusLabel.text = text
        hintLabel.text = nil
        retryButton.isHidden = true
        cancelButton.isHidden = false
        cancelButton.configuration?.title = "取消"
    }

    private func buildUI() {
        view.backgroundColor = .systemBackground

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
    /// 让系统把这个类型写成临时文件，只看大小、不读内容；拿不到就当未知（返回 nil）。
    func representationSize(for type: UTType) async -> Int? {
        await withCheckedContinuation { continuation in
            _ = loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                let size = url.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.size] as? Int }
                continuation.resume(returning: size)
            }
        }
    }

    func loadString() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            _ = loadObject(ofClass: NSString.self) { object, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (object as? NSString).map { $0 as String })
                }
            }
        }
    }

    /// 已 deprecated（iOS 27 SDK）但仍可用：按 Apple 的强制转换规则返回 String / NSAttributedString / Data / NSURL。
    func loadLegacyItem(for type: UTType) async throws -> (any NSSecureCoding)? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item)
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
}
