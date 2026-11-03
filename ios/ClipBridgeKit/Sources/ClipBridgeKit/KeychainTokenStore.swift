import Foundation
import Security

/// Keychain 的 OSStatus 按 UI 需要区分的几种情况分型。
public enum KeychainError: Error, Equatable, Sendable {
    /// -25300：没有这条。按 Apple 文档，查询一个本 target 无权访问的 access group 也返回这个码
    /// （不是 -34018），所以在只读的扩展里它也可能意味着 entitlement 配错了。
    case itemNotFound
    /// -25308：设备还没首次解锁，或条目的可访问级别比当前状态高。
    case interactionNotAllowed
    /// -34018：只在 SecItemAdd / SecItemDelete（save / clearToken）出现：指定的 access group 不在本 target 的
    /// entitlement 里（组名拼错、Team ID 前缀不对、少加了 capability）。
    case missingEntitlement
    /// -25291：没有可用的 Keychain。社区报告键盘没开「允许完全访问」时是这个。
    case notAvailable
    /// -25299：已存在（save 会先删再加，正常不会出现）。
    case duplicateItem
    /// 条目存在但不是 UTF-8 字符串。
    case unexpectedData
    case status(OSStatus)

    public init(status: OSStatus) {
        switch status {
        case errSecItemNotFound: self = .itemNotFound
        case errSecInteractionNotAllowed: self = .interactionNotAllowed
        case errSecMissingEntitlement: self = .missingEntitlement
        case errSecNotAvailable: self = .notAvailable
        case errSecDuplicateItem: self = .duplicateItem
        default: self = .status(status)
        }
    }

    public var status: OSStatus? {
        switch self {
        case .itemNotFound: return errSecItemNotFound
        case .interactionNotAllowed: return errSecInteractionNotAllowed
        case .missingEntitlement: return errSecMissingEntitlement
        case .notAvailable: return errSecNotAvailable
        case .duplicateItem: return errSecDuplicateItem
        case .unexpectedData: return nil
        case let .status(code): return code
        }
    }
}

/// 共享 Keychain 里的 token。只在真机上能真正跑；`swift test` 下没有签名和 access group，用 InMemoryTokenStore。
public struct KeychainTokenStore: TokenStore {
    public let service: String
    public let account: String
    /// 完整组名，例如 "L24ST657GM.com.charleschen.clipbridge.shared"（见 `KeychainAccessGroup.shared`）。
    public let accessGroup: String?

    public init(
        service: String = ClipBridgeIdentifiers.keychainService,
        account: String = ClipBridgeIdentifiers.keychainTokenAccount,
        accessGroup: String?
    ) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    public func loadToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw KeychainError.unexpectedData
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    /// 先删后加：覆盖写入时不受旧条目可访问级别的影响。
    public func save(token: String) throws {
        try clearToken()
        var attributes = baseQuery()
        attributes[kSecValueData as String] = Data(token.utf8)
        // 键盘可能在锁屏下被调起，所以不能用默认的 WhenUnlocked；局域网配对凭据没必要随备份迁移。
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    public func clearToken() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        #if os(macOS)
        // macOS 上 access group 只对 data protection keychain 生效；iOS 忽略这个键。
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
}

/// 共享 Keychain 组名的运行时形式：Team ID 前缀 + 组名。
/// 前缀来自 Info.plist 的 `AppIdentifierPrefix = $(AppIdentifierPrefix)`，构建时展开成 "L24ST657GM."。
public enum KeychainAccessGroup {
    public static let infoPlistKey = "AppIdentifierPrefix"

    public static func shared(bundle: Bundle = .main) -> String? {
        shared(appIdentifierPrefix: bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    public static func shared(appIdentifierPrefix: String?) -> String? {
        guard var prefix = appIdentifierPrefix?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prefix.isEmpty,
              !prefix.hasPrefix("$(") else {
            return nil
        }
        if !prefix.hasSuffix(".") {
            prefix += "."
        }
        return prefix + ClipBridgeIdentifiers.keychainAccessGroupSuffix
    }
}
