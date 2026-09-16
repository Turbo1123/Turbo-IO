import Foundation
import CryptoKit
import Darwin

/// App-owned, endpoint-scoped metadata only. Save returns after file AND rename
/// directory are synchronized, before any request or approval can be sent.
public struct HermesTaskReferenceStore {
    private let directory: URL
    public init(directory: URL) throws {
        guard directory.isFileURL else { throw HermesTaskError.storage }
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attrs[.type] as? FileAttributeType == .typeDirectory,
              let permissions = attrs[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0 else { throw HermesTaskError.storage }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: directory.path)
        #endif
        var target = directory, values = URLResourceValues(); values.isExcludedFromBackup = true
        try target.setResourceValues(values)
    }
    private func file(_ endpoint: String) throws -> URL {
        let normalized = try HermesBridgeConfiguration.normalize(endpoint)
        let hash = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
    public func load(endpoint: String) throws -> Data? {
        let target = try file(endpoint)
        let fd = Darwin.open(target.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0 { if errno == ENOENT { return nil }; throw HermesTaskError.storage }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_mode & 0o077 == 0, info.st_size >= 0, info.st_size <= 4096 else { throw HermesTaskError.storage }
        return try handle.readToEnd() ?? Data()
    }
    public func save(_ data: Data, endpoint: String) throws {
        guard data.count <= 4096 else { throw HermesTaskError.storage }
        let target = try file(endpoint), temporary = directory.appendingPathComponent(UUID().uuidString + ".new")
        let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw HermesTaskError.storage }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close(); try? FileManager.default.removeItem(at: temporary) }
        try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        guard Darwin.rename(temporary.path, target.path) == 0 else { throw HermesTaskError.storage }
        let directoryFD = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard directoryFD >= 0 else { throw HermesTaskError.storage }
        defer { Darwin.close(directoryFD) }
        guard fsync(directoryFD) == 0 else { throw HermesTaskError.storage }
    }
}

public enum HermesTaskPresentation {
    public static func glassesText(_ text: String) -> String {
        let prefix = TextBounds.boundedPrefix(text, maximumCharacters: 1200, maximumUTF8Bytes: 6000)
        return prefix == text ? text : prefix + "\n完整结果见手机任务卡。"
    }
}
