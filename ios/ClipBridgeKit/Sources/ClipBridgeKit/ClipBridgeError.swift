import Foundation

/// ClipBridgeClient 抛出的全部错误。状态码按 CLAUDE.md 的 API 契约映射。
public enum ClipBridgeError: Error, Equatable, Sendable {
    /// 401：token 不对（或没带）。
    case unauthorized
    /// 404：`latest()` 已经把它变成 nil，这里只给其他接口兜底。
    case notFound
    /// 413：服务端判定超过 max_text_bytes。
    case payloadTooLarge
    /// 422：参数不合法（history 的 limit 超范围、content 为空等）。附服务端的说明。
    case unprocessable(String)
    /// 503：写电脑剪贴板失败。
    case clipboardUnavailable(String)
    case unexpectedStatus(Int)
    /// 发送前的本地检查：空内容服务端会 422，直接拦下。
    case contentEmpty
    /// 发送前的本地检查：UTF-8 字节数超过 max_text_bytes。
    case contentTooLarge(bytes: Int, limit: Int)
    case invalidURL
    /// 不是 HTTP 响应，或 JSON 解不出来。
    case invalidResponse
    /// 网络层错误（超时、拒绝连接、本地网络权限被拒等）。
    case transport(URLError.Code)

    /// -1009。在局域网场景下通常就是「本地网络」权限被拒，也可能是真的没网。
    public var isOfflineOrLocalNetworkDenied: Bool {
        self == .transport(.notConnectedToInternet)
    }

    /// -1022：ATS 拦截了明文 HTTP。出现说明 Info.plist 少了 NSAllowsLocalNetworking。
    public var isBlockedByATS: Bool {
        self == .transport(.appTransportSecurityRequiresSecureConnection)
    }
}

/// FastAPI 的错误体：HTTPException 是 {"detail": "..."}，参数校验（422）是 {"detail": [{"msg": ...}, ...]}。
struct ServerErrorBody: Decodable {
    let message: String

    private enum CodingKeys: String, CodingKey {
        case detail
    }

    private struct ValidationItem: Decodable {
        let msg: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .detail) {
            message = text
        } else if let items = try? container.decode([ValidationItem].self, forKey: .detail) {
            message = items.compactMap(\.msg).joined(separator: "; ")
        } else {
            message = ""
        }
    }

    static func message(from data: Data) -> String {
        (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.message ?? ""
    }
}
