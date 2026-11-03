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

    func testInvalidEndpointNeverCrashesAndPointsNowhere() {
        // 值类型本身不校验；非法值的 baseURL 指向保留域名，请求会明确失败而不是打到别的地方
        for endpoint in [
            PairingEndpoint(host: "", port: 8765),
            PairingEndpoint(host: "a b/c", port: 99999),
            PairingEndpoint(host: "192.168.1.10", port: 0),
            PairingEndpoint(host: "user@pc", port: 1),
        ] {
            XCTAssertFalse(endpoint.isValid, "\(endpoint)")
            XCTAssertEqual(endpoint.baseURL.absoluteString, "http://invalid.invalid:1", "\(endpoint)")
        }
        XCTAssertTrue(PairingEndpoint(host: "192.168.1.10", port: 8765).isValid)
    }

    func testDecodingDoesNotValidateSoCallersMust() throws {
        // 契约：Codable 不校验，校验在边界（URL 解析、手动输入、存储读取）。这里把这个行为钉住。
        let decoded = try JSONDecoder().decode(PairingInfo.self, from: json(#"{"host":"","port":0,"token":""}"#))
        XCTAssertFalse(decoded.endpoint.isValid)
        XCTAssertFalse(PairingEndpoint.isValidHost(decoded.host))
        XCTAssertFalse(PairingEndpoint.isValidPort(decoded.port))

        XCTAssertThrowsError(try JSONDecoder().decode(PairingInfo.self, from: json(#"{"host":"h","port":"8765","token":"t"}"#)))
        XCTAssertThrowsError(try JSONDecoder().decode(PairingInfo.self, from: json(#"{"host":"h","port":8765}"#)))
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
        // 带端口的「IP:端口」不是主机名；含冒号只能是 IPv6 字面量
        XCTAssertFalse(PairingEndpoint.isValidHost("192.168.1.23:8765"))
        XCTAssertFalse(PairingEndpoint.isValidHost("mypc:8765"))
        XCTAssertFalse(PairingEndpoint.isValidHost("fe80::1%en0"))
        XCTAssertTrue(PairingEndpoint.isValidHost("::1"))
        XCTAssertTrue(PairingEndpoint.isValidHost("2001:db8::1"))
        XCTAssertTrue(PairingEndpoint.isIPv6Literal("::1"))
        XCTAssertFalse(PairingEndpoint.isIPv6Literal("192.168.1.23"))
    }

    func testPortValidation() {
        XCTAssertTrue(PairingEndpoint.isValidPort(1))
        XCTAssertTrue(PairingEndpoint.isValidPort(65535))
        XCTAssertFalse(PairingEndpoint.isValidPort(0))
        XCTAssertFalse(PairingEndpoint.isValidPort(65536))
    }
}
