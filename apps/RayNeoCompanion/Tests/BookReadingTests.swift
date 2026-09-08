import XCTest
import ZIPFoundation
@testable import RayNeoCompanion

final class BookReadingTests: XCTestCase {
    func epub(extra: [(String, String)] = [], href: String = "a.xhtml", body: String = "<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>hidden</title><script>hidden</script></head><body><h1>第一章</h1><p>你好 👓</p><p>下一段</p></body></html>") throws -> Data {
        let archive = try Archive(accessMode: .create)
        let files = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>"),
            ("OPS/book.opf", "<package xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:title>测试书籍</dc:title></metadata><manifest><item id=\"b\" href=\"b.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"a\" href=\"\(href)\" media-type=\"application/xhtml+xml\"/></manifest><spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>"),
            ("OPS/a.xhtml", body),
            ("OPS/b.xhtml", "<html><body><h1>第二章</h1><p>结束</p></body></html>")
        ] + extra
        for (path, text) in files {
            let bytes = Data(text.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(bytes.count), compressionMethod: .deflate) { position, size in
                bytes.subdata(in: Int(position)..<(Int(position) + size))
            }
        }
        return try XCTUnwrap(archive.data)
    }
    func testEPUBUsesSpineAndExtractsPlainTextWithoutHead() throws {
        let book = try BookImporter.parse(epub(), extension: "epub", title: "fallback")
        XCTAssertEqual(book.title, "测试书籍")
        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "第一章")
        XCTAssertTrue(book.chapters[0].text.contains("你好 👓"))
        XCTAssertFalse(book.chapters[0].text.contains("hidden"))
        XCTAssertEqual(book.chapters[1].title, "第二章")
    }
    func testTXTEncodingAndLongUnicodeSegmentsPreserveText() throws {
        let text = String(repeating: "你好👨‍👩‍👧‍👦e\u{301}\n", count: 3_000)
        let book = try BookImporter.parse(Data(text.utf8), extension: "txt", title: "测试")
        XCTAssertGreaterThan(book.chapters.count, 1)
        XCTAssertEqual(book.chapters.map(\.text).joined(), text)
        let utf16 = try XCTUnwrap("中文\r\n下一行".data(using: .utf16))
        XCTAssertEqual(try BookImporter.parse(utf16, extension: "txt", title: "B").chapters.first?.text, "中文\n下一行")
    }
    func testRejectsDRMAndEscapingReferences() throws {
        XCTAssertThrowsError(try BookImporter.parse(epub(extra: [("META-INF/encryption.xml", "<encryption/>")]), extension: "epub", title: "A"))
        for href in ["../../outside.xhtml", "https://example.invalid/book", "/etc/passwd", "%2e%2e/%2e%2e/out.xhtml"] {
            XCTAssertThrowsError(try BookImporter.parse(epub(href: href), extension: "epub", title: "A"))
        }
        XCTAssertEqual(try BookImporter.resolved("../Text/a.xhtml", relativeTo: "OPS/Body"), "OPS/Text/a.xhtml")
    }
    func testDTDDoesNotExpandOrFetchButPlainDoctypeWorks() throws {
        let evil = "<!DOCTYPE html [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><html><body>&x;</body></html>"
        XCTAssertThrowsError(try BookImporter.parse(epub(body: evil), extension: "epub", title: "A"))
        let plain = "<!DOCTYPE html><html><body><p>安全&nbsp;文字</p></body></html>"
        XCTAssertTrue(try BookImporter.parse(epub(body: plain), extension: "epub", title: "A").chapters[0].text.contains("安全"))
    }
    func testRejectsEmptyUnsupportedAndHugeText() {
        XCTAssertThrowsError(try BookImporter.parse(Data(), extension: "txt", title: "A"))
        XCTAssertThrowsError(try BookImporter.parse(Data("abc".utf8), extension: "pdf", title: "A"))
        XCTAssertThrowsError(try BookImporter.parse(Data(repeating: 65, count: BookImporter.maximumTextBytes + 1), extension: "txt", title: "A"))
        XCTAssertThrowsError(try BookImporter.parse(Data([65, 0, 66]), extension: "txt", title: "A"))
    }
    func testCRCErrorIsNotAcceptedAsSuccessfulBook() throws {
        var bytes = try epub()
        // Corrupt a compressed payload rather than changing parser expectations.
        let central = try XCTUnwrap(bytes.range(of: Data([0x50, 0x4b, 0x01, 0x02])))
        bytes[central.lowerBound + 16] ^= 0xFF
        XCTAssertThrowsError(try BookImporter.parse(bytes, extension: "epub", title: "A"))
    }
    func testMotionIsUniformBoundedAndCannotJumpOnResume() {
        XCTAssertEqual(ReadingMotion.next(offset: 10, maximum: 100, speed: 20, elapsed: 0.05), 11)
        XCTAssertEqual(ReadingMotion.next(offset: 10, maximum: 100, speed: 20, elapsed: 15), 12)
        XCTAssertEqual(ReadingMotion.next(offset: 99, maximum: 100, speed: 80, elapsed: 0.1), 100)
        XCTAssertEqual(ReadingMotion.next(offset: .nan, maximum: 100, speed: 20, elapsed: 0.1), 0)
    }
    @MainActor func testImportPreservesSourceAndRestoresReadingPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("book.txt")
        let bytes = Data("测试书籍原文".utf8); try bytes.write(to: source)
        let library = BookLibrary(root: root.appendingPathComponent("library"))
        await library.importFile(source)
        XCTAssertNil(library.error)
        let book = try XCTUnwrap(library.books.first)
        await library.savePosition(id: book.id, chapter: 0, progress: 0.42, speed: 36)
        let restored = BookLibrary(root: root.appendingPathComponent("library")); await restored.load()
        XCTAssertEqual(restored.books.first?.progress, 0.42)
        XCTAssertEqual(restored.books.first?.speed, 36)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
    @MainActor func testSimulatorVoiceCannotPretendConnectedOrCallCloud() {
        let voice = CompanionVoiceRuntime()
        voice.prepare(); voice.discover(); voice.connect(); voice.start(cloud: true, continuous: true)
        XCTAssertFalse(voice.supportsDevice); XCTAssertFalse(voice.ready); XCTAssertFalse(voice.enabled)
        XCTAssertTrue(voice.transcript.isEmpty); XCTAssertTrue(voice.answer.isEmpty)
    }
}
