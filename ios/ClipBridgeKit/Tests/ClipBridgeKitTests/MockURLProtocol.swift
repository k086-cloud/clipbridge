import Foundation
import XCTest
@testable import ClipBridgeKit

/// 拦截 URLSession 的请求：handler 决定返回的状态码和正文，或抛 URLError 模拟网络层错误。
final class MockURLProtocol: URLProtocol {
    typealias Handler = (RecordedRequest) throws -> (status: Int, body: Data)

    struct RecordedRequest {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?

        var path: String { url.path }
        var query: String? { url.query }
    }

    // 由 lock 保护；标 nonisolated(unsafe) 是为了将来切到 Swift 6 模式也能编译。
    private static let lock = NSLock()
    private nonisolated(unsafe) static var storedHandler: Handler?
    private nonisolated(unsafe) static var storedRequests: [RecordedRequest] = []

    static var handler: Handler? {
        get { lock.lock(); defer { lock.unlock() }; return storedHandler }
        set { lock.lock(); defer { lock.unlock() }; storedHandler = newValue }
    }

    static var requests: [RecordedRequest] {
        lock.lock(); defer { lock.unlock() }
        return storedRequests
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        storedHandler = nil
        storedRequests = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            url: request.url!,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.bodyBytes
        )
        Self.lock.lock()
        Self.storedRequests.append(recorded)
        let handler = Self.storedHandler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        do {
            let (status, body) = try handler(recorded)
            let response = HTTPURLResponse(
                url: recorded.url,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json; charset=utf-8"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLRequest {
    /// URLProtocol 里 httpBody 总是 nil，正文在 httpBodyStream 里。
    var bodyBytes: Data? {
        if let body = httpBody {
            return body
        }
        guard let stream = httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

func makeMockSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

func json(_ text: String) -> Data {
    Data(text.utf8)
}

/// 断言 async 表达式抛出指定的 ClipBridgeError。
func assertThrows<T>(
    _ expected: ClipBridgeError,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ expression: () async throws -> T
) async {
    do {
        _ = try await expression()
        XCTFail("expected \(expected) but nothing was thrown", file: file, line: line)
    } catch let error as ClipBridgeError {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("expected \(expected) but got \(error)", file: file, line: line)
    }
}
