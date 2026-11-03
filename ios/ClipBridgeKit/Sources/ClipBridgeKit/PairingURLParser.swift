import Foundation

public enum PairingURLError: Error, Equatable, Sendable {
    case notAURL
    /// 不是 clipbridge://
    case wrongScheme(String?)
    /// 不是 clipbridge://pair
    case wrongAction(String?)
    case missingHost
    case invalidHost(String)
    case missingPort
    case invalidPort(String)
    case missingToken
}

/// 解析配对二维码 / 配对链接：clipbridge://pair?host=<ip>&port=<port>&token=<token>
/// 查询参数会被 URLComponents 自动百分号解码；重复的参数取第一个；多余参数忽略。
public enum PairingURLParser {
    public static func parse(_ text: String) throws -> PairingInfo {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let components = URLComponents(string: trimmed) else {
            throw PairingURLError.notAURL
        }
        return try parse(components)
    }

    public static func parse(_ url: URL) throws -> PairingInfo {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw PairingURLError.notAURL
        }
        return try parse(components)
    }

    private static func parse(_ components: URLComponents) throws -> PairingInfo {
        guard components.scheme?.lowercased() == ClipBridgeIdentifiers.urlScheme else {
            throw PairingURLError.wrongScheme(components.scheme)
        }
        guard components.host?.lowercased() == ClipBridgeIdentifiers.pairingAction else {
            throw PairingURLError.wrongAction(components.host)
        }

        let items = components.queryItems ?? []
        func first(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard let host = first("host")?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw PairingURLError.missingHost
        }
        guard PairingEndpoint.isValidHost(host) else {
            throw PairingURLError.invalidHost(host)
        }
        guard let portText = first("port")?.trimmingCharacters(in: .whitespacesAndNewlines), !portText.isEmpty else {
            throw PairingURLError.missingPort
        }
        guard let port = Int(portText), PairingEndpoint.isValidPort(port) else {
            throw PairingURLError.invalidPort(portText)
        }
        guard let token = first("token"), !token.isEmpty else {
            throw PairingURLError.missingToken
        }
        return PairingInfo(host: host, port: port, token: token)
    }
}
