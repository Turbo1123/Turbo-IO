import Foundation
import CryptoKit
import Darwin

final class Descriptor {
    let value: Int32
    init(_ value: Int32) { self.value = value }
    deinit { Darwin.close(value) }
}

/// Relative operations use pinned directory descriptors. No caller-supplied relative path is accepted.
final class ArchiveFileSystem {
    let rootURL: URL
    let root: Descriptor
    let audio: Descriptor
    let notes: Descriptor
    let staging: Descriptor
    let lockFile: Descriptor
    static let chunkSize = 4 * 1_024

    init(rootDirectory: URL) throws {
        guard rootDirectory.isFileURL, rootDirectory.host == nil || rootDirectory.host == "",
              rootDirectory.query == nil, rootDirectory.fragment == nil else { throw ArchiveError.invalidFileURL }
        rootURL = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let rootFD = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw ArchiveError.targetDirectoryRequired }
        root = Descriptor(rootFD)
        audio = try Self.directory(parent: rootFD, name: "audio")
        notes = try Self.directory(parent: rootFD, name: "notes")
        staging = try Self.directory(parent: rootFD, name: ".staging")
        lockFile = try Self.openFile(in: rootFD, name: ".archive.lock", flags: O_RDWR | O_CREAT)
        try Self.requireRegular(lockFile.value)
        try Self.synchronize(rootFD)
    }

    private static func directory(parent: Int32, name: String) throws -> Descriptor {
        if mkdirat(parent, name, mode_t(0o700)) != 0 && errno != EEXIST { throw failure("create directory") }
        let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw failure("open archive directory") }
        return Descriptor(fd)
    }

    static func failure(_ operation: String) -> ArchiveError { .io(operation: operation, code: errno) }

    static func openFile(in directory: Int32, name: String, flags: Int32) throws -> Descriptor {
        let fd = openat(directory, name, flags | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { throw failure("open archive file") }
        return Descriptor(fd)
    }

    static func requireRegular(_ fd: Int32) throws {
        let info = try statFile(fd)
        guard info.st_mode & S_IFMT == S_IFREG else { throw ArchiveError.unsupportedFileType }
    }

    static func statFile(_ fd: Int32) throws -> stat {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw failure("inspect file") }
        return info
    }

    static func unchanged(_ first: stat, _ last: stat) -> Bool {
        first.st_dev == last.st_dev && first.st_ino == last.st_ino && first.st_size == last.st_size &&
        first.st_mtimespec.tv_sec == last.st_mtimespec.tv_sec && first.st_mtimespec.tv_nsec == last.st_mtimespec.tv_nsec &&
        first.st_ctimespec.tv_sec == last.st_ctimespec.tv_sec && first.st_ctimespec.tv_nsec == last.st_ctimespec.tv_nsec
    }

    func locked<T>(_ operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        try verifyLocation()
        guard flock(lockFile.value, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK { throw ArchiveError.archiveBusy }
            throw Self.failure("lock archive")
        }
        defer { flock(lockFile.value, LOCK_UN) }
        return try operation()
    }

    /// Pinned descriptors remain safe after renames, but a shareable URL must still identify those descriptors.
    func verifyLocation() throws {
        let rootFD = Darwin.open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw ArchiveError.archiveLocationChanged }
        let currentRoot = Descriptor(rootFD)
        func sameObject(_ left: Int32, _ right: Int32) throws -> Bool {
            let a = try Self.statFile(left), b = try Self.statFile(right)
            return a.st_dev == b.st_dev && a.st_ino == b.st_ino
        }
        guard try sameObject(currentRoot.value, root.value) else { throw ArchiveError.archiveLocationChanged }
        for (name, pinned, directory) in [("audio", audio, true), ("notes", notes, true), (".staging", staging, true), (".archive.lock", lockFile, false)] {
            let fd = openat(root.value, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK | (directory ? O_DIRECTORY : 0))
            guard fd >= 0 else { throw ArchiveError.archiveLocationChanged }
            let current = Descriptor(fd)
            guard try sameObject(current.value, pinned.value) else { throw ArchiveError.archiveLocationChanged }
        }
    }

    static func synchronize(_ fd: Int32) throws {
        guard fsync(fd) == 0 else { throw failure("synchronize archive") }
    }

    static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var position = 0
            while position < raw.count {
                let count = Darwin.write(fd, base.advanced(by: position), raw.count - position)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw failure("write archive file") }
                position += count
            }
        }
    }

    static func chunk(from fd: Int32) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { throw failure("read file") }
            return Data(buffer.prefix(count))
        }
    }

    func writeExclusive(_ data: Data, name: String) throws {
        let fd = try Self.openFile(in: staging.value, name: name, flags: O_WRONLY | O_CREAT | O_EXCL)
        try Self.write(data, to: fd.value)
        try Self.synchronize(fd.value)
    }

    func readSmall(in directory: Int32, name: String, limit: Int) throws -> Data? {
        let rawFD = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if rawFD < 0 && errno == ENOENT { return nil }
        guard rawFD >= 0 else { throw Self.failure("read archive metadata") }
        let fd = Descriptor(rawFD)
        try Self.requireRegular(fd.value)
        let initial = try Self.statFile(fd.value)
        guard initial.st_size <= limit else { throw ArchiveError.manifestSizeLimitExceeded }
        var result = Data()
        while true {
            let bytes = try Self.chunk(from: fd.value)
            if bytes.isEmpty { break }
            guard result.count <= limit - bytes.count else { throw ArchiveError.manifestSizeLimitExceeded }
            result.append(bytes)
        }
        guard Self.unchanged(initial, try Self.statFile(fd.value)) else { throw ArchiveError.invalidManifest }
        return result
    }

    func copySource(_ source: URL, stageName: String, limit: Int64, copiedChunk: (() throws -> Void)? = nil) throws -> (sha256: String, byteCount: Int64) {
        try Task.checkCancellation()
        guard source.isFileURL, source.host == nil || source.host == "",
              source.query == nil, source.fragment == nil else { throw ArchiveError.invalidFileURL }
        let rawFD = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard rawFD >= 0 else { throw Self.failure("open selected source") }
        let input = Descriptor(rawFD)
        try Self.requireRegular(input.value)
        let initial = try Self.statFile(input.value)
        guard initial.st_size > 0 else { throw ArchiveError.emptySource }
        guard initial.st_size <= limit else { throw ArchiveError.fileSizeLimitExceeded }
        let output = try Self.openFile(in: staging.value, name: stageName, flags: O_WRONLY | O_CREAT | O_EXCL)
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let bytes = try Self.chunk(from: input.value)
            if bytes.isEmpty { break }
            guard total <= limit - Int64(bytes.count) else { throw ArchiveError.fileSizeLimitExceeded }
            try Self.write(bytes, to: output.value)
            hasher.update(data: bytes)
            total += Int64(bytes.count)
            try copiedChunk?()
            try Task.checkCancellation()
        }
        guard total == initial.st_size, Self.unchanged(initial, try Self.statFile(input.value)) else {
            throw ArchiveError.sourceChangedDuringCopy
        }
        try Self.synchronize(output.value)
        return (hasher.finalize().map { String(format: "%02x", $0) }.joined(), total)
    }

    func verify(in directory: Int32, name: String, sha256: String, size: Int64, limit: Int64) throws -> Bool {
        try Task.checkCancellation()
        let rawFD = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if rawFD < 0 && errno == ENOENT { return false }
        guard rawFD >= 0 else { throw Self.failure("open verification file") }
        let fd = Descriptor(rawFD)
        try Self.requireRegular(fd.value)
        let initial = try Self.statFile(fd.value)
        guard initial.st_size == size, size <= limit else { throw ArchiveError.archivedContentChanged }
        var hasher = SHA256()
        var total: Int64 = 0
        while true {
            let bytes = try Self.chunk(from: fd.value)
            if bytes.isEmpty { break }
            guard total <= limit - Int64(bytes.count) else { throw ArchiveError.archivedContentChanged }
            total += Int64(bytes.count)
            hasher.update(data: bytes)
            try Task.checkCancellation()
        }
        let actual = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard total == size, actual == sha256, Self.unchanged(initial, try Self.statFile(fd.value)) else {
            throw ArchiveError.archivedContentChanged
        }
        return true
    }

    func publish(stageName: String, to directory: Int32, filename: String) throws {
        // A hard-link publication is atomic and fails if the destination exists. Unlike rename it never overwrites.
        guard linkat(staging.value, stageName, directory, filename, 0) == 0 else {
            if errno == EEXIST { throw ArchiveError.destinationConflict }
            throw Self.failure("publish archive file")
        }
        try Self.synchronize(directory)
    }

    func replaceManifest(stageName: String) throws {
        guard renameat(staging.value, stageName, root.value, "manifest.json") == 0 else {
            throw Self.failure("publish manifest")
        }
        try Self.synchronize(root.value)
        try Self.synchronize(staging.value)
    }

    func removeStageIfPresent(_ name: String) throws {
        guard unlinkat(staging.value, name, 0) == 0 || errno == ENOENT else {
            throw Self.failure("remove transaction staging file")
        }
    }

    func stageNames() throws -> [String] {
        let duplicate = dup(staging.value)
        guard duplicate >= 0 else { throw Self.failure("inspect staging directory") }
        guard let stream = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw Self.failure("inspect staging directory")
        }
        defer { closedir(stream) }
        rewinddir(stream)
        var result: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw Self.failure("read staging entries") }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard result.count < 30_000 else { throw ArchiveError.invalidJournal }
            result.append(name)
        }
        return result.sorted()
    }
}
