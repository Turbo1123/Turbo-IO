import Foundation

/// Incremental, terminal-on-error inspection of one non-chained Opus version-1/mapping-0 stream.
/// Value semantics: keep one instance per file; callers must not feed the same instance concurrently.
public struct OggOpusInspector: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public static let maximumOggPageBytes = 27 + 255 + 255 * 255
    public private(set) var status: InspectorStatus = .accepting
    public private(set) var peakBufferedPageBytes = 0
    public var bufferedPageBytes: Int { pageBuffer.count }
    public var description: String { "OggOpusInspector(status: \(status.rawValue))" }
    public var debugDescription: String { description }

    private enum PageStage: Sendable { case fixedHeader, laces, payload }
    private let limits: InspectionLimits
    private var pageBuffer: [UInt8] = []
    private var stage = PageStage.fixedHeader
    private var expectedBytes = 27
    private var headerBytes = 27
    private var inputBytes = 0
    private var pages = 0
    private var serial: UInt32?
    private var sequence: UInt32?
    private var eos = false
    private var pending = false
    private var packetBytes = 0
    private var identificationPrefix: [UInt8] = []
    private var comments = CommentHeaderInspector()
    private var audioPrefix: [UInt8] = []
    private var packets = 0
    private var audioPackets = 0
    private var audioBytes = 0
    private var histogram: [Int: Int] = [:]
    private var silenceMatches = 0
    private var silenceIndices: [Int] = []
    private var identification: OpusIdentification?
    private var lastGranule: Int64?
    private var firstAudioGranule: Int64?
    private var continuedPages = 0
    private var audioPages = 0
    private var audioPageCounts: [Int: Int] = [:]
    private var firstAudioPackets: Int?

    public init(limits: InspectionLimits = InspectionLimits()) throws {
        try limits.validate()
        self.limits = limits
    }

    /// Consumes a caller-owned chunk without retaining the complete chunk. Empty chunks are allowed before finish.
    /// Any parse, limit, or cancellation error makes the inspector terminal; create a new instance to retry.
    public mutating func push(_ chunk: Data) throws {
        try requireAccepting()
        do {
            try Task.checkCancellation()
            guard chunk.count <= limits.maximumInputBytes - inputBytes else { throw OggInspectionError.limitExceeded(.inputBytes) }
            inputBytes += chunk.count
            try chunk.withUnsafeBytes { raw in
                let bytes = raw.bindMemory(to: UInt8.self)
                var at = 0
                while at < bytes.count {
                    let take = min(expectedBytes - pageBuffer.count, bytes.count - at)
                    pageBuffer.append(contentsOf: bytes[at..<(at + take)])
                    at += take
                    peakBufferedPageBytes = max(peakBufferedPageBytes, pageBuffer.count)
                    while pageBuffer.count == expectedBytes {
                        switch stage {
                        case .fixedHeader:
                            guard pageBuffer[0..<4].elementsEqual("OggS".utf8) else { throw OggInspectionError.invalid(.capturePattern) }
                            guard pageBuffer[4] == 0 else { throw OggInspectionError.unsupported(.oggVersion) }
                            guard pageBuffer[5] & ~UInt8(7) == 0 else { throw OggInspectionError.invalid(.reservedHeaderFlags) }
                            headerBytes = 27 + Int(pageBuffer[26])
                            expectedBytes = headerBytes
                            stage = .laces
                        case .laces:
                            expectedBytes = headerBytes + pageBuffer[27..<headerBytes].reduce(0) { $0 + Int($1) }
                            stage = .payload
                        case .payload:
                            try inspectPage()
                            pageBuffer.removeAll(keepingCapacity: true)
                            stage = .fixedHeader
                            expectedBytes = 27
                            headerBytes = 27
                            try Task.checkCancellation()
                        }
                    }
                }
            }
        } catch {
            status = .failed
            releaseEphemeralContent()
            throw error
        }
    }

    /// Returns a report only after EOF, both headers, complete packet boundaries, and EOS pass the checked subset.
    public mutating func finish() throws -> OggOpusStructureReport {
        try requireAccepting()
        do {
            try Task.checkCancellation()
            guard pageBuffer.isEmpty else { throw OggInspectionError.invalid(.truncatedPageOrTrailingBytes) }
            guard !pending else { throw OggInspectionError.invalid(.unfinishedPacketAtEOF) }
            guard pages > 0, packets >= 3, let header = identification,
                  let granule = lastGranule, let firstGranule = firstAudioGranule,
                  let firstPagePackets = firstAudioPackets else { throw OggInspectionError.invalid(.missingHeadersOrAudio) }
            guard eos else { throw OggInspectionError.invalid(.missingEOS) }
            guard granule >= Int64(header.preSkip) else { throw OggInspectionError.invalid(.granuleBeforePreskip) }
            let report = OggOpusStructureReport(
                schema: "rayneo-swift-ogg-opus-structure-v1", checkedStructurePassed: true,
                inputBytes: inputBytes, pageCount: pages, crcCheckedPages: pages,
                contiguousPageSequence: true, bosPresent: true, eosPresent: true,
                continuedPages: continuedPages, audioPages: audioPages, firstAudioPagePackets: firstPagePackets,
                audioPacketsPerPageHistogram: audioPageCounts.sorted { $0.key < $1.key }.map { AudioPagePacketCount(packets: $0.key, pages: $0.value) },
                packetCountIncludingHeaders: packets, audioPacketCount: audioPackets, audioPacketPayloadBytes: audioBytes,
                sizeHistogram: histogram.sorted { $0.key < $1.key }.map { PacketSizeCount(size: $0.key, count: $0.value) },
                matchingThreeByteSilencePackets: silenceMatches, matchingSilenceAudioPacketIndicesZeroBased: silenceIndices,
                matchingSilenceIndicesTruncated: silenceMatches > silenceIndices.count,
                opusHeader: header, firstAudioGranule: firstGranule, finalGranule: granule,
                finalPCMPosition: granule - Int64(header.preSkip), finalPCMPositionSeconds: Double(granule - Int64(header.preSkip)) / 48_000,
                caveats: [
                    "Only the declared Ogg/Opus structure subset passed; this is not a full RFC conformance result.",
                    "No codec decoding, packet-duration parsing, or packet/granule duration reconciliation was performed.",
                    "Final PCM position is not measured decoded or recorded duration; initial granule offsets may be nonzero.",
                    "This does not prove original capture or wireless coverage, acoustic quality, ASR correctness, or why a matching packet exists.",
                    "Only one non-chained version-1 mapping-family-0 stream with nonempty pages is supported."
                ]
            )
            status = .finished
            releaseEphemeralContent()
            return report
        } catch {
            status = .failed
            releaseEphemeralContent()
            throw error
        }
    }

    private func requireAccepting() throws {
        switch status {
        case .accepting: return
        case .finished: throw OggInspectionError.inspectorAlreadyFinished
        case .failed: throw OggInspectionError.inspectorFailed
        }
    }

    private mutating func releaseEphemeralContent() {
        pageBuffer.removeAll(keepingCapacity: false)
        identificationPrefix.removeAll(keepingCapacity: false)
        audioPrefix.removeAll(keepingCapacity: false)
        comments = CommentHeaderInspector()
        serial = nil
        sequence = nil
    }

    private mutating func inspectPage() throws {
        guard OggCRC32.calculate(pageBuffer, zeroPageChecksumField: true) == little32(pageBuffer, 22) else {
            throw OggInspectionError.invalid(.pageCRC)
        }
        let pageSerial = little32(pageBuffer, 14)
        let pageSequence = little32(pageBuffer, 18)
        let flags = pageBuffer[5]
        if eos {
            if pageSerial != serial && flags & 2 != 0 { throw OggInspectionError.unsupported(.chainedStreams) }
            throw OggInspectionError.invalid(.dataAfterEOS)
        }
        guard pages < limits.maximumPages else { throw OggInspectionError.limitExceeded(.pageCount) }
        if pages == 0 {
            guard flags & 2 != 0, pageSequence == 0 else { throw OggInspectionError.invalid(.initialBOSOrSequence) }
            serial = pageSerial
        } else {
            guard pageSerial == serial else { throw OggInspectionError.unsupported(.multipleLogicalStreams) }
            guard flags & 2 == 0 else { throw OggInspectionError.invalid(.repeatedBOS) }
            guard let previous = sequence, pageSequence == previous &+ 1 else { throw OggInspectionError.invalid(.pageSequenceGap) }
        }
        // Empty pages have continuation subtleties not needed by the observed subset; reject as unsupported, not corrupt.
        guard headerBytes > 27 else { throw OggInspectionError.unsupported(.emptyPage) }
        guard (flags & 1 != 0) == pending else { throw OggInspectionError.invalid(.packetContinuation) }
        if flags & 1 != 0 { continuedPages += 1 }
        sequence = pageSequence
        let packetsBefore = packets
        let audioBefore = audioPackets
        var at = headerBytes
        for laceAt in 27..<headerBytes {
            let length = Int(pageBuffer[laceAt])
            guard length <= limits.maximumPacketBytes - packetBytes else { throw OggInspectionError.limitExceeded(.packetBytes) }
            packetBytes += length
            for byteAt in at..<(at + length) {
                let byte = pageBuffer[byteAt]
                if packets == 0 {
                    if identificationPrefix.count < 19 { identificationPrefix.append(byte) }
                } else if packets == 1 {
                    try comments.consume(byte)
                } else if audioPrefix.count < 8 {
                    audioPrefix.append(byte)
                }
            }
            at += length
            pending = length == 255
            if !pending {
                let wasComment = packets == 1
                try completePacket()
                if wasComment && laceAt != headerBytes - 1 { throw OggInspectionError.invalid(.mixedHeadersAndAudio) }
            }
        }
        if pages == 0 && (packets != 1 || pending) { throw OggInspectionError.invalid(.identificationPage) }
        if packetsBefore < 2 && audioPackets > audioBefore { throw OggInspectionError.invalid(.mixedHeadersAndAudio) }
        let granule = signedLittle64(pageBuffer, 6)
        let completed = packets - packetsBefore
        if audioPackets > audioBefore {
            guard granule >= 0 else { throw OggInspectionError.invalid(.audioGranule) }
            guard granule <= 9_007_199_254_740_991 else { throw OggInspectionError.unsupported(.granuleBeyondExactJSONIntegerRange) }
            if let last = lastGranule, granule < last { throw OggInspectionError.invalid(.granuleRegression) }
            lastGranule = granule
            if firstAudioGranule == nil { firstAudioGranule = granule }
            let count = audioPackets - audioBefore
            if firstAudioPackets == nil { firstAudioPackets = count }
            audioPageCounts[count, default: 0] += 1
            audioPages += 1
        } else if packets <= 2 && completed > 0 {
            guard granule == 0 else { throw OggInspectionError.invalid(.headerGranule) }
        } else if completed == 0 && granule != -1 {
            throw OggInspectionError.invalid(.unfinishedPacketGranule)
        }
        pages += 1
        if flags & 4 != 0 {
            guard !pending else { throw OggInspectionError.invalid(.unfinishedPacketAtEOS) }
            guard audioPackets > audioBefore else { throw OggInspectionError.unsupported(.eosWithoutCompletedAudio) }
            eos = true
        }
    }

    private mutating func completePacket() throws {
        if packets == 0 {
            guard identificationPrefix.prefix(8).elementsEqual("OpusHead".utf8) else {
                throw OggInspectionError.unsupported(.unrecognizedCodec)
            }
            guard packetBytes >= 19, identificationPrefix.count == 19 else { throw OggInspectionError.invalid(.identificationHeader) }
            let head = identificationPrefix
            guard head[8] == 1 else { throw OggInspectionError.unsupported(.opusVersion) }
            guard head[18] == 0 else { throw OggInspectionError.unsupported(.mappingFamily) }
            guard packetBytes == 19, head[9] == 1 || head[9] == 2 else { throw OggInspectionError.invalid(.mappingZeroHeader) }
            identification = OpusIdentification(version: head[8], channels: head[9], preSkip: little16(head, 10),
                inputSampleRate: little32(head, 12), outputGainQ78: Int16(bitPattern: little16(head, 16)), mappingFamily: head[18])
            identificationPrefix.removeAll(keepingCapacity: false)
        } else if packets == 1 {
            try comments.finish()
            comments = CommentHeaderInspector()
        } else {
            guard packetBytes > 0 else { throw OggInspectionError.invalid(.emptyAudioPacket) }
            guard audioPackets < limits.maximumAudioPackets else { throw OggInspectionError.limitExceeded(.audioPacketCount) }
            if histogram[packetBytes] == nil && histogram.count >= limits.maximumPacketSizeHistogramBuckets {
                throw OggInspectionError.limitExceeded(.packetSizeHistogramBuckets)
            }
            audioPackets += 1
            audioBytes += packetBytes
            histogram[packetBytes, default: 0] += 1
            if packetBytes == 3 && audioPrefix == [0xf8, 0xff, 0xfe] {
                silenceMatches += 1
                if silenceIndices.count < limits.maximumStoredSilenceIndices { silenceIndices.append(audioPackets - 1) }
            }
        }
        packets += 1
        packetBytes = 0
        audioPrefix.removeAll(keepingCapacity: true)
    }
}
