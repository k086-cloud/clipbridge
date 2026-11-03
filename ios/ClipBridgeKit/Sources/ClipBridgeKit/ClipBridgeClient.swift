import Foundation

/// Windows 端 FastAPI 服务的客户端，主 App、键盘、共享扩展共用。
/// 只做纯文本；任何 2xx 都算成功（POST /clip 返回 201）。
public struct ClipBridgeClient: Sendable {
    public let baseURL: URL
    public let token: String
    /// 和服务端 max_text_bytes 保持一致；发送前在本地先拦。
    public let maxTextBytes: Int
    private let session: URLSession

    public init(
        baseURL: URL,
        token: String,
        session: URLSession = ClipBridgeClient.makeSession(),
        maxTextBytes: Int = ClipBridgeIdentifiers.defaultMaxTextBytes
    ) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
        self.maxTextBytes = maxTextBytes
    }

    public init(
        pairing: PairingInfo,
        session: URLSession = ClipBridgeClient.makeSession(),
        maxTextBytes: Int = ClipBridgeIdentifiers.defaultMaxTextBytes
    ) {
        self.init(baseURL: pairing.baseURL, token: pairing.token, session: session, maxTextBytes: maxTextBytes)
    }

    /// 键盘扩展里不能让请求挂 60 秒：电脑关机时局域网 TCP 会一直重试。
    /// `URLSession.shared` 改不了超时，所以用独立的 ephemeral 配置。
    public static func makeSession(requestTimeout: TimeInterval = 3, resourceTimeout: TimeInterval = 5) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: - API

    /// GET /health，免鉴权。
    public func health() async throws {
        let request = try makeRequest(method: "GET", path: "/health", authorized: false)
        let (data, response) = try await perform(request)
        try check(response, data)
    }

    /// GET /clip/latest；历史为空时服务端 404，这里返回 nil（token 正确只是没内容，不算失败）。
    public func latest() async throws -> ClipItem? {
        let request = try makeRequest(method: "GET", path: "/clip/latest")
        let (data, response) = try await perform(request)
        if response.statusCode == 404 {
            return nil
        }
        try check(response, data)
        return try decode(ClipItem.self, from: data)
    }

    /// GET /clip/history?limit=N，最新在前。limit 省略时服务端返回全部（最多 history_size 条）。
    /// limit 超过服务端 history_size 会得到 422，见 `recentHistory(preferredLimit:)`。
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

    /// 键盘用：先按 preferredLimit 拉；服务端 history_size 比它小会 422，那就退化成 1 条。
    /// 不能用「不传 limit」兜底——那会把全部历史（最多 20 条 × 100 KB）拉进键盘进程。
    public func recentHistory(preferredLimit: Int = 5) async throws -> [ClipItem] {
        do {
            return try await history(limit: preferredLimit)
        } catch ClipBridgeError.unprocessable where preferredLimit > 1 {
            return try await history(limit: 1)
        }
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

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ClipBridgeError.transport(error.code)
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
        case 413: throw ClipBridgeError.payloadTooLarge
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
