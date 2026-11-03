import Foundation

/// 服务端 history.py 里的 ClipItem：{id, content, timestamp, source}。
public struct ClipItem: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        case pc
        case phone
    }

    public let id: String
    public let content: String
    /// 服务端给的是本地时区、精确到毫秒的 ISO 8601，例如 2026-11-01T21:51:00.123+08:00。
    public let timestamp: Date
    public let source: Source

    public init(id: String, content: String, timestamp: Date, source: Source) {
        self.id = id
        self.content = content
        self.timestamp = timestamp
        self.source = source
    }
}

/// `GET /clip/history` 的响应：{"items": [...]}，最新在前。
public struct HistoryResponse: Codable, Equatable, Sendable {
    public let items: [ClipItem]

    public init(items: [ClipItem]) {
        self.items = items
    }
}

/// 和服务端约定一致的 JSON 编解码器。
/// JSONDecoder 自带的 .iso8601 策略不认小数秒，所以日期用 ISO8601DateFormatter 手动解析。
public enum ClipBridgeJSON {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "不是 ISO 8601 时间：\(text)")
            }
            return date
        }
        return decoder
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(formatter(fractionalSeconds: true).string(from: date))
        }
        return encoder
    }

    /// 先按带小数秒解析，再退回不带小数秒；两种都接受时区偏移和 Z。
    public static func parseDate(_ text: String) -> Date? {
        formatter(fractionalSeconds: true).date(from: text) ?? formatter(fractionalSeconds: false).date(from: text)
    }

    private static func formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
