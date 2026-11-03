import Foundation
import ClipBridgeKit
import Observation
import SwiftUI

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
    /// 由 RootView 用 scenePhase 喂进来。系统权限弹窗出现时 scene 会变成 inactive，回到 active 说明用户已经回答。
    var scenePhase: ScenePhase = .active

    /// 整个 App 共用一个 session（跑过任务的 URLSession 会一直活到 invalidate，不能每次测试新建一个）。
    @ObservationIgnored private let session = ClipBridgeClient.makeSession(requestTimeout: 5, resourceTimeout: 8)
    @ObservationIgnored private var testTask: Task<Void, Never>?
    /// 每次开始/取消测试都加一，旧测试的结果对不上代数就丢掉——解除配对或重新配对后不会冒出上一台电脑的报告。
    @ObservationIgnored private var testGeneration = 0

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
        cancelConnectionTest()
        refresh()
    }

    func unpair() throws {
        try store.clear()
        cancelConnectionTest()
        refresh()
    }

    // MARK: 测试连接

    func startConnectionTest() {
        cancelConnectionTest()
        let generation = testGeneration
        testTask = Task { await runConnectionTest(generation: generation) }
    }

    private func cancelConnectionTest() {
        testTask?.cancel()
        testTask = nil
        testGeneration += 1
        connectionTest = .idle
    }

    private func publish(_ test: ConnectionTest, generation: Int) {
        guard generation == testGeneration else { return }
        connectionTest = test
    }

    /// 先 /health（免鉴权，证明局域网通、对面是 ClipBridge），再 history?limit=1（证明 token 正确）。
    private func runConnectionTest(generation: Int) async {
        guard let info = pairingInfo else {
            return
        }
        var report = ConnectionReport()
        publish(.running(report), generation: generation)
        let client = ClipBridgeClient(pairing: info, session: session)

        do {
            let health = try await healthWaitingForLocalNetworkPrompt(client: client, report: &report, generation: generation)
            let monitor = health.monitorRunning ? "运行中" : "未运行"
            report.hint = nil
            report.health = .ok("服务 v\(health.version)，剪贴板监听\(monitor)，已记录 \(health.historyItems) 条")
            // 先把这一行变绿，别让用户等第二步的超时
            publish(.running(report), generation: generation)
        } catch {
            guard !Task.isCancelled else { return }
            report.health = .failed(error.localizedDescription)
            report.hint = Self.hint(for: error, port: info.port)
            publish(.finished(report), generation: generation)
            return
        }

        do {
            let item = try await client.latest()
            if let item {
                // 只报元数据，不把电脑剪贴板的内容留在屏幕上（可能是密码、验证码）
                let source = item.source == .pc ? "电脑" : "手机"
                let time = item.timestamp.formatted(date: .omitted, time: .shortened)
                report.latest = .ok("token 正确。最新一条来自\(source)，\(time)")
            } else {
                report.latest = .ok("token 正确。电脑上还没有记录任何内容")
            }
        } catch {
            guard !Task.isCancelled else { return }
            report.latest = .failed(error.localizedDescription)
            report.hint = Self.hint(for: error, port: info.port)
        }
        publish(.finished(report), generation: generation)
    }

    /// 第一次访问局域网会触发系统的「本地网络」弹窗，而且系统可能在用户回答前就先拒绝一次（-1009）。
    /// 没有 API 能查询这个权限，只能重试：弹窗出现时 scene 变 inactive，回到 active 就是用户答完了，再试最后一次；
    /// 一直没见到弹窗（之前就拒绝过、或没连 Wi-Fi）就只多试一次；整体不超过 25 秒。
    private func healthWaitingForLocalNetworkPrompt(
        client: ClipBridgeClient,
        report: inout ConnectionReport,
        generation: Int
    ) async throws -> HealthResponse {
        let clock = ContinuousClock()
        let start = clock.now
        var sawAlert = false
        var triedAfterAnswer = false
        while true {
            do {
                return try await client.health()
            } catch let error as ClipBridgeError where error.isOfflineOrLocalNetworkDenied {
                try Task.checkCancellation()
                let elapsed = clock.now - start
                if triedAfterAnswer || elapsed > .seconds(25) {
                    throw error
                }
                if scenePhase != .active {
                    sawAlert = true
                }
                if !sawAlert && elapsed > .seconds(4) {
                    // 4 秒内没弹过窗：不是首次询问，是真的被拒或没网
                    throw error
                }
                if report.hint == nil {
                    report.hint = "系统正在询问「本地网络」权限，请在弹窗里选「允许」…"
                    publish(.running(report), generation: generation)
                }
                if sawAlert && scenePhase == .active {
                    triedAfterAnswer = true
                    continue
                }
                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    static func hint(for error: Error, port: Int) -> String? {
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
            return "如果刚才弹出了询问并已点「允许」，再点一次「测试连接」即可；否则到 设置 → 隐私与安全性 → 本地网络 打开 ClipBridge（「打开 ClipBridge 的系统设置」也能进入），并确认 iPhone 和电脑在同一个 Wi-Fi。"
        }
        if error.isUnreachable {
            return "确认电脑上的服务在运行、IP 没变、防火墙放行了 \(port) 端口，并且手机和电脑在同一个 Wi-Fi（校园网常有 AP 隔离，可改用手机热点）。"
        }
        if error.isBlockedByATS {
            return "工程配置错误：Info.plist 缺 NSAppTransportSecurity → NSAllowsLocalNetworking。"
        }
        return nil
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
    /// 进行中：当前在等什么；失败时：下一步做什么。
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
