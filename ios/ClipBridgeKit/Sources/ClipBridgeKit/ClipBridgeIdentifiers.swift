import Foundation

/// 三个 target 共用的固定标识，和 Xcode 工程里的 capability 配置一一对应。
/// 这些值已经注册到 Personal Team，改之前先改工程，并且注意每周只能注册 10 个 App ID。
public enum ClipBridgeIdentifiers {
    /// App Groups capability 里的组名（主 App、键盘、共享扩展都有）。存 host/port。
    public static let appGroup = "group.com.charleschen.ClipBridge"

    /// Keychain Sharing capability 里的组名。运行时必须带 Team ID 前缀，见 `KeychainAccessGroup`。
    public static let keychainAccessGroupSuffix = "com.charleschen.clipbridge.shared"

    /// Keychain 里存 token 的条目（kSecClassGenericPassword）。
    public static let keychainService = "com.charleschen.clipbridge.pairing"
    public static let keychainTokenAccount = "token"

    /// 配对二维码：clipbridge://pair?host=<ip>&port=<port>&token=<token>
    public static let urlScheme = "clipbridge"
    public static let pairingAction = "pair"

    /// 服务端 max_text_bytes 的默认值（UTF-8 字节数），超过返回 413。
    public static let defaultMaxTextBytes = 102_400
}
