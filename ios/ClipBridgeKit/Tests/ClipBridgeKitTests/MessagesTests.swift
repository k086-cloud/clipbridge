import XCTest
@testable import ClipBridgeKit

final class MessagesTests: XCTestCase {
    func testEveryClipBridgeErrorHasAMessage() {
        let errors: [ClipBridgeError] = [
            .unauthorized, .notFound, .serverOutdated, .payloadTooLarge(""), .payloadTooLarge("Text exceeds the 1024 byte limit."), .unprocessable(""), .unprocessable("x"),
            .clipboardUnavailable(""), .unexpectedStatus(500), .contentEmpty, .contentTooLarge(bytes: 2, limit: 1),
            .invalidURL, .invalidResponse, .transport(.notConnectedToInternet), .transport(.timedOut),
            .transport(.badServerResponse), .underlying(domain: NSPOSIXErrorDomain, code: 1), .underlying(domain: "x", code: 9),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
        }
        XCTAssertTrue(ClipBridgeError.transport(.notConnectedToInternet).localizedDescription.contains("本地网络"))
        XCTAssertTrue(ClipBridgeError.underlying(domain: NSPOSIXErrorDomain, code: 1).localizedDescription.contains("允许完全访问"))
        XCTAssertTrue(ClipBridgeError.serverOutdated.localizedDescription.contains("版本太旧"))
    }

    func testKeychainAndPairingErrorsHaveMessages() {
        for error in [KeychainError.itemNotFound, .interactionNotAllowed, .missingEntitlement, .notAvailable, .duplicateItem, .unexpectedData, .status(-50)] {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
        }
        for error in [PairingURLError.notAURL, .wrongScheme(nil), .wrongScheme("https"), .wrongAction("x"), .missingHost, .invalidHost("a b"), .missingPort, .invalidPort("0"), .missingToken] {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
        }
    }
}
