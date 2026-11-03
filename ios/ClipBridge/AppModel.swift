import Foundation
import ClipBridgeKit
import Observation

/// 主 App 的状态：配对信息、待确认的配对、连接测试结果。所有方法都在主线程（App target 默认 MainActor）。
@Observable
final class AppModel {
    let store: any PairingStore
    /// `SharedPairingStore.live()` 失败（Info.plist 缺 AppIdentifierPrefix / 没有 App Group entitlement）时的说明；正常为 nil。
    let configurationError: String?

    private(set) var pairingState: PairingState = .notPaired
    /// 扫码或 clipbridge:// 链接解析成功后，等用户确认再保存。
    var pendingPairing: PendingPairing?
    /// 扫码或链接解析失败的说明，用来弹提示。
    var pairingInputError: String?
    private(set) var connectionTest: ConnectionTest = .idle

    init(store: any PairingStore, configurationError: String? = nil) {
        self.store = store
        self.configurationError = configurationError
        refresh()
    }

    /// 真机：App Group + 共享 Keychain。工程配错时退回内存存储并把原因挂在 configurationError 上，界面会显示红色提示。
    static func live() -> AppModel {
        if let store = SharedPairingStore.live() {
            return AppModel(store: store)
        }
        return AppModel(
            store: SharedPairingStore.inMemory(),
            configurationError: "工程配置错误：Info.plist 缺 AppIdentifierPrefix，或没有 App Group entitlement。配对信息只会保存在内存里，扩展读不到。"
        )
    }

    var pairingInfo: PairingInfo? {
        if case let .paired(info) = pairingState {
            return info
        }
        return nil
    }

    func refresh() {
        pairingState = store.load()
    }

    // MARK: 配对

    func handleScannedCode(_ code: String) {
        stage(parsing: code)
    }

    func handleIncomingURL(_ url: URL) {
        stage(parsing: url.absoluteString)
    }

    private func stage(parsing text: String) {
        do {
            pendingPairing = PendingPairing(info: try PairingURLParser.parse(text))
            pairingInputError = nil
        } catch {
            pendingPairing = nil
            pairingInputError = "\(error.localizedDescription)\n\n内容：\(text.prefix(120))"
        }
    }

    func confirmPendingPairing() throws {
        guard let pending = pendingPairing else {
            return
        }
        try pair(pending.info)
        pendingPairing = nil
    }

    func pair(_ info: PairingInfo) throws {
        try store.save(info)
        connectionTest = .idle
        refresh()
    }

    func unpair() throws {
        try store.clear()
        connectionTest = .idle
        refresh()
    }

    // MARK: 测试连接

    /// 先 /health（免鉴权，证明局域网通、对面是 ClipBridge），再 history?limit=1（证明 token 正确）。
    /// 第一次访问局域网会触发系统的「本地网络」弹窗，系统可能在用户回答前就先拒绝一次，所以 -1009 时等 2 秒重试一次。
    func testConnection() async {
        guard let info = pairingInfo else {
            return
        }
        var report = ConnectionReport()
        connectionTest = .running(report)
        let client = ClipBridgeClient(
            pairing: info,
            session: ClipBridgeClient.makeSession(requestTimeout: 5, resourceTimeout: 8)
        )

        do {
            let health = try await withLocalNetworkRetry { try await client.health() }
            let monitor = health.monitorRunning ? "运行中" : "未运行"
            report.health = .ok("服务 v\(health.version)，剪贴板监听\(monitor)，已记录 \(health.historyItems) 条")
        } catch {
            report.health = .failed(error.localizedDescription)
            report.hint = Self.hint(for: error)
            connectionTest = .finished(report)
            return
        }

        do {
            let item = try await client.latest()
            if let item {
                report.latest = .ok("token 正确。电脑最新一条：\(Self.preview(item.content))")
            } else {
                report.latest = .ok("token 正确。电脑上还没有记录任何内容")
            }
        } catch {
            report.latest = .failed(error.localizedDescription)
            report.hint = Self.hint(for: error)
        }
        connectionTest = .finished(report)
    }

    private func withLocalNetworkRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as ClipBridgeError where error.isOfflineOrLocalNetworkDenied {
            try await Task.sleep(for: .seconds(2))
            return try await operation()
        }
    }

    static func hint(for error: Error) -> String? {
        guard let error = error as? ClipBridgeError else {
            return nil
        }
        switch error {
        case .unauthorized:
            return "重新扫描电脑上的二维码，或在「手动输入」里改正 token。电脑端重新生成 config.json 后 token 会变。"
        case .notFound, .invalidResponse:
            return "检查 host 和端口是否指向运行 ClipBridge 服务的电脑（终端里打印的 Health URL 在 Safari 能打开才对）。"
        default:
            break
        }
        if error.isOfflineOrLocalNetworkDenied {
            return "到 设置 → 隐私与安全性 → 本地网络 打开 ClipBridge（也可从下面的「打开 ClipBridge 设置」进入），并确认 iPhone 和电脑在同一个 Wi-Fi。"
        }
        if error.isUnreachable {
            return "确认电脑上的服务在运行、IP 没变、防火墙放行了 8765 端口，并且手机和电脑在同一个 Wi-Fi（校园网常有 AP 隔离，可改用手机热点）。"
        }
        if error.isBlockedByATS {
            return "工程配置错误：Info.plist 缺 NSAppTransportSecurity → NSAllowsLocalNetworking。"
        }
        return nil
    }

    static func preview(_ text: String, limit: Int = 60) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        return flattened.count > limit ? String(flattened.prefix(limit)) + "…" : flattened
    }
}

struct PendingPairing: Identifiable, Equatable {
    let id = UUID()
    let info: PairingInfo
}

enum ConnectionTest: Equatable {
    case idle
    case running(ConnectionReport)
    case finished(ConnectionReport)

    var report: ConnectionReport? {
        switch self {
        case .idle: return nil
        case let .running(report), let .finished(report): return report
        }
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}

struct ConnectionReport: Equatable {
    enum Step: Equatable {
        case pending
        case ok(String)
        case failed(String)
    }

    var health: Step = .pending
    var latest: Step = .pending
    /// 失败时告诉用户下一步做什么。
    var hint: String?

    var isSuccess: Bool {
        if case .ok = health, case .ok = latest {
            return true
        }
        return false
    }
}

extension String {
    /// token 只显示头尾，中间打码。
    var maskedToken: String {
        guard count > 10 else { return String(repeating: "•", count: count) }
        return "\(prefix(4))…\(suffix(4))"
    }
}
