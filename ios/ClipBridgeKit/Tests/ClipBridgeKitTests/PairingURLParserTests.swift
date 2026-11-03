import XCTest
@testable import ClipBridgeKit

final class PairingURLParserTests: XCTestCase {
    func testParsesCanonicalURL() throws {
        let info = try PairingURLParser.parse("clipbridge://pair?host=192.168.1.10&port=8765&token=abc-DEF_123")
        XCTAssertEqual(info, PairingInfo(host: "192.168.1.10", port: 8765, token: "abc-DEF_123"))
    }

    func testParsesURLValue() throws {
        let url = try XCTUnwrap(URL(string: "clipbridge://pair?host=my-pc.local&port=1&token=t"))
        let info = try PairingURLParser.parse(url)
        XCTAssertEqual(info.host, "my-pc.local")
        XCTAssertEqual(info.port, 1)
        XCTAssertEqual(info.token, "t")
    }

    func testDecodesPercentEncodedToken() throws {
        let info = try PairingURLParser.parse("clipbridge://pair?host=10.0.0.2&port=8765&token=a%2Bb%3Dc%2Fd")
        XCTAssertEqual(info.token, "a+b=c/d")
    }

    func testSchemeAndActionAreCaseInsensitive() throws {
        let info = try PairingURLParser.parse("CLIPBRIDGE://PAIR?host=10.0.0.2&port=8765&token=t")
        XCTAssertEqual(info.port, 8765)
    }

    func testTrimsSurroundingWhitespace() throws {
        let info = try PairingURLParser.parse("  clipbridge://pair?host=10.0.0.2&port=8765&token=t\n")
        XCTAssertEqual(info.host, "10.0.0.2")
    }

    func testIgnoresExtraParametersAndUsesFirstDuplicate() throws {
        let info = try PairingURLParser.parse("clipbridge://pair?x=1&host=a.local&host=b.local&port=8765&token=t&y=2")
        XCTAssertEqual(info.host, "a.local")
    }

    func testIPv6HostIsAcceptedAndBracketedInBaseURL() throws {
        let info = try PairingURLParser.parse("clipbridge://pair?host=fe80::1&port=8765&token=t")
        XCTAssertEqual(info.host, "fe80::1")
        XCTAssertEqual(info.baseURL.absoluteString, "http://[fe80::1]:8765")
    }

    func testRejectsOtherScheme() {
        XCTAssertThrowsError(try PairingURLParser.parse("https://pair?host=10.0.0.2&port=8765&token=t")) { error in
            XCTAssertEqual(error as? PairingURLError, .wrongScheme("https"))
        }
    }

    func testRejectsOtherAction() {
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://unpair?host=10.0.0.2&port=8765&token=t")) { error in
            XCTAssertEqual(error as? PairingURLError, .wrongAction("unpair"))
        }
    }

    func testRejectsMissingParameters() {
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?port=8765&token=t")) { error in
            XCTAssertEqual(error as? PairingURLError, .missingHost)
        }
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?host=&port=8765&token=t")) { error in
            XCTAssertEqual(error as? PairingURLError, .missingHost)
        }
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?host=10.0.0.2&token=t")) { error in
            XCTAssertEqual(error as? PairingURLError, .missingPort)
        }
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?host=10.0.0.2&port=8765")) { error in
            XCTAssertEqual(error as? PairingURLError, .missingToken)
        }
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?host=10.0.0.2&port=8765&token=")) { error in
            XCTAssertEqual(error as? PairingURLError, .missingToken)
        }
    }

    func testRejectsBadPorts() {
        for bad in ["0", "65536", "-1", "abc", "80.5"] {
            XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?host=10.0.0.2&port=\(bad)&token=t")) { error in
                XCTAssertEqual(error as? PairingURLError, .invalidPort(bad), "port \(bad)")
            }
        }
    }

    func testRejectsHostWithSpacesOrSeparators() {
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?host=a%20b&port=8765&token=t")) { error in
            XCTAssertEqual(error as? PairingURLError, .invalidHost("a b"))
        }
        XCTAssertThrowsError(try PairingURLParser.parse("clipbridge://pair?host=evil.com%2Fpath&port=8765&token=t")) { error in
            XCTAssertEqual(error as? PairingURLError, .invalidHost("evil.com/path"))
        }
    }

    func testRejectsGarbage() {
        // iOS 17+/macOS 14+ 的 URLComponents 很宽松：没有 scheme 的文本会被当成相对路径解析成功，落到 wrongScheme(nil)
        let cases: [(String, PairingURLError)] = [
            ("", .notAURL),
            ("   ", .notAURL),
            ("http://[bad", .notAURL),
            ("not a url at all", .wrongScheme(nil)),
            ("pair?host=1&port=2&token=3", .wrongScheme(nil)),
        ]
        for (text, expected) in cases {
            XCTAssertThrowsError(try PairingURLParser.parse(text), "input: \(text)") { error in
                XCTAssertEqual(error as? PairingURLError, expected, "input: \(text)")
            }
        }
    }
}
