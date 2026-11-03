import XCTest
@testable import ClipBridgeKit

final class ClipItemDecodingTests: XCTestCase {
    private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int, millis: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second, nanosecond: millis * 1_000_000)
        return calendar.date(from: components)!
    }

    func testDecodesServerTimestampWithMillisecondsAndOffset() throws {
        let item = try ClipBridgeJSON.makeDecoder().decode(ClipItem.self, from: json(
            #"{"id":"3f2a","content":"hello","timestamp":"2026-11-01T21:51:00.123+08:00","source":"pc"}"#
        ))
        XCTAssertEqual(item.id, "3f2a")
        XCTAssertEqual(item.content, "hello")
        XCTAssertEqual(item.source, .pc)
        XCTAssertEqual(item.timestamp.timeIntervalSince1970, utcDate(2026, 11, 1, 13, 51, 0, millis: 123).timeIntervalSince1970, accuracy: 0.001)
    }

    func testDecodesTimestampWithoutFractionalSeconds() throws {
        let item = try ClipBridgeJSON.makeDecoder().decode(ClipItem.self, from: json(
            #"{"id":"1","content":"x","timestamp":"2026-11-01T13:51:00Z","source":"phone"}"#
        ))
        XCTAssertEqual(item.source, .phone)
        XCTAssertEqual(item.timestamp, utcDate(2026, 11, 1, 13, 51, 0))
    }

    func testRejectsUnparseableTimestampAndUnknownSource() {
        XCTAssertThrowsError(try ClipBridgeJSON.makeDecoder().decode(ClipItem.self, from: json(
            #"{"id":"1","content":"x","timestamp":"yesterday","source":"pc"}"#
        )))
        XCTAssertThrowsError(try ClipBridgeJSON.makeDecoder().decode(ClipItem.self, from: json(
            #"{"id":"1","content":"x","timestamp":"2026-11-01T13:51:00Z","source":"watch"}"#
        )))
    }

    func testHistoryResponseKeepsServerOrder() throws {
        let response = try ClipBridgeJSON.makeDecoder().decode(HistoryResponse.self, from: json(#"""
        {"items":[
          {"id":"new","content":"新的","timestamp":"2026-11-01T21:51:00.123+08:00","source":"pc"},
          {"id":"old","content":"old","timestamp":"2026-11-01T21:50:59.000+08:00","source":"phone"}
        ]}
        """#))
        XCTAssertEqual(response.items.map(\.id), ["new", "old"])
        XCTAssertEqual(response.items[0].content, "新的")
    }

    func testEncoderRoundTripsWithMilliseconds() throws {
        let original = ClipItem(id: "a", content: "b", timestamp: utcDate(2026, 1, 2, 3, 4, 5, millis: 678), source: .pc)
        let data = try ClipBridgeJSON.makeEncoder().encode(original)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("2026-01-02T03:04:05.678Z"))
        let decoded = try ClipBridgeJSON.makeDecoder().decode(ClipItem.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, original.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }
}
