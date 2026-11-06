//
//  KeyboardViewController.swift
//  ClipBridgeKeyboard
//

import ClipBridgeKit
import UIKit

/// 电脑 → 手机：显示电脑最近几条剪贴板内容，点卡片插入到当前输入框。
/// 键盘进程内存很紧（社区实测约 50–70 MB 就会被静默杀掉），所以只用 UIKit、只保留 5 条、不缓存任何东西。
final class KeyboardViewController: UIInputViewController {
    private static let preferredItemCount = 5
    /// 键盘跟随宿主 App 的方向（备忘录、Safari 都能横屏），横屏时 440 pt 高的屏幕放不下 280 pt。
    private static let portraitHeight: CGFloat = 280
    private static let landscapeHeight: CGFloat = 190
    private static let flashDuration: TimeInterval = 2.5
    private static let errorFlashDuration: TimeInterval = 6

    private let keyboardView = KeyboardView()
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
        // 键盘进程会活很久，视图也不会重建：取消任务的同时把界面复位，别留下转圈或灰掉的发送键。
        loadTask?.cancel()
        loadTask = nil
        sendTask?.cancel()
        sendTask = nil
        flashWorkItem?.cancel()
        flashWorkItem = nil
        keyboardView.setLoading(false)
        keyboardView.setSending(false)
        restoreStatus()
    }

    override func viewWillLayoutSubviews() {
        // Face ID 机型系统自己在键盘下方画地球键，这时 needsInputModeSwitchKey 为 false
        keyboardView.globeButton.isHidden = !needsInputModeSwitchKey
        heightConstraint?.constant = preferredHeight
        super.viewWillLayoutSubviews()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        applyAppearance()
    }

    /// 横屏（竖向 compact）用矮的；只支持 iPhone，所以宽度判断是兜底。
    private var preferredHeight: CGFloat {
        if traitCollection.verticalSizeClass == .compact || view.bounds.width > 600 {
            return Self.landscapeHeight
        }
        return Self.portraitHeight
    }

    /// 键盘视图默认是透明的，高度也要自己给；优先级 999 避免和系统的约束冲突时直接崩。
    private func installHeightConstraintIfNeeded() {
        guard heightConstraint == nil else { return }
        inputView?.allowsSelfSizing = true
        let constraint = view.heightAnchor.constraint(equalToConstant: preferredHeight)
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
            // 没开完全访问：沙盒禁网，键盘也连不上 securityd（2026-11-05 真机：TCC XPC_ERROR_CONNECTION_INVALID、
            // securityd「Failed to talk to securityd after 4 attempts」），所以以 hasFullAccess 为准，不连网、不读 Keychain。
            // App Group 的共享容器此时仍可只读（真机已证实），所以能告诉用户「已配对但要开完全访问」。
            let endpoint = UserDefaultsEndpointStore(appGroup: ClipBridgeIdentifiers.appGroup)?.loadEndpoint()
            if let endpoint {
                showMessage("要连接电脑 \(endpoint.host) 需要「允许完全访问」。\n设置 → 通用 → 键盘 → 键盘 → ClipBridge — ClipBridgeKeyboard → 允许完全访问")
            } else {
                showMessage("尚未配对。先打开 ClipBridge App 扫码配对，再在设置里开启「允许完全访问」。")
            }
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
                        showMessage("电脑上暂时没有记录。在电脑上复制一段文字，再点刷新。")
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

    /// 键盘拿不到完整的文档内容，所以这里发的是手机剪贴板（需要完全访问）。
    /// iOS 16 起程序化读取剪贴板会弹系统的「允许粘贴」：设置里是「询问」时每次新内容都会问；
    /// 设置 → ClipBridge → 从其他 App 粘贴 → 允许 可以关掉询问。手机 → 电脑的主路径仍然是共享扩展。
    private func sendClipboard() {
        guard let pairing else {
            flash("先配对并开启完全访问")
            return
        }
        let pasteboard = UIPasteboard.general
        guard pasteboard.hasStrings else {
            // 只查元数据，不会弹窗
            flash("手机剪贴板里没有文字")
            return
        }
        // 这一行会弹系统「允许粘贴」并阻塞到用户回答；拒绝（或 Universal Clipboard 取不到）时返回 nil
        guard let text = pasteboard.string else {
            flash("读不到剪贴板：若刚才点了「不允许粘贴」，到 设置 → ClipBridge → 从其他 App 粘贴 选「允许」", isError: true)
            return
        }
        guard !text.isEmpty else {
            flash("手机剪贴板里只有空文本")
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
                // 状态行只有一行，用短文案；详细指引在卡片区的错误提示里
                flash("发送失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - 状态文字

    private func setStatus(_ text: String) {
        currentStatus = text
        keyboardView.statusLabel.textColor = .secondaryLabel
        keyboardView.statusLabel.text = text
    }

    private func showMessage(_ text: String) {
        keyboardView.showMessage(text)
        setStatus("")
    }

    /// 临时显示一条反馈，几秒后恢复原状态；错误用红色、显示更久。
    private func flash(_ text: String, isError: Bool = false) {
        flashWorkItem?.cancel()
        keyboardView.statusLabel.textColor = isError ? .systemRed : .secondaryLabel
        keyboardView.statusLabel.text = text
        let restore = DispatchWorkItem { [weak self] in
            self?.restoreStatus()
        }
        flashWorkItem = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? Self.errorFlashDuration : Self.flashDuration), execute: restore)
    }

    private func restoreStatus() {
        keyboardView.statusLabel.textColor = .secondaryLabel
        keyboardView.statusLabel.text = currentStatus
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
}
