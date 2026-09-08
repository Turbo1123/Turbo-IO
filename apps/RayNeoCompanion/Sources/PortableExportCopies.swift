import Foundation

struct PortableExportCopy: Identifiable, Sendable {
    let id: UUID
    let inTrash: Bool
    let bytes: Int64
    let modifiedAt: Date
}

struct PortableExportCatalog: Sendable {
    var copies: [PortableExportCopy] = []
    var unrecognized = 0
}

enum PortableCopyError: LocalizedError {
    case unsafe, capacity, changed
    var errorDescription: String? {
        switch self {
        case .unsafe: return "导出副本目录结构异常，未移动任何文件。"
        case .capacity: return "目标目录已达到 20 份限制；未覆盖或删除现有副本。"
        case .changed: return "副本已变化或目标已存在，请刷新后重试。"
        }
    }
}

/// Only derived ZIP export directories. Never accepts an arbitrary source path or deletes contents.
struct PortableExportCopies {
    let parent: URL
    private var base: URL { parent.standardizedFileURL.resolvingSymlinksInPath() }
    private func root(trash: Bool) -> URL {
        base.appendingPathComponent(trash ? "PortableArchiveTrashV1" : "PortableArchiveExportsV1", isDirectory: true)
    }
    private func directory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true,
              url.standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else { throw PortableCopyError.unsafe }
    }
    private func children(_ url: URL) throws -> [URL] {
        if !FileManager.default.fileExists(atPath: url.path) {
            // Dangling symlinks are not an absent directory.
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw PortableCopyError.unsafe }
            return []
        }
        try directory(url)
        let rows = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        guard rows.count <= 500 else { throw PortableCopyError.unsafe }
        return rows
    }
    private func inspect(_ url: URL, id: UUID, trash: Bool) throws -> PortableExportCopy {
        try directory(url)
        var todo = [url], count = 0, bytes: Int64 = 0
        while let next = todo.popLast() {
            for child in try children(next) {
                count += 1
                guard count <= 500 else { throw PortableCopyError.unsafe }
                let value = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                guard value.isSymbolicLink != true else { throw PortableCopyError.unsafe }
                if value.isDirectory == true { todo.append(child) }
                else {
                    guard value.isRegularFile == true, let size = value.fileSize, size >= 0,
                          bytes <= Int64.max - Int64(size) else { throw PortableCopyError.unsafe }
                    bytes += Int64(size)
                }
            }
        }
        let date = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        return PortableExportCopy(id: id, inTrash: trash, bytes: bytes, modifiedAt: date)
    }
    func catalog() throws -> PortableExportCatalog {
        var catalog = PortableExportCatalog()
        for trash in [false, true] {
            for child in try children(root(trash: trash)) {
                guard let id = UUID(uuidString: child.lastPathComponent), child.lastPathComponent == id.uuidString,
                      let copy = try? inspect(child, id: id, trash: trash) else { catalog.unrecognized += 1; continue }
                catalog.copies.append(copy)
            }
        }
        catalog.copies.sort { $0.modifiedAt > $1.modifiedAt }
        return catalog
    }
    func move(_ id: UUID, toTrash: Bool) throws {
        let sourceRoot = root(trash: !toTrash), targetRoot = root(trash: toTrash)
        try directory(sourceRoot)
        let source = sourceRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        _ = try inspect(source, id: id, trash: !toTrash)
        guard try children(targetRoot).count < 20 else { throw PortableCopyError.capacity }
        if !FileManager.default.fileExists(atPath: targetRoot.path) {
            try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        try directory(targetRoot)
        let target = targetRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: target.path),
              (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw PortableCopyError.changed }
        try FileManager.default.moveItem(at: source, to: target)
    }
}
