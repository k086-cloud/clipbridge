//
//  KeyboardViewController.swift
//  ClipBridgeKeyboard
//

import ClipBridgeKit
import UIKit
import os

/// 电脑 → 手机：显示电脑最近几条剪贴板内容，点卡片插入到当前输入框。
/// 键盘进程内存很紧（社区实测约 50–70 MB 就会被静默杀掉），所以只用 UIKit、只保留 5 条、不缓存任何东西。
final class KeyboardViewController: UIInputViewController {
    private static let preferredItemCount = 5
    private static let keyboardHeight: CGFloat = 280
    private static let flashDuration: TimeInterval = 2.5

    private let keyboardView = KeyboardView()
    private let logger = Logger(subsystem: "com.charleschen.ClipBridge", category: "keyboard")
    /// 真机上是 App Group + 共享 Keychain；工程配错时为 nil，界面会直说。
    private let pairingStore: (any PairingStore)? = SharedPairingStore.live()

    private var heightConstraint: NSLayoutConstraint?
    private var loadTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var flashWorkItem: DispatchWorkItem?
    private var pairing: PairingInfo?
    private var currentStatus = ""

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardView)
        NSLayoutConstraint.activate([
            keyboardView.topAnchor.constraint(equalTo: view.topAnchor),
            keyboardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            keyboardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // 地球键：Apple 要求自定义键盘提供切换到下一个键盘的方式；长按出列表、点按切换都由这个 selector 处理。
        keyboardView.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        keyboardView.onCardTap = { [weak self] item in self?.insert(item) }
        keyboardView.onRefresh = { [weak self] in self?.reload() }
        keyboardView.onSend = { [weak self] in self?.sendClipboard() }
        keyboardView.onBackspace = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        keyboardView.onSpace = { [weak self] in self?.textDocumentProxy.insertText(" ") }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installHeightConstraintIfNeeded()
        applyAppearance()
        keyboardView.globeButton.isHidden = !needsInputModeSwitchKey
        reload()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        loadTask?.cancel()
        loadTask = nil
        sendTask?.cancel()
        sendTask = nil
        flashWorkItem?.cancel()
        flashWorkItem = nil
    }

    override func viewWillLayoutSubviews() {
        // Face ID 机型系统自己在键盘下方画地球键，这时 needsInputModeSwitchKey 为 false
        keyboardView.globeButton.isHidden = !needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        applyAppearance()
    }

    /// 键盘视图默认是透明的，高度也要自己给；优先级 999 避免和系统的约束冲突时直接崩。
    private func installHeightConstraintIfNeeded() {
        guard heightConstraint == nil else { return }
        inputView?.allowsSelfSizing = true
        let constraint = view.heightAnchor.constraint(equalToConstant: Self.keyboardHeight)
        constraint.priority = UILayoutPriority(999)
        constraint.isActive = true
        heightConstraint = constraint
    }

    /// 跟着宿主输入框的键盘外观走（备忘录深色模式等），这样系统动态颜色都对。
    private func applyAppearance() {
        switch textDocumentProxy.keyboardAppearance {
        case .dark:
            view.overrideUserInterfaceStyle = .dark
        case .light:
            view.overrideUserInterfaceStyle = .light
        default:
            view.overrideUserInterfaceStyle = .unspecified
        }
    }

    // MARK: - 读取电脑剪贴板历史

    private func reload() {
        loadTask?.cancel()
        pairing = nil

        guard hasFullAccess else {
            // 没开完全访问：沙盒禁网，也不去碰 Keychain（以 hasFullAccess 为准，不用 Keychain 失败推断）。
            // App Group 的共享容器按 Apple 文档此时仍可只读，所以能告诉用户「已配对但要开完全访问」。
            let endpoint = UserDefaultsEndpointStore(appGroup: ClipBridgeIdentifiers.appGroup)?.loadEndpoint()
            if let endpoint {
                showMessage("要连接电脑 \(endpoint.host) 需要「允许完全访问」。\n设置 → 通用 → 键盘 → 键盘 → ClipBridge — ClipBridgeKeyboard → 允许完全访问")
            } else {
                showMessage("尚未配对。先打开 ClipBridge App 扫码配对，再在设置里开启「允许完全访问」。")
            }
            probeKeychainWithoutFullAccess()
            return
        }

        guard let pairingStore else {
            showMessage("工程配置错误：读不到配对信息（AppIdentifierPrefix / App Group entitlement）。")
            return
        }

        switch pairingStore.load() {
        case .notPaired:
            showMessage("尚未配对。打开 ClipBridge App，扫描电脑终端里的二维码。")
        case let .tokenUnavailable(endpoint, reason):
            showMessage("已配对 \(endpoint.host)，但读不到 token：\(reason.localizedDescription)\n在 ClipBridge App 里重新配对一次即可。")
        case let .paired(info):
            pairing = info
            keyboardView.setLoading(true)
            setStatus("正在从 \(info.host) 获取…")
            loadTask = Task { [weak self] in
                let client = ClipBridgeClient(pairing: info)
                do {
                    let items = try await client.recentHistory(preferredLimit: Self.preferredItemCount)
                    guard let self, !Task.isCancelled else { return }
                    keyboardView.setLoading(false)
                    if items.isEmpty {
                        showMessage("电脑上还没有复制过内容。在电脑上复制一段文字，再点刷新。")
                    } else {
                        keyboardView.show(items: items)
                        setStatus("电脑最近 \(items.count) 条 · 点卡片插入")
                    }
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    keyboardView.setLoading(false)
                    showMessage(Self.message(for: error))
                }
            }
        }
    }

    private func insert(_ item: ClipItem) {
        textDocumentProxy.insertText(item.content)
        flash("已插入 \(item.content.count) 个字符")
    }

    // MARK: - 手机剪贴板 → 电脑

    /// 键盘拿不到完整的文档内容，所以这里发的是手机剪贴板（需要完全访问；iOS 16 起系统会弹一次「允许粘贴」）。
    /// 手机 → 电脑的主路径仍然是共享扩展。
    private func sendClipboard() {
        guard let pairing else {
            flash("先配对并开启完全访问")
            return
        }
        guard UIPasteboard.general.hasStrings, let text = UIPasteboard.general.string, !text.isEmpty else {
            flash("手机剪贴板里没有文字")
            return
        }
        sendTask?.cancel()
        keyboardView.setSending(true)
        sendTask = Task { [weak self] in
            let client = ClipBridgeClient(pairing: pairing)
            do {
                try await client.send(text)
                guard let self, !Task.isCancelled else { return }
                keyboardView.setSending(false)
                flash("已发送到电脑（\(text.count) 个字符）")
            } catch {
                guard let self, !Task.isCancelled else { return }
                keyboardView.setSending(false)
                flash(Self.message(for: error))
            }
        }
    }

    // MARK: - 状态文字

    private func setStatus(_ text: String) {
        currentStatus = text
        keyboardView.statusLabel.text = text
    }

    private func showMessage(_ text: String) {
        keyboardView.showMessage(text)
        setStatus("")
    }

    /// 临时显示一条反馈，几秒后恢复原状态。
    private func flash(_ text: String) {
        flashWorkItem?.cancel()
        keyboardView.statusLabel.text = text
        let restore = DispatchWorkItem { [weak self] in
            guard let self else { return }
            keyboardView.statusLabel.text = currentStatus
        }
        flashWorkItem = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration, execute: restore)
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? ClipBridgeError else {
            return error.localizedDescription
        }
        if error.isSandboxDenied {
            return "没有网络权限：请在设置里为 ClipBridge 键盘开启「允许完全访问」。"
        }
        if error.isOfflineOrLocalNetworkDenied {
            return "本地网络被拒或没有 Wi-Fi。先在 ClipBridge App 里点「测试连接」。"
        }
        if error.isUnreachable {
            return "连不上电脑：\(error.localizedDescription)。确认电脑上的服务在运行、手机和电脑在同一个 Wi-Fi。"
        }
        if error == .unauthorized {
            return "token 不对。在 ClipBridge App 里重新扫码配对。"
        }
        return error.localizedDescription
    }

    /// Apple 没写明没开「允许完全访问」时能不能读共享 Keychain。这里只把 OSStatus 记到控制台（Xcode 附加到键盘进程可见），
    /// 不拿它做任何判断；也绝不打印 token 本身。
    private func probeKeychainWithoutFullAccess() {
        guard let accessGroup = KeychainAccessGroup.shared() else { return }
        do {
            let token = try KeychainTokenStore(accessGroup: accessGroup).loadToken()
            logger.info("Keychain probe without Full Access: \(token == nil ? "no item (errSecItemNotFound)" : "readable", privacy: .public)")
        } catch {
            logger.info("Keychain probe without Full Access failed: \(String(describing: error), privacy: .public)")
        }
    }
}
