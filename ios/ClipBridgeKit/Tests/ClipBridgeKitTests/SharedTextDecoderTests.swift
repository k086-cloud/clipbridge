import XCTest
@testable import ClipBridgeKit

final class SharedTextDecoderTests: XCTestCase {
    private func archived(_ object: NSObject & NSSecureCoding) throws -> Data {
        try NSKeyedArchiver.archivedData(withRootObject: object, requiringSecureCoding: true)
    }

    func testPlainUTF8IsAccepted() {
        XCTAssertEqual(SharedTextDecoder.plainText(from: Data("confusing piece".utf8)), "confusing piece")
        XCTAssertEqual(SharedTextDecoder.plainText(from: Data("中文 and ümlauts\n第二行".utf8)), "中文 and ümlauts\n第二行")
        XCTAssertEqual(SharedTextDecoder.text(from: Data("x".utf8)), "x")
    }

    func testBinaryPlistIsNeverTreatedAsText() throws {
        // Safari 分享选中文字时给的就是这种东西；之前被 .utf16 硬解成「扰汩猿〜吾」发了出去
        let plist = try PropertyListSerialization.data(fromPropertyList: ["confusing": "piece"], format: .binary, options: 0)
        XCTAssertTrue(SharedTextDecoder.isBinaryPlist(plist))
        XCTAssertNil(SharedTextDecoder.plainText(from: plist))
        XCTAssertNil(SharedTextDecoder.archivedText(from: plist))
        XCTAssertNil(SharedTextDecoder.text(from: plist))
        XCTAssertNil(SharedTextDecoder.text(fromLoadedItem: plist))
    }

    func testArchivedAttributedStringDecodesToItsText() throws {
        let data = try archived(NSAttributedString(string: "a confusing piece"))
        XCTAssertTrue(SharedTextDecoder.isBinaryPlist(data))
        XCTAssertNil(SharedTextDecoder.plainText(from: data), "归档数据不能当纯文本")
        XCTAssertEqual(SharedTextDecoder.archivedText(from: data), "a confusing piece")
        XCTAssertEqual(SharedTextDecoder.text(from: data), "a confusing piece")
        XCTAssertEqual(SharedTextDecoder.text(fromLoadedItem: data), "a confusing piece")
    }

    func testArchivedStringDecodesToItsText() throws {
        let data = try archived("hello" as NSString)
        XCTAssertEqual(SharedTextDecoder.archivedText(from: data), "hello")
        XCTAssertEqual(SharedTextDecoder.text(from: data), "hello")
    }

    func testArchivedEmptyTextIsNil() throws {
        XCTAssertNil(SharedTextDecoder.text(from: try archived(NSAttributedString(string: "  \n"))))
    }

    func testInvalidUTF8AndNULAreRejected() {
        XCTAssertNil(SharedTextDecoder.plainText(from: Data([0xC3, 0x28])))
        XCTAssertNil(SharedTextDecoder.plainText(from: Data([0xFF, 0x00, 0x12, 0x34])))
        XCTAssertNil(SharedTextDecoder.plainText(from: Data("h\0i".utf8)))
        // 不带 BOM 的 UTF-16LE："hi" = 68 00 69 00，恰好是合法 UTF-8，靠 NUL 拦住
        XCTAssertNil(SharedTextDecoder.plainText(from: Data([0x68, 0x00, 0x69, 0x00])))
        XCTAssertNil(SharedTextDecoder.text(from: Data([0x68, 0x00, 0x69, 0x00])))
    }

    func testUTF16WithBOMIsAccepted() throws {
        var little = Data([0xFF, 0xFE])
        little.append(try XCTUnwrap("hi 中".data(using: .utf16LittleEndian)))
        XCTAssertEqual(SharedTextDecoder.plainText(from: little), "hi 中")

        var big = Data([0xFE, 0xFF])
        big.append(try XCTUnwrap("hi 中".data(using: .utf16BigEndian)))
        XCTAssertEqual(SharedTextDecoder.plainText(from: big), "hi 中")
    }

    func testWhitespaceOnlyAndEmptyAreNil() {
        XCTAssertNil(SharedTextDecoder.plainText(from: Data()))
        XCTAssertNil(SharedTextDecoder.plainText(from: Data("   \n\t".utf8)))
        XCTAssertNil(SharedTextDecoder.nonEmpty(" "))
        XCTAssertEqual(SharedTextDecoder.nonEmpty(" a "), " a ")
    }

    func testLoadedItemVariants() throws {
        XCTAssertEqual(SharedTextDecoder.text(fromLoadedItem: "plain"), "plain")
        XCTAssertEqual(SharedTextDecoder.text(fromLoadedItem: "bridged" as NSString), "bridged")
        XCTAssertEqual(SharedTextDecoder.text(fromLoadedItem: NSAttributedString(string: "rich")), "rich")
        XCTAssertEqual(SharedTextDecoder.text(fromLoadedItem: Data("data".utf8)), "data")
        XCTAssertEqual(SharedTextDecoder.text(fromLoadedItem: try archived(NSAttributedString(string: "archived"))), "archived")
        XCTAssertNil(SharedTextDecoder.text(fromLoadedItem: URL(string: "https://example.com")!))
        XCTAssertNil(SharedTextDecoder.text(fromLoadedItem: NSURL(string: "https://example.com")!))
        XCTAssertNil(SharedTextDecoder.text(fromLoadedItem: nil))
        XCTAssertNil(SharedTextDecoder.text(fromLoadedItem: 42))
    }

    func testHexPrefix() {
        XCTAssertEqual(SharedTextDecoder.hexPrefix(of: Data("bplist00".utf8), count: 4), "62 70 6c 69")
        XCTAssertEqual(SharedTextDecoder.hexPrefix(of: Data()), "")
    }
}
