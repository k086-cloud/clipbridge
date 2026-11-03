import XCTest
@testable import ClipBridgeKit

/// 错误体的文案都是从真实服务端（windows-server，FastAPI TestClient）抓下来的，别随手改。
final class ClipBridgeClientTests: XCTestCase {
    private var client: ClipBridgeClient!

    private let sampleItem = #"{"id":"3f2a","content":"hello","timestamp":"2026-11-01T21:51:00.123+08:00","source":"pc"}"#
    private let healthBody = #"{"status":"ok","version":"0.2.0","history_items":3,"monitor_running":true,"uptime_seconds":12.5,"max_text_bytes":102400,"history_size":20}"#

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        client = ClipBridgeClient(
            baseURL: URL(string: "http://192.168.1.10:8765")!,
            token: "secret-token",
            session: makeMockSession()
        )
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: health

    func testHealthDecodesServerStatusWithoutAuthorizationHeader() async throws {
        MockURLProtocol.handler = { _ in (200, json(self.healthBody)) }
        let health = try await client.health()
        XCTAssertTrue(health.isOK)
        XCTAssertEqual(health.version, "0.2.0")
        XCTAssertEqual(health.historyItems, 3)
        XCTAssertTrue(health.monitorRunning)
        XCTAssertEqual(health.uptimeSeconds, 12.5)
        XCTAssertEqual(health.maxTextBytes, 102_400)
        XCTAssertEqual(health.historySize, 20)
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "http://192.168.1.10:8765/health")
        XCTAssertNil(request.headers["Authorization"])
    }

    func testHealthAcceptsOldServerWithoutLimitFields() async throws {
        MockURLProtocol.handler = { _ in
            (200, json(#"{"status":"ok","version":"0.1.0","history_items":0,"monitor_running":false,"uptime_seconds":0.0}"#))
        }
        let health = try await client.health()
        XCTAssertTrue(health.isOK)
        XCTAssertNil(health.maxTextBytes)
        XCTAssertNil(health.historySize)
    }

    func testHealthRejectsAServerThatIsNotClipBridge() async {
        // 随便一个 HTTP 服务也会对 /health 返回 200，但解不出 HealthResponse
        MockURLProtocol.handler = { _ in (200, json("<html><body>It works!</body></html>")) }
        await assertThrows(.invalidResponse) { try await self.client.health() }
    }

    func testHealthMapsUnexpectedStatus() async {
        MockURLProtocol.handler = { _ in (500, Data()) }
        await assertThrows(.unexpectedStatus(500)) { try await self.client.health() }
    }

    // MARK: latest

    func testLatestUsesHistoryLimitOneAndSendsBearerToken() async throws {
        MockURLProtocol.handler = { _ in (200, json(#"{"items":[\#(self.sampleItem)]}"#)) }
        let item = try await client.latest()
        XCTAssertEqual(item?.id, "3f2a")
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/clip/history")
        XCTAssertEqual(request.query, "limit=1")
        XCTAssertEqual(request.headers["Authorization"], "Bearer secret-token")
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }

    func testLatestReturnsNilOnEmptyHistory() async throws {
        MockURLProtocol.handler = { _ in (200, json(#"{"items":[]}"#)) }
        let item = try await client.latest()
        XCTAssertNil(item)
    }

    func testLatestOn404IsNotFoundNotEmpty() async {
        // 指错了 host：对面不是 ClipBridge，/clip/history 不存在。不能被当成「已配对但没内容」
        MockURLProtocol.handler = { _ in (404, json(#"{"detail":"Not Found"}"#)) }
        await assertThrows(.notFound) { try await self.client.latest() }
    }

    func testLatestMapsUnauthorized() async {
        MockURLProtocol.handler = { _ in (401, json(#"{"detail":"Missing or invalid bearer token."}"#)) }
        await assertThrows(.unauthorized) { try await self.client.latest() }
    }

    func testLatestWithUndecodableBodyIsInvalidResponse() async {
        MockURLProtocol.handler = { _ in (200, json("<html>")) }
        await assertThrows(.invalidResponse) { try await self.client.latest() }
    }

    // MARK: history

    func testHistoryPassesLimitAndKeepsOrder() async throws {
        MockURLProtocol.handler = { _ in
            (200, json(#"{"items":[\#(self.sampleItem),{"id":"old","content":"o","timestamp":"2026-11-01T21:50:00.000+08:00","source":"phone"}]}"#))
        }
        let items = try await client.history(limit: 5)
        XCTAssertEqual(items.map(\.id), ["3f2a", "old"])
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/clip/history")
        XCTAssertEqual(request.query, "limit=5")
    }

    func testHistoryWithoutLimitSendsNoQuery() async throws {
        MockURLProtocol.handler = { _ in (200, json(#"{"items":[]}"#)) }
        let items = try await client.history()
        XCTAssertTrue(items.isEmpty)
        XCTAssertNil(MockURLProtocol.requests.first?.query)
    }

    func testHistoryMapsValidationErrorWithArrayDetail() async {
        MockURLProtocol.handler = { _ in
            (422, json(#"{"detail":[{"type":"less_than_equal","loc":["query","limit"],"msg":"Input should be less than or equal to 5","input":"6","ctx":{"le":5}}]}"#))
        }
        await assertThrows(.unprocessable("Input should be less than or equal to 5")) {
            try await self.client.history(limit: 6)
        }
    }

    func testRecentHistoryFallsBackToOneItemOn422() async throws {
        MockURLProtocol.handler = { request in
            if request.query == "limit=5" {
                return (422, json(#"{"detail":[{"msg":"Input should be less than or equal to 3"}]}"#))
            }
            return (200, json(#"{"items":[\#(self.sampleItem)]}"#))
        }
        let items = try await client.recentHistory(preferredLimit: 5)
        XCTAssertEqual(items.map(\.id), ["3f2a"])
        XCTAssertEqual(MockURLProtocol.requests.map(\.query), ["limit=5", "limit=1"])
    }

    func testRecentHistoryWithPreferredLimitOneDoesNotRetry() async {
        MockURLProtocol.handler = { _ in (422, json(#"{"detail":[{"msg":"bad limit"}]}"#)) }
        await assertThrows(.unprocessable("bad limit")) { try await self.client.recentHistory(preferredLimit: 1) }
        XCTAssertEqual(MockURLProtocol.requests.map(\.query), ["limit=1"])
    }

    func testRecentHistoryGivesUpWhenFallbackAlso422() async {
        MockURLProtocol.handler = { _ in (422, json(#"{"detail":[{"msg":"still bad"}]}"#)) }
        await assertThrows(.unprocessable("still bad")) { try await self.client.recentHistory(preferredLimit: 5) }
        XCTAssertEqual(MockURLProtocol.requests.map(\.query), ["limit=5", "limit=1"])
    }

    func testRecentHistoryDoesNotRetryOtherErrors() async {
        MockURLProtocol.handler = { _ in (401, Data()) }
        await assertThrows(.unauthorized) { try await self.client.recentHistory(preferredLimit: 5) }
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    // MARK: send

    func testSendPostsJSONBodyAndAccepts201() async throws {
        MockURLProtocol.handler = { _ in (201, json(#"{"id":"n","content":"你好 world","timestamp":"2026-11-01T21:51:00.123+08:00","source":"phone"}"#)) }
        try await client.send("你好 world")
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/clip")
        XCTAssertEqual(request.headers["Authorization"], "Bearer secret-token")
        XCTAssertEqual(request.headers["Content-Type"], "application/json; charset=utf-8")
        let body = try XCTUnwrap(request.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(object, ["content": "你好 world"])
    }

    func testSendTreatsWhole2xxRangeAsSuccess() async {
        for status in [200, 204, 299] {
            MockURLProtocol.handler = { _ in (status, Data()) }
            do {
                try await client.send("x")
            } catch {
                XCTFail("\(status) should succeed, got \(error)")
            }
        }
        for status in [199, 300, 302] {
            MockURLProtocol.handler = { _ in (status, Data()) }
            await assertThrows(.unexpectedStatus(status)) { try await self.client.send("x") }
        }
    }

    func testSendRejectsEmptyTextLocally() async {
        await assertThrows(.contentEmpty) { try await self.client.send("") }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testSendRejectsOversizedTextLocallyByUTF8Bytes() async {
        let small = ClipBridgeClient(baseURL: client.baseURL, token: "t", session: makeMockSession(), maxTextBytes: 10)
        // 4 个汉字 = 12 字节 > 10，虽然只有 4 个字符
        await assertThrows(.contentTooLarge(bytes: 12, limit: 10)) { try await small.send("你好世界") }
        XCTAssertTrue(MockURLProtocol.requests.isEmpty)
    }

    func testSendAcceptsTextExactlyAtLimit() async throws {
        // 服务端 text_too_large 是 `> max_bytes`，恰好等于上限要能发出去
        MockURLProtocol.handler = { _ in (201, json(#"{"id":"n","content":"你好世界","timestamp":"2026-11-01T21:51:00.123+08:00","source":"phone"}"#)) }
        let small = ClipBridgeClient(baseURL: client.baseURL, token: "t", session: makeMockSession(), maxTextBytes: 12)
        try await small.send("你好世界")
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testSendMapsServerErrors() async {
        MockURLProtocol.handler = { _ in (413, json(#"{"detail":"Text exceeds the 102400 byte limit."}"#)) }
        await assertThrows(.payloadTooLarge) { try await self.client.send("x") }

        MockURLProtocol.handler = { _ in
            (422, json(#"{"detail":[{"type":"string_too_short","loc":["body","content"],"msg":"String should have at least 1 character","input":"","ctx":{"min_length":1}}]}"#))
        }
        await assertThrows(.unprocessable("String should have at least 1 character")) { try await self.client.send("x") }

        MockURLProtocol.handler = { _ in (503, json(#"{"detail":"clipboard is locked"}"#)) }
        await assertThrows(.clipboardUnavailable("clipboard is locked")) { try await self.client.send("x") }
    }

    // MARK: transport

    func testTransportErrorsAreWrapped() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(.transport(.notConnectedToInternet)) { try await self.client.health() }
        XCTAssertTrue(ClipBridgeError.transport(.notConnectedToInternet).isOfflineOrLocalNetworkDenied)
        XCTAssertTrue(ClipBridgeError.transport(.appTransportSecurityRequiresSecureConnection).isBlockedByATS)
        XCTAssertTrue(ClipBridgeError.transport(.timedOut).isUnreachable)
        XCTAssertTrue(ClipBridgeError.transport(.cannotConnectToHost).isUnreachable)
        XCTAssertFalse(ClipBridgeError.transport(.timedOut).isOfflineOrLocalNetworkDenied)
    }

    func testNonURLErrorsAreWrappedToo() async {
        // 键盘扩展沙盒禁网时 URLSession 可能直接抛 POSIX EPERM，不是 URLError
        MockURLProtocol.handler = { _ in throw NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)) }
        await assertThrows(.underlying(domain: NSPOSIXErrorDomain, code: 1)) { try await self.client.health() }
        XCTAssertTrue(ClipBridgeError.underlying(domain: NSPOSIXErrorDomain, code: 1).isSandboxDenied)
        XCTAssertFalse(ClipBridgeError.underlying(domain: "Other", code: 1).isSandboxDenied)
    }

    func testInitFromPairingInfoUsesItsBaseURL() {
        let fromPairing = ClipBridgeClient(pairing: PairingInfo(host: "fe80::1", port: 9000, token: "t"))
        XCTAssertEqual(fromPairing.baseURL.absoluteString, "http://[fe80::1]:9000")
        XCTAssertEqual(fromPairing.token, "t")
        XCTAssertEqual(fromPairing.maxTextBytes, 102_400)
    }

    func testDefaultSessionHasShortTimeouts() {
        let configuration = ClipBridgeClient.makeSession().configuration
        XCTAssertEqual(configuration.timeoutIntervalForRequest, 3)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 5)
        XCTAssertFalse(configuration.waitsForConnectivity)
    }
}
