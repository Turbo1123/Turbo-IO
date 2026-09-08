import Foundation
import CoreFoundation
import ZIPFoundation
import Darwin

struct ReadingChapter: Codable, Identifiable, Equatable {
    var id: Int
    var title: String
    var text: String
}

struct ReadingBook: Codable, Identifiable, Equatable {
    var id = UUID()
    var title: String
    var chapters: [ReadingChapter]
    var importedAt = Date()
    var sourceExtension: String
    var chapter = 0
    var progress = 0.0
    var speed = 24.0 // phone points per second, NOT a glasses protocol value
}

enum BookImportError: LocalizedError {
    case unsupported, limit, invalid, encrypted, encoding, busy
    var errorDescription: String? {
        switch self {
        case .unsupported: return "目前支持 TXT 和无加密、可重排文字的 EPUB；不支持 PDF 或 DRM 电子书。"
        case .limit: return "书籍超过安全限额：源文件 20 MiB、正文 8 MiB、最多 2,000 个阅读分段。"
        case .invalid: return "文件结构、校验或章节引用异常，未导入。原文件保持不变。"
        case .encrypted: return "此 EPUB 含加密声明，暂不导入；不会尝试解除 DRM。"
        case .encoding: return "无法识别文字编码，请另存为 UTF-8 TXT 后导入。"
        case .busy: return "已有书籍正在导入，请稍候。"
        }
    }
}

enum BookImporter {
    static let maximumBytes = 20 * 1_024 * 1_024
    static let maximumTextBytes = 8 * 1_024 * 1_024

    // Coordinated read, bounded actual bytes; no archive paths are written to disk.
    static func read(_ source: URL) throws -> ReadingBook {
        guard source.isFileURL else { throw BookImportError.unsupported }
        let ext = source.pathExtension.lowercased()
        guard ["epub", "txt"].contains(ext) else { throw BookImportError.unsupported }
        var result: Result<ReadingBook, Error>?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            result = Result {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw BookImportError.invalid }
                guard let size = values.fileSize, size > 0, size <= maximumBytes else { throw BookImportError.limit }
                let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                guard fd >= 0 else { throw BookImportError.invalid }
                let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                defer { try? handle.close() }
                var before = stat()
                guard fstat(fd, &before) == 0, before.st_mode & S_IFMT == S_IFREG, before.st_size == size else { throw BookImportError.invalid }
                var bytes = Data()
                while let block = try handle.read(upToCount: 65_536), !block.isEmpty {
                    try Task.checkCancellation()
                    guard bytes.count + block.count <= maximumBytes else { throw BookImportError.limit }
                    bytes.append(block)
                }
                guard bytes.count == size else { throw BookImportError.invalid }
                var after = stat()
                guard fstat(fd, &after) == 0, before.st_size == after.st_size,
                      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw BookImportError.invalid }
                return try parse(bytes, extension: ext, title: source.deletingPathExtension().lastPathComponent)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw BookImportError.invalid }
        return try result.get()
    }

    static func parse(_ data: Data, extension ext: String, title: String) throws -> ReadingBook {
        guard !data.isEmpty, data.count <= maximumBytes else { throw BookImportError.limit }
        if ext == "txt" {
            guard data.count <= maximumTextBytes else { throw BookImportError.limit }
            let text: String?
            if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
                text = String(data: data, encoding: .utf16)
            } else if let utf8 = String(data: data, encoding: .utf8) { text = utf8 }
            else {
                let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
                text = String(data: data, encoding: String.Encoding(rawValue: gb))
            }
            guard let text, !text.contains("\0") else { throw BookImportError.encoding }
            let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "").replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            guard clean.utf8.count <= maximumTextBytes else { throw BookImportError.limit }
            guard !clean.unicodeScalars.contains(where: { $0.value < 32 && $0.value != 9 && $0.value != 10 }) else { throw BookImportError.encoding }
            guard !clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BookImportError.invalid }
            return ReadingBook(title: String(title.prefix(200)), chapters: try segments([(title, clean)]), sourceExtension: ext)
        }
        guard ext == "epub" else { throw BookImportError.unsupported }
        let archive = try Archive(data: data, accessMode: .read)
        var paths = Set<String>(), count = 0
        var expanded: UInt64 = 0
        for entry in archive {
            count += 1; expanded += entry.uncompressedSize
            guard count <= 5_000, expanded <= 128 * 1_024 * 1_024 else { throw BookImportError.limit }
            guard entry.type != .symlink, paths.insert(entry.path).inserted else { throw BookImportError.invalid }
        }
        guard archive["META-INF/encryption.xml"] == nil else { throw BookImportError.encrypted }
        func extract(_ path: String, limit: Int) throws -> Data {
            guard let entry = archive[path], entry.type == .file, entry.uncompressedSize <= UInt64(limit) else { throw BookImportError.invalid }
            var bytes = Data()
            let crc = try archive.extract(entry, bufferSize: 65_536) { chunk in
                try Task.checkCancellation()
                guard bytes.count + chunk.count <= limit else { throw BookImportError.limit }
                bytes.append(chunk)
            }
            guard crc == entry.checksum else { throw BookImportError.invalid }
            return bytes
        }
        guard String(data: try extract("mimetype", limit: 128), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" else { throw BookImportError.invalid }
        let container = try BookXML.parse(extract("META-INF/container.xml", limit: 262_144))
        guard let root = container.rootfile else { throw BookImportError.invalid }
        let opfPath = try resolved(root, relativeTo: "")
        let package = try BookXML.parse(extract(opfPath, limit: 1_048_576))
        guard !package.fixedLayout else { throw BookImportError.unsupported }
        let base = (opfPath as NSString).deletingLastPathComponent
        var parts: [(String, String)] = [], total = 0
        guard !package.spine.isEmpty, package.spine.count <= 1_000 else { throw BookImportError.invalid }
        for id in package.spine {
            try Task.checkCancellation()
            guard let item = package.manifest[id], ["application/xhtml+xml", "text/html"].contains(item.media) else { throw BookImportError.unsupported }
            let path = try resolved(item.href, relativeTo: base)
            let raw = try extract(path, limit: 2 * 1_024 * 1_024)
            total += raw.count
            guard total <= maximumTextBytes else { throw BookImportError.limit }
            let page = try BookXML.parse(raw)
            let text = page.body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { parts.append((page.heading.isEmpty ? "章节 \(parts.count + 1)" : page.heading, text)) }
        }
        guard !parts.isEmpty else { throw BookImportError.unsupported }
        return ReadingBook(title: String((package.title.isEmpty ? title : package.title).prefix(200)), chapters: try segments(parts), sourceExtension: ext)
    }

    static func resolved(_ href: String, relativeTo base: String) throws -> String {
        guard let decoded = href.removingPercentEncoding, !decoded.isEmpty,
              !decoded.hasPrefix("/"), !decoded.contains(":"), !decoded.contains("\\"), !decoded.contains("\0"),
              !decoded.contains("?"), !decoded.contains("#") else { throw BookImportError.invalid }
        var stack = base.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { guard !stack.isEmpty else { throw BookImportError.invalid }; stack.removeLast() }
            else { stack.append(String(part)) }
        }
        guard !stack.isEmpty else { throw BookImportError.invalid }
        return stack.joined(separator: "/")
    }

    static func segments(_ parts: [(String, String)]) throws -> [ReadingChapter] {
        var result: [ReadingChapter] = []
        for (title, text) in parts {
            let chunks = LocalPrompterPager.pages(text, charactersPerPage: 12_000)
            for (index, chunk) in chunks.enumerated() {
                guard result.count < 2_000 else { throw BookImportError.limit }
                result.append(ReadingChapter(id: result.count, title: String(title.prefix(120)) + (chunks.count > 1 ? " · \(index + 1)" : ""), text: chunk))
            }
        }
        return result
    }
}

// Strict XHTML text subset. No web view, JavaScript, CSS, external entities or network.
private final class BookXML: NSObject, XMLParserDelegate {
    var rootfile: String?
    var manifest: [String: (href: String, media: String)] = [:]
    var spine: [String] = []
    var title = "", body = "", heading = ""
    var fixedLayout = false
    private var stack: [String] = []
    private var ignored = 0
    private var fixedMeta = false
    static func parse(_ bytes: Data) throws -> BookXML {
        // DTD and ENTITY are unsupported, including internal expansion attacks.
        // Decode for declaration scanning so UTF-16 cannot bypass the check.
        var scan = String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .utf16) ?? ""
        guard !scan.isEmpty, !scan.uppercased().contains("<!ENTITY") else { throw BookImportError.invalid }
        // Strip only simple HTML doctype declarations without internal subsets.
        // Never load a DTD or run arbitrary HTML through a browser.
        scan = scan.replacingOccurrences(of: "<!DOCTYPE\\s+html(?:\\s+(?:PUBLIC|SYSTEM)\\s+[^<>\\[\\]]*)?\\s*>", with: "", options: [.regularExpression, .caseInsensitive])
        guard !scan.uppercased().contains("<!DOCTYPE") else { throw BookImportError.invalid }
        scan = scan.replacingOccurrences(of: "<\\?xml[^?]*\\?>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: "&#160;")
        let delegate = BookXML(), parser = XMLParser(data: Data(scan.utf8))
        parser.shouldProcessNamespaces = true; parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse() else { throw BookImportError.invalid }
        return delegate
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.lowercased(); stack.append(name)
        if stack.count > 128 { parser.abortParsing(); return }
        if ["script", "style", "head", "svg"].contains(name) { ignored += 1 }
        if name == "rootfile", rootfile == nil { rootfile = attributes["full-path"] }
        if name == "item", let id = attributes["id"], let href = attributes["href"], let media = attributes["media-type"] {
            if manifest[id] != nil { parser.abortParsing(); return }
            manifest[id] = (href, media)
        }
        if name == "itemref", attributes["linear"] != "no", let id = attributes["idref"] { spine.append(id) }
        if name == "meta", attributes["property"] == "rendition:layout" { fixedMeta = true }
        if ignored == 0, stack.contains("body"), ["p", "div", "br", "h1", "h2", "li"].contains(name) { body += "\n" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if stack.last == "title", !stack.contains("head") { title += string }
        if fixedMeta, string.contains("pre-paginated") { fixedLayout = true }
        guard ignored == 0, stack.contains("body") else { return }
        body += string
        if stack.contains("h1") || stack.contains("h2"), heading.count < 120 { heading += String(string.prefix(120 - heading.count)) }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.lowercased()
        if ignored == 0, stack.contains("body"), ["p", "div", "h1", "h2", "li"].contains(name) { body += "\n" }
        if ["script", "style", "head", "svg"].contains(name) { ignored = max(0, ignored - 1) }
        if name == "meta" { fixedMeta = false }
        if !stack.isEmpty { stack.removeLast() }
    }
}
