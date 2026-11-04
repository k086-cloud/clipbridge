import Foundation

/// Windows 端 FastAPI 服务的客户端，主 App、键盘、共享扩展共用。
/// 只做纯文本；任何 2xx 都算成功（POST /clip 返回 201）。
public struct ClipBridgeClient: Sendable {
    public let baseURL: URL
    public let token: String
    /// 和服务端 max_text_bytes 保持一致；发送前在本地先拦。服务端 0.2.0 起 /health 会报告实际值。
    public let maxTextBytes: Int
    private let session: URLSession

    public init(
        baseURL: URL,
        token: String,
        session: URLSession = ClipBridgeClient.defaultSession,
        maxTextBytes: Int = ClipBridgeIdentifiers.defaultMaxTextBytes
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.maxTextBytes = maxTextBytes
    }

    public init(
        pairing: PairingInfo,
        session: URLSession = ClipBridgeClient.defaultSession,
        maxTextBytes: Int = ClipBridgeIdentifiers.defaultMaxTextBytes
    ) {
        self.init(baseURL: pairing.baseURL, token: pairing.token, session: session, maxTextBytes: maxTextBytes)
    }

    /// 整个进程共用一个 session：URLSession 跑过任务后会一直活到 invalidate 为止，
    /// 每建一个 client 就 makeSession() 一次会在键盘扩展里慢慢堆内存。
    public static let defaultSession: URLSession = makeSession()

    /// 键盘扩展里不能让请求挂 60 秒：电脑关机时局域网 TCP 会一直重试。
    /// `URLSession.shared` 改不了超时，所以用独立的 ephemeral 配置。
    /// 需要别的超时时调用它，但要自己长期持有返回的 session（或用完 finishTasksAndInvalidate），不要每次请求都新建。
    public static func makeSession(requestTimeout: TimeInterval = 3, resourceTimeout: TimeInterval = 5) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - API

    /// GET /health，免鉴权。响应体必须能解成 HealthResponse——这是「对面确实是 ClipBridge 服务」的依据。
    @discardableResult
    public func health() async throws -> HealthResponse {
        let request = try makeRequest(method: "GET", path: "/health", authorized: false)
        let (data, response) = try await perform(request)
        try check(response, data)
        return try decode(HealthResponse.self, from: data)
    }

    /// 最新一条；历史为空时返回 nil。
    /// 走 `GET /clip/history?limit=1` 而不是 `/clip/latest`：后者用 404 表示「没内容」，
    /// 和「host 指错、对面根本不是 ClipBridge」的 404 分不开；history 为空时是 200 + 空数组，含义明确。
    public func latest() async throws -> ClipItem? {
        try await history(limit: 1).first
    }

    /// GET /clip/history?limit=N，最新在前。limit 省略时服务端返回全部（最多 history_size 条）。
    /// 服务端 0.1 对超过 history_size 的 limit 返回 422（0.2.0 起改为截断），见 `recentHistory(preferredLimit:)`。
    public func history(limit: Int? = nil) async throws -> [ClipItem] {
        var query: [URLQueryItem] = []
        if let limit {
            query.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        let request = try makeRequest(method: "GET", path: "/clip/history", query: query)
        let (data, response) = try await perform(request)
        try check(response, data)
        return try decode(HistoryResponse.self, from: data).items
    }

    /// 键盘用：先按 preferredLimit 拉；旧服务端 history_size 比它小会 422，那就退化成 1 条。
    /// 不能用「不传 limit」兜底——那会把全部历史（最多 history_size 条 × max_text_bytes）拉进键盘进程。
    public func recentHistory(preferredLimit: Int = 5) async throws -> [ClipItem] {
        do {
            return try await history(limit: preferredLimit)
        } catch ClipBridgeError.unprocessable where preferredLimit > 1 {
            return try await history(limit: 1)
        }
    }

    /// DELETE /clip/history（服务端 0.3.0 起），清空电脑内存里的历史，成功是 204 无响应体。
    /// 只清历史，不动电脑当前的剪贴板；电脑复制新内容后才会再有记录。旧服务端返回 405 → `.serverOutdated`。
    public func clearHistory() async throws {
        let request = try makeRequest(method: "DELETE", path: "/clip/history")
        let (data, response) = try await perform(request)
        try check(response, data)
    }

    /// POST /clip {"content": text}，写进电脑剪贴板。空内容和超长内容在本地先拦。
    public func send(_ text: String) async throws {
        guard !text.isEmpty else {
            throw ClipBridgeError.contentEmpty
        }
        let bytes = text.utf8.count
        guard bytes <= maxTextBytes else {
            throw ClipBridgeError.contentTooLarge(bytes: bytes, limit: maxTextBytes)
        }
        let body = try ClipBridgeJSON.makeEncoder().encode(SendRequest(content: text))
        let request = try makeRequest(method: "POST", path: "/clip", jsonBody: body)
        let (data, response) = try await perform(request)
        try check(response, data)
    }

    // MARK: - Internals

    private struct SendRequest: Encodable {
        let content: String
    }

    private func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        jsonBody: Data? = nil,
        authorized: Bool = true
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ClipBridgeError.invalidURL
        }
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw ClipBridgeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let jsonBody {
            request.httpBody = jsonBody
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// 网络层的任何错误都收口成 ClipBridgeError，调用方不用再分辨 NSError 域。
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ClipBridgeError.transport(error.code)
        } catch {
            let nsError = error as NSError
            throw ClipBridgeError.underlying(domain: nsError.domain, code: nsError.code)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ClipBridgeError.invalidResponse
        }
        return (data, http)
    }

    private func check(_ response: HTTPURLResponse, _ data: Data) throws {
        guard !(200..<300).contains(response.statusCode) else {
            return
        }
        let message = ServerErrorBody.message(from: data)
        switch response.statusCode {
        case 401: throw ClipBridgeError.unauthorized
        case 404: throw ClipBridgeError.notFound
        case 405: throw ClipBridgeError.serverOutdated
        case 413: throw ClipBridgeError.payloadTooLarge(message)
        case 422: throw ClipBridgeError.unprocessable(message)
        case 503: throw ClipBridgeError.clipboardUnavailable(message)
        default: throw ClipBridgeError.unexpectedStatus(response.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try ClipBridgeJSON.makeDecoder().decode(type, from: data)
        } catch {
            throw ClipBridgeError.invalidResponse
        }
    }
}
