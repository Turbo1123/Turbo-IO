import Foundation
import CryptoKit
import RayNeoAudioContainer

struct RecordingCoverage: Codable, Equatable {
    var ranges: [Range<Int>] = []
    var highest: Int { ranges.last?.upperBound ?? 0 }
    var contiguous: Bool { ranges.count == 1 && ranges[0].lowerBound == 0 }
    mutating func insert(_ next: Range<Int>) {
        var merged: [Range<Int>] = []
        for range in (ranges + [next]).sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count-1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else { merged.append(range) }
        }
        ranges = merged
    }
}

/// Serial-queue owned, file-backed and crash recoverable. Never cleans glasses storage.
// Runtime owns exactly one instance on its dedicated serial IO queue; no mutable
// Swift state crosses queues. Test callers use isolated roots sequentially.
final class GlassesRecordingInbox: @unchecked Sendable {
    struct Manifest: Codable {
        var wireID: String
        var createdAt = Date()
        var coverage = RecordingCoverage()
        var completed = false
        var failed = false
        var marks: [Int64] = []
        var rawSHA256: String?
        var completionReported: Bool?
    }
    struct Entry: Identifiable, Equatable {
        let id: String
        let createdAt: Date
        let receivedBytes: Int
        let hasGaps: Bool
        let failed: Bool
        let sealed: Bool
        let completionReported: Bool
        var mayRecover: Bool { !failed && !hasGaps && receivedBytes > 0 && (sealed || completionReported) }
        var status: String {
            if failed { return "接收异常 · 不可标完整" }
            if sealed { return "曾封装 · 恢复前需重新校验" }
            if hasGaps { return "存在空洞 · 原始文件保留" }
            return completionReported ? "已记录结束消息 · 待校验封装" : "未记录结束消息 · 不能强行完成"
        }
    }
    struct Catalog { let entries: [Entry]; let unreadable: Int }
    let root: URL
    static let limit = 24 * 1024 * 1024
    init(root: URL) { self.root = root }
    private func folder(_ device: String, _ id: String) -> URL {
        let hash = SHA256.hash(data: Data((device + "\0" + id).utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
    }
    private func read(_ folder: URL) throws -> Manifest {
        let url = folder.appendingPathComponent("receipt.json")
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, (values.fileSize ?? Int.max) < 1_048_576 else { throw DeviceFeatureError.storageLimit }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        guard !manifest.wireID.isEmpty, manifest.wireID.utf8.count <= 128, manifest.coverage.ranges.count <= 4096,
              manifest.marks.count <= 1000, manifest.createdAt.timeIntervalSince1970.isFinite else { throw DeviceFeatureError.invalidPacket }
        var end = 0
        for range in manifest.coverage.ranges {
            guard !range.isEmpty, range.lowerBound >= end, range.upperBound <= Self.limit else { throw DeviceFeatureError.invalidPacket }
            end = range.upperBound
        }
        return manifest
    }
    private func save(_ manifest: Manifest, _ folder: URL) throws {
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("receipt.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func begin(device: String, id: String) throws {
        let dir = folder(device, id)
        if FileManager.default.fileExists(atPath: dir.path) { _ = try read(dir); return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard entries.count < 100 else { throw DeviceFeatureError.storageLimit }
        let used = entries.reduce(0) { n, entry in
            n + ((try? entry.appendingPathComponent("source.rawopus").resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard used < 1_073_741_824 else { throw DeviceFeatureError.storageLimit }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        try Data().write(to: dir.appendingPathComponent("source.rawopus"), options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        try save(Manifest(wireID: id), dir)
    }
    @discardableResult func append(device: String, id: String, offset: Int, data: Data) throws -> Int {
        guard !data.isEmpty, data.count <= 65_536, offset >= 0, offset <= Self.limit - data.count else { throw DeviceFeatureError.storageLimit }
        let dir = folder(device,id); var manifest = try read(dir)
        guard !manifest.failed else { throw DeviceFeatureError.conflictingBytes }
        let incoming = offset..<(offset + data.count)
        guard !manifest.completed else { throw DeviceFeatureError.incomplete }
        let file = try FileHandle(forUpdating: dir.appendingPathComponent("source.rawopus"))
        defer { try? file.close() }
        for previous in manifest.coverage.ranges {
            let overlap = max(previous.lowerBound,incoming.lowerBound)..<max(max(previous.lowerBound,incoming.lowerBound), min(previous.upperBound,incoming.upperBound))
            if !overlap.isEmpty {
                try file.seek(toOffset: UInt64(overlap.lowerBound))
                guard try file.read(upToCount: overlap.count) == data.subdata(in: (overlap.lowerBound-offset)..<(overlap.upperBound-offset)) else {
                    manifest.failed = true; try save(manifest,dir); throw DeviceFeatureError.conflictingBytes
                }
            }
        }
        try file.seek(toOffset: UInt64(offset)); try file.write(contentsOf: data); try file.synchronize()
        manifest.coverage.insert(incoming)
        guard manifest.coverage.ranges.count <= 4096 else { manifest.failed = true; try save(manifest,dir); throw DeviceFeatureError.storageLimit }
        try save(manifest,dir)
        return manifest.coverage.ranges.reduce(0) { $0 + $1.count }
    }
    func mark(device: String, id: String, time: Int64) throws {
        let dir = folder(device,id); var m = try read(dir)
        if !m.marks.contains(time), m.marks.count < 1000 { m.marks.append(time); try save(m,dir) }
    }
    func invalidate(device: String, id: String) {
        let dir = folder(device,id)
        if var m = try? read(dir) { m.failed = true; try? save(m,dir) }
    }
    func recordCompletion(device: String, id: String) throws {
        let dir = folder(device,id); var m = try read(dir)
        m.completionReported = true; try save(m,dir)
    }
    func catalog() throws -> Catalog {
        guard FileManager.default.fileExists(atPath:root.path) else { return Catalog(entries:[],unreadable:0) }
        guard try root.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else { throw DeviceFeatureError.invalidPacket }
        let directories = try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard directories.count <= 200 else { throw DeviceFeatureError.storageLimit }
        var entries: [Entry] = [], unreadable = 0
        for dir in directories {
            do {
                let safe = try checkedFolder(dir.lastPathComponent)
                let m = try read(safe)
                _ = try regularRaw(safe)
                entries.append(Entry(id:dir.lastPathComponent,createdAt:m.createdAt,
                    receivedBytes:m.coverage.ranges.reduce(0) { $0+$1.count },hasGaps:!m.coverage.contiguous,
                    failed:m.failed,sealed:m.completed,completionReported:m.completionReported == true))
            } catch { unreadable += 1 }
        }
        return Catalog(entries:entries.sorted { $0.createdAt > $1.createdAt },unreadable:unreadable)
    }
    private func checkedFolder(_ id: String) throws -> URL {
        guard id.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { throw DeviceFeatureError.invalidPacket }
        guard try root.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey]).isSymbolicLink != true else { throw DeviceFeatureError.invalidPacket }
        let dir = root.appendingPathComponent(id,isDirectory:true)
        let attributes = try dir.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else { throw DeviceFeatureError.invalidPacket }
        return dir
    }
    private func regularRaw(_ dir: URL) throws -> URL {
        let raw = dir.appendingPathComponent("source.rawopus")
        let info = try raw.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, let size = info.fileSize, size >= 0, size <= Self.limit else { throw DeviceFeatureError.invalidPacket }
        return raw
    }
    func rawForRecovery(_ entryID: String) throws -> URL { try regularRaw(checkedFolder(entryID)) }
    func exportRawCopy(_ entryID: String) throws -> URL {
        let source = try rawForRecovery(entryID)
        let target = root.deletingLastPathComponent().appendingPathComponent("RecordingRecoveryExportsV1",isDirectory:true)
        try FileManager.default.createDirectory(at:target,withIntermediateDirectories:true,
            attributes:[.posixPermissions:0o700,.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication])
        guard try target.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true,
              try FileManager.default.contentsOfDirectory(atPath:target.path).count < 20 else { throw DeviceFeatureError.storageLimit }
        let copy = try RecordingFileImporter.copy(source:source,to:target,maximumBytes:Self.limit)
        return target.appendingPathComponent(copy.storedFilename)
    }
    func recoverContainer(_ entryID: String) throws -> URL {
        let dir = try checkedFolder(entryID), m = try read(dir)
        guard m.completionReported == true || m.completed else { throw DeviceFeatureError.incomplete }
        return try finishFolder(dir)
    }
    func recoverDecoded(_ entryID: String) throws -> URL {
        _ = try recoverContainer(entryID)
        return try decodedFolder(checkedFolder(entryID))
    }
    func finish(device: String, id: String) throws -> URL {
        try finishFolder(folder(device,id))
    }
    private func finishFolder(_ dir: URL) throws -> URL {
        var m = try read(dir)
        guard !m.failed, m.coverage.contiguous, m.coverage.highest > 0 else { throw DeviceFeatureError.incomplete }
        let source = try regularRaw(dir)
        let data = try Data(contentsOf: source, options: .mappedIfSafe)
        guard data.count == m.coverage.highest, data.count % 240 == 0 else { throw DeviceFeatureError.incomplete }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard !m.completed || m.rawSHA256 == hash else { throw DeviceFeatureError.conflictingBytes }
        m.rawSHA256 = hash
        // Source bytes are retained. No tail trimming, zero filling or silent repair.
        let output = dir.appendingPathComponent("recording.ogg")
        if !m.completed {
            guard !FileManager.default.fileExists(atPath: output.path) else { throw DeviceFeatureError.incomplete }
            try RawRecordingOgg.write(data, to: output)
            m.completed = true; try save(m,dir)
        }
        return output
    }
    func decodedDerivative(device: String, id: String) throws -> URL {
        try decodedFolder(folder(device,id))
    }
    private func decodedFolder(_ dir: URL) throws -> URL {
        let m = try read(dir)
        guard m.completed, !m.failed else { throw DeviceFeatureError.incomplete }
        #if COMPANION_DEVICE
        // Every attempt has a new destination; failed derivatives never overwrite originals.
        let output = dir.appendingPathComponent("decoded-\(UUID().uuidString).wav")
        let result = dir.appendingPathComponent("source.rawopus").path.withCString { source in
            output.path.withCString { RNRecordingRawToWAV(source,$0) }
        }
        guard result == 0 else { throw DeviceFeatureError.unsupportedFile }
        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.completeUntilFirstUserAuthentication],ofItemAtPath:output.path)
        return output
        #else
        throw DeviceFeatureError.unsupportedFile
        #endif
    }
}

enum RawRecordingOgg {
    static func write(_ raw: Data, to output: URL) throws {
        guard !raw.isEmpty, raw.count <= GlassesRecordingInbox.limit, raw.count % 240 == 0 else { throw DeviceFeatureError.unsupportedFile }
        try Data().write(to: output, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        let file = try FileHandle(forWritingTo: output); defer { try? file.close() }
        var sequence: UInt32 = 0
        func page(_ packets: [Data], flags: UInt8, granule: UInt64) throws {
            var header = Data("OggS".utf8); header.append(contentsOf: [0,flags])
            append(granule, to: &header); append(UInt32(0x524E494F), to: &header); append(sequence, to: &header)
            append(UInt32(0), to: &header); header.append(UInt8(packets.count))
            for packet in packets { header.append(UInt8(packet.count)) }
            for packet in packets { header.append(packet) }
            var checksum = OggCRC32.compute(header).littleEndian
            withUnsafeBytes(of: &checksum) { header.replaceSubrange(22..<26, with: $0) }
            try file.write(contentsOf: header); sequence += 1
        }
        var head = Data("OpusHead".utf8); head.append(contentsOf: [1,2]); append(UInt16(312), to: &head)
        append(UInt32(16000), to: &head); append(UInt16(0), to: &head); head.append(0)
        try page([head], flags: 2, granule: 0)
        var tags = Data("OpusTags".utf8); append(UInt32(7), to: &tags); tags.append(Data("CompanJ".utf8)); append(UInt32(0), to: &tags)
        try page([tags], flags: 0, granule: 0)
        let count = raw.count / 240
        for first in stride(from: 0, to: count, by: 50) {
            let end = min(count, first + 50)
            let packets = try (first..<end).map { i -> Data in
                let packet = raw.subdata(in: (i*240)..<((i+1)*240))
                guard packet.contains(where: { $0 != 0 }) else { throw DeviceFeatureError.unsupportedFile }
                return packet
            }
            try page(packets, flags: end == count ? 4 : 0, granule: 312 + UInt64(end) * 960)
        }
        try file.synchronize()
    }
    static func append<T: FixedWidthInteger>(_ n: T, to data: inout Data) {
        var value = n.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }
}
