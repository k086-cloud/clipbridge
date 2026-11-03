import Foundation
import Security

/// 读出来的配对状态。UI 按它决定显示什么：
/// - notPaired：引导去主 App 配对
/// - paired：正常工作
/// - tokenUnavailable：App Group 里有地址但 Keychain 里的 token 读不到。由 reason 区分：
///   - itemNotFound：条目不存在。注意按 Apple 文档，**查询**一个本 target 无权访问的 access group 也是这个码
///     （-34018 只在写入/删除时出现），所以在只读的扩展里它也可能意味着 entitlement 配错了
///   - interactionNotAllowed：设备还没首次解锁
///   - notAvailable：没有可用的 Keychain（社区报告：键盘没开「允许完全访问」）
public enum PairingState: Equatable, Sendable {
    case notPaired
    case paired(PairingInfo)
    case tokenUnavailable(endpoint: PairingEndpoint, reason: KeychainError)
}

/// 主 App 写、两个扩展读。真机上用 `SharedPairingStore.live()`，测试和预览用 `SharedPairingStore.inMemory()`。
public protocol PairingStore: Sendable {
    func load() -> PairingState
    func save(_ info: PairingInfo) throws
    func clear() throws
}

/// host/port 的存放处（App Group 的 UserDefaults）。不是机密，键盘没开完全访问时也能读。
public protocol EndpointStore: Sendable {
    func loadEndpoint() -> PairingEndpoint?
    func save(_ endpoint: PairingEndpoint)
    func clearEndpoint()
}

/// token 的存放处（共享 Keychain）。
public protocol TokenStore: Sendable {
    /// nil 表示没有条目；其他 Keychain 故障抛 `KeychainError`。
    func loadToken() throws -> String?
    func save(token: String) throws
    func clearToken() throws
}

/// 把地址和 token 组合成一份 PairingInfo，并把 Keychain 故障折叠成 `PairingState`。
public struct SharedPairingStore: PairingStore {
    public let endpoints: any EndpointStore
    public let tokens: any TokenStore

    public init(endpoints: any EndpointStore, tokens: any TokenStore) {
        self.endpoints = endpoints
        self.tokens = tokens
    }

    /// 真机上的默认组合：App Group 存地址，共享 Keychain 存 token。
    /// Info.plist 没有 AppIdentifierPrefix、或没有 App Group entitlement 时返回 nil——
    /// 这两种都是工程配置错误，不该在运行时静默降级。
    public static func live(bundle: Bundle = .main) -> SharedPairingStore? {
        guard let accessGroup = KeychainAccessGroup.shared(bundle: bundle),
              let endpoints = UserDefaultsEndpointStore(appGroup: ClipBridgeIdentifiers.appGroup) else {
            return nil
        }
        return SharedPairingStore(endpoints: endpoints, tokens: KeychainTokenStore(accessGroup: accessGroup))
    }

    public static func inMemory(_ info: PairingInfo? = nil) -> SharedPairingStore {
        SharedPairingStore(
            endpoints: InMemoryEndpointStore(endpoint: info?.endpoint),
            tokens: InMemoryTokenStore(token: info?.token)
        )
    }

    public func load() -> PairingState {
        let endpoint = endpoints.loadEndpoint()
        do {
            let token = try tokens.loadToken()
            switch (endpoint, token) {
            case let (endpoint?, token?):
                return .paired(PairingInfo(endpoint: endpoint, token: token))
            case let (endpoint?, nil):
                return .tokenUnavailable(endpoint: endpoint, reason: .itemNotFound)
            case (nil, _):
                // 只有 token 没有地址（例如 App Group 被清了）也当作未配对，重新配对会覆盖 token。
                return .notPaired
            }
        } catch {
            guard let endpoint else {
                return .notPaired
            }
            let reason = (error as? KeychainError) ?? .status(errSecInternalComponent)
            return .tokenUnavailable(endpoint: endpoint, reason: reason)
        }
    }

    /// 先写 Keychain：它可能失败；失败就不动地址，保证两边一致。
    public func save(_ info: PairingInfo) throws {
        try tokens.save(token: info.token)
        endpoints.save(info.endpoint)
    }

    /// 和 save 对称：先删 Keychain，失败就不动地址，重试即可（clearToken 把「本来就没有」当成功）。
    public func clear() throws {
        try tokens.clearToken()
        endpoints.clearEndpoint()
    }
}

// MARK: - App Group UserDefaults

public final class UserDefaultsEndpointStore: EndpointStore, @unchecked Sendable {
    public static let hostKey = "clipbridge.pairing.host"
    public static let portKey = "clipbridge.pairing.port"
    public static let pairedAtKey = "clipbridge.pairing.pairedAt"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 没有对应 App Group entitlement 时 `UserDefaults(suiteName:)` 不会返回 nil，而是给一个不共享的实例并只在控制台警告；
    /// 所以先用 `containerURL(forSecurityApplicationGroupIdentifier:)` 探测 entitlement，缺了就明确返回 nil。
    public convenience init?(appGroup: String) {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) != nil,
              let defaults = UserDefaults(suiteName: appGroup) else {
            return nil
        }
        self.init(defaults: defaults)
    }

    public func loadEndpoint() -> PairingEndpoint? {
        guard let host = defaults.string(forKey: Self.hostKey), PairingEndpoint.isValidHost(host) else {
            return nil
        }
        let port = defaults.integer(forKey: Self.portKey)
        guard PairingEndpoint.isValidPort(port) else {
            return nil
        }
        return PairingEndpoint(host: host, port: port)
    }

    public func save(_ endpoint: PairingEndpoint) {
        defaults.set(endpoint.host, forKey: Self.hostKey)
        defaults.set(endpoint.port, forKey: Self.portKey)
        defaults.set(Date(), forKey: Self.pairedAtKey)
    }

    public func clearEndpoint() {
        defaults.removeObject(forKey: Self.hostKey)
        defaults.removeObject(forKey: Self.portKey)
        defaults.removeObject(forKey: Self.pairedAtKey)
    }

    public var pairedAt: Date? {
        defaults.object(forKey: Self.pairedAtKey) as? Date
    }
}

// MARK: - In-memory（测试、SwiftUI 预览）

public final class InMemoryEndpointStore: EndpointStore, @unchecked Sendable {
    private let lock = NSLock()
    private var endpoint: PairingEndpoint?

    public init(endpoint: PairingEndpoint? = nil) {
        self.endpoint = endpoint
    }

    public func loadEndpoint() -> PairingEndpoint? {
        lock.lock(); defer { lock.unlock() }
        return endpoint
    }

    public func save(_ endpoint: PairingEndpoint) {
        lock.lock(); defer { lock.unlock() }
        self.endpoint = endpoint
    }

    public func clearEndpoint() {
        lock.lock(); defer { lock.unlock() }
        endpoint = nil
    }
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?
    private var failure: KeychainError?

    /// `failure` 设定后所有操作都抛它，用来模拟「键盘没开完全访问」「设备未解锁」等情况。
    public init(token: String? = nil, failure: KeychainError? = nil) {
        self.token = token
        self.failure = failure
    }

    public func setFailure(_ failure: KeychainError?) {
        lock.lock(); defer { lock.unlock() }
        self.failure = failure
    }

    public func loadToken() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        return token
    }

    public func save(token: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        self.token = token
    }

    public func clearToken() throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        token = nil
    }
}
