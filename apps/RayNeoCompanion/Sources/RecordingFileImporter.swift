import Foundation

enum RecordingImportError: LocalizedError {
    case alreadyImporting, notRegularFile, emptyFile, tooLarge, sourceChanged
    var errorDescription: String? {
        switch self {
        case .alreadyImporting: return "已有一个音频正在导入，请稍候。"
        case .notRegularFile: return "只能导入普通音频文件，不支持目录或符号链接。"
        case .emptyFile: return "所选文件为空。"
        case .tooLarge: return "单个文件最多支持 512 MB，请先拆分较大的录音。"
        case .sourceChanged: return "导入期间来源文件发生变化，已取消本次导入。"
        }
    }
}

enum RecordingFileImporter {
    static let maximumBytes = 512 * 1024 * 1024

    /// Called off the main actor while the caller keeps security-scoped access alive.
    /// Only this invocation's UUID paths may be removed on failure; the source is never altered.
    static func copy(source: URL, to directory: URL, maximumBytes: Int = maximumBytes) throws -> LocalRecording {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let before = try source.resourceValues(forKeys: keys)
        guard before.isRegularFile == true, before.isSymbolicLink != true else { throw RecordingImportError.notRegularFile }
        let count = before.fileSize ?? 0
        guard count > 0 else { throw RecordingImportError.emptyFile }
        guard count <= maximumBytes else { throw RecordingImportError.tooLarge }
        let ext = source.pathExtension.lowercased()
        let filename = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        let staging = directory.appendingPathComponent(filename + ".partial")
        let target = directory.appendingPathComponent(filename)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var ownsStaging = false
        do {
            // UUID paths are checked before copying, never used to overwrite an existing file.
            guard !manager.fileExists(atPath: staging.path), !manager.fileExists(atPath: target.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try Data().write(to: staging, options: .withoutOverwriting)
            ownsStaging = true
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            let output = try FileHandle(forWritingTo: staging)
            defer { try? output.close() }
            var total = 0
            while let chunk = try input.read(upToCount: 65_536), !chunk.isEmpty {
                try Task.checkCancellation()
                guard total <= maximumBytes - chunk.count else { throw RecordingImportError.tooLarge }
                total += chunk.count
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
            var refreshedSource = source
            refreshedSource.removeAllCachedResourceValues()
            let after = try refreshedSource.resourceValues(forKeys: keys)
            let copied = try staging.resourceValues(forKeys: [.fileSizeKey])
            guard after.fileSize == before.fileSize, after.contentModificationDate == before.contentModificationDate,
                  copied.fileSize == before.fileSize, total == count else { throw RecordingImportError.sourceChanged }
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: staging.path)
            try manager.moveItem(at: staging, to: target)
            ownsStaging = false
            let recording = LocalRecording(name: source.deletingPathExtension().lastPathComponent, storedFilename: filename, byteCount: Int64(count))
            return recording
        } catch {
            if ownsStaging { try? manager.removeItem(at: staging) }
            throw error
        }
    }
}
