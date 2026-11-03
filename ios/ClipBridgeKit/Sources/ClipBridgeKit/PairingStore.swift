import Foundation
import Security

/// 读出来的配对状态。UI 按它决定显示什么：
/// - notPaired：引导去主 App 配对
/// - paired：正常工作
/// - tokenUnavailable：App Group 里有地址但 Keychain 读不到 token。键盘没开「允许完全访问」、
///   设备还没首次解锁、entitlement 不匹配，都落在这里，由 reason 区分。
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
    /// Info.plist 没有 AppIdentifierPrefix、或 App Group 的 UserDefaults 建不出来时返回 nil——
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

    public func clear() throws {
        endpoints.clearEndpoint()
        try tokens.clearToken()
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

    /// `UserDefaults(suiteName:)` 在没有对应 App Group entitlement 时返回的是一个无法共享的实例，
    /// 在 suite 名非法时返回 nil；两种情况都只会出现在工程配置错误时。
    public convenience init?(appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else {
            return nil
        }
        self.init(defaults: defaults)
    }

    public func loadEndpoint() -> PairingEndpoint? {
        guard let host = defaults.string(forKey: Self.hostKey), !host.isEmpty else {
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
