import XCTest
@testable import ClipBridgeKit

final class ClipBridgeClientTests: XCTestCase {
    private var client: ClipBridgeClient!

    private let sampleItem = #"{"id":"3f2a","content":"hello","timestamp":"2026-11-01T21:51:00.123+08:00","source":"pc"}"#

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

    func testHealthSendsNoAuthorizationHeader() async throws {
        MockURLProtocol.handler = { _ in (200, json(#"{"status":"ok"}"#)) }
        try await client.health()
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "http://192.168.1.10:8765/health")
        XCTAssertNil(request.headers["Authorization"])
    }

    func testHealthMapsUnexpectedStatus() async {
        MockURLProtocol.handler = { _ in (500, Data()) }
        await assertThrows(.unexpectedStatus(500)) { try await self.client.health() }
    }

    // MARK: latest

    func testLatestSendsBearerTokenAndDecodesItem() async throws {
        MockURLProtocol.handler = { _ in (200, json(self.sampleItem)) }
        let item = try await client.latest()
        XCTAssertEqual(item?.id, "3f2a")
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.path, "/clip/latest")
        XCTAssertEqual(request.headers["Authorization"], "Bearer secret-token")
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }

    func testLatestReturnsNilOnEmptyHistory() async throws {
        MockURLProtocol.handler = { _ in (404, json(#"{"detail":"No clipboard history yet"}"#)) }
        let item = try await client.latest()
        XCTAssertNil(item)
    }

    func testLatestMapsUnauthorized() async {
        MockURLProtocol.handler = { _ in (401, json(#"{"detail":"Invalid or missing token"}"#)) }
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
            (422, json(#"{"detail":[{"type":"less_than_equal","loc":["query","limit"],"msg":"Input should be less than or equal to 3","input":"5"}]}"#))
        }
        await assertThrows(.unprocessable("Input should be less than or equal to 3")) {
            try await self.client.history(limit: 5)
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

    func testSendMapsServerErrors() async {
        MockURLProtocol.handler = { _ in (413, json(#"{"detail":"Text exceeds 102400 bytes"}"#)) }
        await assertThrows(.payloadTooLarge) { try await self.client.send("x") }

        MockURLProtocol.handler = { _ in (422, json(#"{"detail":[{"msg":"content must not be empty"}]}"#)) }
        await assertThrows(.unprocessable("content must not be empty")) { try await self.client.send("x") }

        MockURLProtocol.handler = { _ in (503, json(#"{"detail":"Could not write to the clipboard"}"#)) }
        await assertThrows(.clipboardUnavailable("Could not write to the clipboard")) { try await self.client.send("x") }
    }

    // MARK: transport

    func testTransportErrorsAreWrapped() async {
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await assertThrows(.transport(.notConnectedToInternet)) { try await self.client.health() }
        XCTAssertTrue(ClipBridgeError.transport(.notConnectedToInternet).isOfflineOrLocalNetworkDenied)
        XCTAssertTrue(ClipBridgeError.transport(.appTransportSecurityRequiresSecureConnection).isBlockedByATS)
        XCTAssertFalse(ClipBridgeError.transport(.timedOut).isOfflineOrLocalNetworkDenied)
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
