import XCTest
@testable import ClipBridgeKit

final class PairingInfoTests: XCTestCase {
    func testJSONIsFlatAndRoundTrips() throws {
        let info = PairingInfo(host: "192.168.1.10", port: 8765, token: "tok")
        let data = try JSONEncoder().encode(info)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["host"] as? String, "192.168.1.10")
        XCTAssertEqual(object["port"] as? Int, 8765)
        XCTAssertEqual(object["token"] as? String, "tok")
        XCTAssertEqual(object.count, 3)

        let decoded = try JSONDecoder().decode(PairingInfo.self, from: data)
        XCTAssertEqual(decoded, info)
    }

    func testDecodesFlatJSON() throws {
        let decoded = try JSONDecoder().decode(PairingInfo.self, from: json(#"{"host":"pc.local","port":1234,"token":"t"}"#))
        XCTAssertEqual(decoded.endpoint, PairingEndpoint(host: "pc.local", port: 1234))
        XCTAssertEqual(decoded.token, "t")
    }

    func testBaseURL() {
        XCTAssertEqual(PairingEndpoint(host: "192.168.1.10", port: 8765).baseURL.absoluteString, "http://192.168.1.10:8765")
        XCTAssertEqual(PairingEndpoint(host: "my-pc.local", port: 80).baseURL.absoluteString, "http://my-pc.local:80")
        XCTAssertEqual(PairingEndpoint(host: "fe80::1", port: 8765).baseURL.absoluteString, "http://[fe80::1]:8765")
    }

    func testHostValidation() {
        XCTAssertTrue(PairingEndpoint.isValidHost("192.168.1.10"))
        XCTAssertTrue(PairingEndpoint.isValidHost("my-pc.local"))
        XCTAssertTrue(PairingEndpoint.isValidHost("fe80::1"))
        XCTAssertFalse(PairingEndpoint.isValidHost(""))
        XCTAssertFalse(PairingEndpoint.isValidHost("a b"))
        XCTAssertFalse(PairingEndpoint.isValidHost("host/path"))
        XCTAssertFalse(PairingEndpoint.isValidHost("user@host"))
        XCTAssertFalse(PairingEndpoint.isValidHost("[fe80::1]"))
    }

    func testPortValidation() {
        XCTAssertTrue(PairingEndpoint.isValidPort(1))
        XCTAssertTrue(PairingEndpoint.isValidPort(65535))
        XCTAssertFalse(PairingEndpoint.isValidPort(0))
        XCTAssertFalse(PairingEndpoint.isValidPort(65536))
    }
}
