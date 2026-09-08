import Foundation
import CryptoKit
import Darwin

private struct SnapshotIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
    init(_ value: stat) { device = value.st_dev; inode = value.st_ino }
}

/// A single invocation's pinned output directory and exact ownership ledger, never a recursive cleaner.
final class SnapshotDestination {
    let parentURL: URL
    let parent: Descriptor
    let sourceRoot: Int32
    let stageName: String
    let finalName: String
    var finalURL: URL { parentURL.appendingPathComponent(finalName, isDirectory: true) }
    private(set) var published = false
    private var stageCreated = false
    private var stage: Descriptor?
    private var audio: Descriptor?
    private var notes: Descriptor?
    private struct OwnedEntry {
        let parent: Int32
        let name: String
        let identity: SnapshotIdentity
        let isDirectory: Bool
        var verifiedMetadata: stat?
    }
    private var owned: [OwnedEntry] = []

    init(parentURL: URL, sourceRoot: Int32, snapshotID: UUID) throws {
        // Foundation standardization can rewrite /private/var back to the /var symlink on Darwin.
        // Preserve the caller's physical path; never introduce aliases before a no-follow walk.
        self.parentURL = parentURL
        self.parent = try Self.openDirectoryPath(parentURL)
        self.sourceRoot = sourceRoot
        let stem = snapshotID.uuidString.lowercased()
        stageName = ".rayneo-snapshot-\(stem).staging"
        finalName = "rayneo-snapshot-\(stem)"
        var filesystem = statfs()
        guard fstatfs(parent.value, &filesystem) == 0 else { throw ArchiveFileSystem.failure("inspect snapshot filesystem") }
        guard filesystem.f_flags & UInt32(MNT_LOCAL) != 0 else { throw SnapshotError.targetNotLocal }
        try Self.verifyAncestry(parent: parent.value, sourceRoot: sourceRoot)
    }

    // Do not canonicalize through a symbolic link: each component must itself be a real directory.
    private static func openDirectoryPath(_ url: URL) throws -> Descriptor {
        guard url.isFileURL, url.host == nil || url.host == "", url.query == nil, url.fragment == nil,
              url.path.hasPrefix("/"), !url.path.utf8.contains(0), !url.pathComponents.contains(".."),
              url.pathComponents.dropFirst().allSatisfy({ !$0.utf8.contains(0) && !$0.contains("/") }) else {
            throw ArchiveError.invalidFileURL
        }
        let fd = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SnapshotError.targetDirectoryRequired }
        var current = Descriptor(fd)
        for component in url.pathComponents where component != "/" && component != "." {
            var info = stat()
            guard fstatat(current.value, component, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw SnapshotError.targetDirectoryRequired }
            if info.st_mode & S_IFMT == S_IFLNK { throw SnapshotError.symbolicLinkNotAllowed }
            let child = openat(current.value, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw SnapshotError.targetDirectoryRequired }
            let next = Descriptor(child)
            guard SnapshotIdentity(info) == SnapshotIdentity(try ArchiveFileSystem.statFile(next.value)) else {
                throw SnapshotError.locationChanged
            }
            current = next
        }
        return current
    }

    private static func verifyAncestry(parent: Int32, sourceRoot: Int32) throws {
        let sourceIdentity = SnapshotIdentity(try ArchiveFileSystem.statFile(sourceRoot))
        let fd = dup(parent)
        guard fd >= 0 else { throw ArchiveFileSystem.failure("inspect snapshot ancestry") }
        var current = Descriptor(fd)
        for _ in 0..<1_024 {
            let identity = SnapshotIdentity(try ArchiveFileSystem.statFile(current.value))
            guard identity != sourceIdentity else { throw SnapshotError.targetInsideArchive }
            var marker = stat()
            if fstatat(current.value, "snapshot-manifest.json", &marker, AT_SYMLINK_NOFOLLOW) == 0 {
                throw SnapshotError.targetInsideSnapshot
            }
            guard errno == ENOENT else { throw ArchiveFileSystem.failure("inspect existing snapshot marker") }
            let fd = openat(current.value, "..", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw ArchiveFileSystem.failure("inspect snapshot ancestor") }
            let above = Descriptor(fd)
            if SnapshotIdentity(try ArchiveFileSystem.statFile(above.value)) == identity { return }
            current = above
        }
        throw SnapshotError.locationChanged
    }

    private static func identityAt(parent: Int32, name: String) -> SnapshotIdentity? {
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { return nil }
        return SnapshotIdentity(info)
    }

    func createStage() throws {
        try verifyParent()
        guard mkdirat(parent.value, stageName, mode_t(0o700)) == 0 else {
            if errno == EEXIST { throw SnapshotError.destinationConflict }
            throw ArchiveFileSystem.failure("create snapshot staging directory")
        }
        stageCreated = true
        let fd = openat(parent.value, stageName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SnapshotError.locationChanged }
        stage = Descriptor(fd)
        audio = try createDirectory("audio", in: fd)
        notes = try createDirectory("notes", in: fd)
        try ArchiveFileSystem.synchronize(parent.value)
    }

    private func createDirectory(_ name: String, in directory: Int32) throws -> Descriptor {
        guard mkdirat(directory, name, mode_t(0o700)) == 0 else { throw ArchiveFileSystem.failure("create snapshot subdirectory") }
        let fd = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw SnapshotError.locationChanged }
        let result = Descriptor(fd)
        owned.append(OwnedEntry(parent: directory, name: name,
                                identity: SnapshotIdentity(try ArchiveFileSystem.statFile(fd)), isDirectory: true, verifiedMetadata: nil))
        return result
    }

    private func newFile(_ name: String, in directory: Int32) throws -> Descriptor {
        let result = try ArchiveFileSystem.openFile(in: directory, name: name, flags: O_WRONLY | O_CREAT | O_EXCL)
        owned.append(OwnedEntry(parent: directory, name: name,
                                identity: SnapshotIdentity(try ArchiveFileSystem.statFile(result.value)), isDirectory: false, verifiedMetadata: nil))
        return result
    }

    private func verifyParent() throws {
        let current = try Self.openDirectoryPath(parentURL)
        guard SnapshotIdentity(try ArchiveFileSystem.statFile(current.value)) == SnapshotIdentity(try ArchiveFileSystem.statFile(parent.value)) else {
            throw SnapshotError.locationChanged
        }
        try Self.verifyAncestry(parent: parent.value, sourceRoot: sourceRoot)
    }

    func verifyLocation() throws {
        try verifyParent()
        guard let stage, Self.identityAt(parent: parent.value, name: published ? finalName : stageName) == SnapshotIdentity(try ArchiveFileSystem.statFile(stage.value)) else {
            throw SnapshotError.locationChanged
        }
        for entry in owned {
            var info = stat()
            guard fstatat(entry.parent, entry.name, &info, AT_SYMLINK_NOFOLLOW) == 0,
                  SnapshotIdentity(info) == entry.identity else { throw SnapshotError.locationChanged }
            // A same-inode edit after checksum readback is still a changed snapshot. This includes
            // size, nanosecond mtime and ctime, not just the pathname or last-modified timestamp.
            if let verified = entry.verifiedMetadata, !ArchiveFileSystem.unchanged(verified, info) {
                throw ArchiveError.archivedContentChanged
            }
        }
    }

    func copy(_ entry: SnapshotFile, from sourceDirectory: Int32, limit: Int64, copiedChunk: () throws -> Void) throws {
        try verifyLocation()
        let parts = entry.relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == (entry.kind == .audio ? "audio" : "notes"),
              !parts[1].isEmpty, parts[1] != ".", parts[1] != "..", !entry.relativePath.hasPrefix("/") else {
            throw SnapshotError.invalidSelection
        }
        let name = String(parts[1])
        guard let targetDirectory = entry.kind == .audio ? audio?.value : notes?.value else { throw SnapshotError.locationChanged }
        let input = try ArchiveFileSystem.openFile(in: sourceDirectory, name: name, flags: O_RDONLY | O_NONBLOCK)
        try ArchiveFileSystem.requireRegular(input.value)
        let before = try ArchiveFileSystem.statFile(input.value)
        guard before.st_size == entry.byteCount, entry.byteCount <= limit else { throw ArchiveError.archivedContentChanged }
        let output = try newFile(name, in: targetDirectory)
        var hash = SHA256()
        var count: Int64 = 0
        while true {
            try Task.checkCancellation()
            let data = try ArchiveFileSystem.chunk(from: input.value)
            if data.isEmpty { break }
            guard count <= entry.byteCount - Int64(data.count) else { throw ArchiveError.archivedContentChanged }
            try ArchiveFileSystem.write(data, to: output.value)
            hash.update(data: data)
            count += Int64(data.count)
            try copiedChunk()
        }
        guard count == entry.byteCount, Self.hex(hash) == entry.sha256,
              ArchiveFileSystem.unchanged(before, try ArchiveFileSystem.statFile(input.value)),
              Self.identityAt(parent: sourceDirectory, name: name) == SnapshotIdentity(before) else {
            throw ArchiveError.archivedContentChanged
        }
        try ArchiveFileSystem.synchronize(output.value)
        try verifyFile(name, in: targetDirectory, size: entry.byteCount, sha256: entry.sha256)
        try verifyLocation()
    }

    private static func hex(_ hash: SHA256) -> String { hash.finalize().map { String(format: "%02x", $0) }.joined() }

    private func verifyFile(_ name: String, in directory: Int32, size: Int64, sha256: String) throws {
        let file = try ArchiveFileSystem.openFile(in: directory, name: name, flags: O_RDONLY | O_NONBLOCK)
        try ArchiveFileSystem.requireRegular(file.value)
        let before = try ArchiveFileSystem.statFile(file.value)
        guard before.st_size == size else { throw ArchiveError.archivedContentChanged }
        var hash = SHA256()
        var count: Int64 = 0
        while true {
            try Task.checkCancellation()
            let data = try ArchiveFileSystem.chunk(from: file.value)
            if data.isEmpty { break }
            guard count <= size - Int64(data.count) else { throw ArchiveError.archivedContentChanged }
            count += Int64(data.count)
            hash.update(data: data)
        }
        let after = try ArchiveFileSystem.statFile(file.value)
        guard count == size, Self.hex(hash) == sha256,
              ArchiveFileSystem.unchanged(before, after) else { throw ArchiveError.archivedContentChanged }
        guard let index = owned.firstIndex(where: { $0.parent == directory && $0.name == name }),
              owned[index].identity == SnapshotIdentity(after) else { throw SnapshotError.locationChanged }
        owned[index].verifiedMetadata = after
    }

    func writeManifest(_ data: Data) throws {
        try verifyLocation()
        guard let stage else { throw SnapshotError.locationChanged }
        let file = try newFile("snapshot-manifest.json", in: stage.value)
        for offset in stride(from: 0, to: data.count, by: ArchiveFileSystem.chunkSize) {
            try Task.checkCancellation()
            try ArchiveFileSystem.write(data.subdata(in: offset..<min(offset + ArchiveFileSystem.chunkSize, data.count)), to: file.value)
        }
        try ArchiveFileSystem.synchronize(file.value)
        try verifyFile("snapshot-manifest.json", in: stage.value, size: Int64(data.count), sha256: digest(data))
        try verifyLocation()
    }

    func publish() throws {
        try Task.checkCancellation()
        try verifyLocation()
        guard let stage, let audio, let notes else { throw SnapshotError.locationChanged }
        for directory in [stage.value, audio.value, notes.value] {
            try requireExactEntries(in: directory)
        }
        try ArchiveFileSystem.synchronize(audio.value)
        try ArchiveFileSystem.synchronize(notes.value)
        try ArchiveFileSystem.synchronize(stage.value)
        // Atomic no-replace publication. Never emulate this with exists + overwriting rename.
        guard renameatx_np(parent.value, stageName, parent.value, finalName, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST || errno == ENOTEMPTY { throw SnapshotError.destinationConflict }
            if errno == ENOTSUP || errno == EINVAL || errno == ENOSYS { throw SnapshotError.publicationUnsupported }
            throw ArchiveFileSystem.failure("publish snapshot directory")
        }
        published = true
        try ArchiveFileSystem.synchronize(parent.value)
    }

    /// Directory existence and known-file hashes alone do not describe the entire exported snapshot.
    /// Repeat the exact-entry check after publication, immediately before constructing the receipt.
    func verifyPublishedContents() throws {
        guard published, let stage, let audio, let notes else { throw SnapshotError.locationChanged }
        try verifyLocation()
        for directory in [stage.value, audio.value, notes.value] { try requireExactEntries(in: directory) }
        try verifyLocation()
    }

    private func requireExactEntries(in directory: Int32) throws {
        var expected = Set(owned.filter { $0.parent == directory }.map(\.name))
        let duplicate = dup(directory)
        guard duplicate >= 0 else { throw ArchiveFileSystem.failure("inspect snapshot entries") }
        guard let stream = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw ArchiveFileSystem.failure("inspect snapshot entries")
        }
        defer { closedir(stream) }
        rewinddir(stream)
        while true {
            try Task.checkCancellation()
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw ArchiveFileSystem.failure("read snapshot entries") }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard expected.remove(name) != nil else { throw SnapshotError.locationChanged }
        }
        guard expected.isEmpty else { throw SnapshotError.locationChanged }
    }

    private func cleanupParentStillLinked(_ directory: Int32) -> Bool {
        guard let stage, let info = try? ArchiveFileSystem.statFile(stage.value),
              Self.identityAt(parent: parent.value, name: stageName) == SnapshotIdentity(info) else { return false }
        if directory == stage.value { return true }
        for (name, descriptor) in [("audio", audio), ("notes", notes)] {
            if let descriptor, descriptor.value == directory, let info = try? ArchiveFileSystem.statFile(directory) {
                return Self.identityAt(parent: stage.value, name: name) == SnapshotIdentity(info)
            }
        }
        return false
    }

    /// No enumeration, recursive deletion, or removal of entries whose identities no longer match.
    func cleanup() -> Bool {
        guard !published else { return false }
        guard stageCreated else { return true }
        guard let stage, let identity = try? ArchiveFileSystem.statFile(stage.value),
              Self.identityAt(parent: parent.value, name: stageName) == SnapshotIdentity(identity) else { return false }
        var complete = true
        for entry in owned.reversed() {
            guard cleanupParentStillLinked(entry.parent),
                  Self.identityAt(parent: entry.parent, name: entry.name) == entry.identity else { complete = false; continue }
            if unlinkat(entry.parent, entry.name, entry.isDirectory ? AT_REMOVEDIR : 0) != 0 { complete = false }
        }
        if complete {
            guard Self.identityAt(parent: parent.value, name: stageName) == SnapshotIdentity(identity),
                  unlinkat(parent.value, stageName, AT_REMOVEDIR) == 0 else { return false }
            try? ArchiveFileSystem.synchronize(parent.value)
        }
        return complete
    }
}
