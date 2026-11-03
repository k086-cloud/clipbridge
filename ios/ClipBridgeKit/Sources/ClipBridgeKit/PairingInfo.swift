import Foundation

/// 电脑端服务的地址。单独成类型，因为它和 token 存在不同的地方（App Group vs Keychain）。
public struct PairingEndpoint: Codable, Equatable, Hashable, Sendable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// host 只允许主机名 / IPv4 / IPv6 字面量：非空、无空白、不含 URL 分隔符。
    public static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/?#@\\[]"))
        return host.rangeOfCharacter(from: forbidden) == nil
    }

    public static func isValidPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }

    /// `http://host:port`；IPv6 字面量自动加方括号。
    public var baseURL: URL {
        let hostPart = host.contains(":") ? "[\(host)]" : host
        if let url = URL(string: "http://\(hostPart):\(port)") {
            return url
        }
        // host 含非法字符时百分号编码再试；这种值本不该被存下来（解析和输入都会先校验）。
        let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "invalid"
        return URL(string: "http://\(encoded):\(port)")!
    }
}

/// 一次配对得到的全部信息。JSON 形状是扁平的 {"host","port","token"}，和二维码里的字段一致。
public struct PairingInfo: Codable, Equatable, Hashable, Sendable {
    public var endpoint: PairingEndpoint
    public var token: String

    public init(endpoint: PairingEndpoint, token: String) {
        self.endpoint = endpoint
        self.token = token
    }

    public init(host: String, port: Int, token: String) {
        self.init(endpoint: PairingEndpoint(host: host, port: port), token: token)
    }

    public var host: String { endpoint.host }
    public var port: Int { endpoint.port }
    public var baseURL: URL { endpoint.baseURL }

    private enum CodingKeys: String, CodingKey {
        case host, port, token
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let host = try container.decode(String.self, forKey: .host)
        let port = try container.decode(Int.self, forKey: .port)
        let token = try container.decode(String.self, forKey: .token)
        self.init(host: host, port: port, token: token)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(endpoint.host, forKey: .host)
        try container.encode(endpoint.port, forKey: .port)
        try container.encode(token, forKey: .token)
    }
}
