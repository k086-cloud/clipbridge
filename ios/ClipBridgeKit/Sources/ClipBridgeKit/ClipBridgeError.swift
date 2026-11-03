import Foundation

/// ClipBridgeClient 抛出的全部错误。状态码按 CLAUDE.md 的 API 契约映射。
public enum ClipBridgeError: Error, Equatable, Sendable {
    /// 401：token 不对（或没带）。
    case unauthorized
    /// 404：路径不存在——host/port 指向的不是 ClipBridge 服务（随便一个 HTTP 服务都会 404），或接口改名了。
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
    /// 不是 HTTP 响应，或 JSON 解不出来（/health 解不出来 = 对面不是 ClipBridge 服务）。
    case invalidResponse
    /// 网络层错误（超时、拒绝连接、本地网络权限被拒等）。
    case transport(URLError.Code)
    /// URLSession 抛出的非 URLError（例如键盘扩展沙盒禁网时的 POSIX EPERM）。
    case underlying(domain: String, code: Int)

    /// -1009。在局域网场景下通常就是「本地网络」权限被拒，也可能是真的没网。
    public var isOfflineOrLocalNetworkDenied: Bool {
        self == .transport(.notConnectedToInternet)
    }

    /// -1022：ATS 拦截了明文 HTTP。出现说明 Info.plist 少了 NSAllowsLocalNetworking。
    public var isBlockedByATS: Bool {
        self == .transport(.appTransportSecurityRequiresSecureConnection)
    }

    /// POSIX EPERM：进程根本没有联网权限——键盘扩展没开「允许完全访问」时是这个样子。
    public var isSandboxDenied: Bool {
        self == .underlying(domain: NSPOSIXErrorDomain, code: Int(EPERM))
    }

    /// 连不上：超时、拒绝连接、找不到主机。电脑没开服务、IP 变了、不在同一个 Wi-Fi 都落在这里。
    public var isUnreachable: Bool {
        switch self {
        case .transport(.timedOut), .transport(.cannotConnectToHost), .transport(.cannotFindHost),
             .transport(.networkConnectionLost), .transport(.dnsLookupFailed):
            return true
        default:
            return false
        }
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

    /// 解不出来（非 JSON、没有 detail）就给空串，调用方按状态码处理。
    static func message(from data: Data) -> String {
        (try? JSONDecoder().decode(ServerErrorBody.self, from: data))?.message ?? ""
    }
}
