import XCTest
@testable import ClipBridgeKit

final class ServerErrorBodyTests: XCTestCase {
    func testStringDetail() {
        XCTAssertEqual(ServerErrorBody.message(from: json(#"{"detail":"Missing or invalid bearer token."}"#)), "Missing or invalid bearer token.")
    }

    func testValidationArrayJoinsMessages() {
        let body = #"{"detail":[{"loc":["query","limit"],"msg":"first"},{"loc":["body","content"],"msg":"second"}]}"#
        XCTAssertEqual(ServerErrorBody.message(from: json(body)), "first; second")
    }

    func testValidationItemsWithoutMsgAreSkipped() {
        XCTAssertEqual(ServerErrorBody.message(from: json(#"{"detail":[{"loc":["query"]},{"msg":"only"}]}"#)), "only")
        XCTAssertEqual(ServerErrorBody.message(from: json(#"{"detail":[]}"#)), "")
    }

    func testUnknownShapesGiveEmptyMessageWithoutThrowing() {
        for body in ["", "<html>", "{}", #"{"detail":null}"#, #"{"detail":{"msg":"object"}}"#, #"{"error":"x"}"#] {
            XCTAssertEqual(ServerErrorBody.message(from: json(body)), "", "body: \(body)")
        }
    }
}
