import Foundation

/// 把分享面板 / NSItemProvider 交过来的东西安全地变成纯文字。
///
/// 教训（2026-11-04 真机）：Safari 分享选中文字时，`loadDataRepresentation(for: .plainText)` 给的是
/// NSKeyedArchiver 归档的二进制 plist；用 `String(data:encoding:.utf16)` 硬解会得到一串汉字乱码并原样发到电脑。
/// 规则：解不开的二进制一律不当文本，宁可报错。
public enum SharedTextDecoder {
    private static let binaryPlistMagic = Array("bplist".utf8)
    private static let utf16LittleEndianBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BigEndianBOM: [UInt8] = [0xFE, 0xFF]

    public static func isBinaryPlist(_ data: Data) -> Bool {
        data.starts(with: binaryPlistMagic)
    }

    /// 纯文本 Data：只接受合法 UTF-8，或带 BOM 的 UTF-16；bplist、含 NUL、纯空白都返回 nil。
    /// 不带 BOM 的 UTF-16 也拒绝——ASCII 的 UTF-16 恰好是「字符 + NUL」，能通过 UTF-8 校验，所以靠 NUL 拦。
    public static func plainText(from data: Data) -> String? {
        guard !data.isEmpty, !isBinaryPlist(data) else {
            return nil
        }
        let decoded: String?
        if data.starts(with: utf16LittleEndianBOM) || data.starts(with: utf16BigEndianBOM) {
            decoded = String(data: data, encoding: .utf16)
        } else {
            decoded = String(data: data, encoding: .utf8)
        }
        guard let decoded, !decoded.contains("\0") else {
            return nil
        }
        return nonEmpty(decoded)
    }

    /// NSKeyedArchiver 归档（bplist 开头）的 NSAttributedString / NSString。
    public static func archivedText(from data: Data) -> String? {
        guard isBinaryPlist(data) else {
            return nil
        }
        if let attributed = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSAttributedString.self, from: data) {
            return nonEmpty(attributed.string)
        }
        if let string = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: data) {
            return nonEmpty(string as String)
        }
        return nil
    }

    /// 先按归档解，再按纯文本解；两条都走不通就是 nil，调用方必须报错而不是发送。
    public static func text(from data: Data) -> String? {
        archivedText(from: data) ?? plainText(from: data)
    }

    /// `loadItem(forTypeIdentifier:)` 回来的对象可能是 String / NSAttributedString / Data / NSURL。
    public static func text(fromLoadedItem item: Any?) -> String? {
        switch item {
        case let string as String:
            return nonEmpty(string)
        case let attributed as NSAttributedString:
            return nonEmpty(attributed.string)
        case let data as Data:
            return text(from: data)
        default:
            return nil
        }
    }

    /// 能当正文用的字符串：非空白、不含 NUL、也不是被当成文本解出来的归档字节
    /// （NSAttributedString 的纯文本读取器会把 bplist 归档解成以 "bplist00" 开头的"字符串"）。
    public static func nonEmpty(_ text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !text.contains("\0"),
              !text.hasPrefix("bplist0") else {
            return nil
        }
        return text
    }

    /// 日志用：前几个字节的十六进制。
    public static func hexPrefix(of data: Data, count: Int = 16) -> String {
        data.prefix(count).map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
