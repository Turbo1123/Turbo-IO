import Foundation

public struct InspectionLimits: Sendable {
    public let maximumInputBytes: Int
    public let maximumPacketBytes: Int
    public let maximumPages: Int
    public let maximumAudioPackets: Int
    public let maximumPacketSizeHistogramBuckets: Int
    public let maximumStoredSilenceIndices: Int

    public init(maximumInputBytes: Int = 64 * 1_024 * 1_024,
                maximumPacketBytes: Int = 1_024 * 1_024,
                maximumPages: Int = 1_000_000,
                maximumAudioPackets: Int = 2_000_000,
                maximumPacketSizeHistogramBuckets: Int = 4_096,
                maximumStoredSilenceIndices: Int = 32) {
        self.maximumInputBytes = maximumInputBytes
        self.maximumPacketBytes = maximumPacketBytes
        self.maximumPages = maximumPages
        self.maximumAudioPackets = maximumAudioPackets
        self.maximumPacketSizeHistogramBuckets = maximumPacketSizeHistogramBuckets
        self.maximumStoredSilenceIndices = maximumStoredSilenceIndices
    }

    func validate() throws {
        guard (1...8_589_934_592).contains(maximumInputBytes),
              (19...16_777_216).contains(maximumPacketBytes),
              (1...10_000_000).contains(maximumPages),
              (1...20_000_000).contains(maximumAudioPackets),
              (1...65_536).contains(maximumPacketSizeHistogramBuckets),
              (0...1_024).contains(maximumStoredSilenceIndices) else {
            throw OggInspectionError.invalidConfiguration
        }
    }
}

public enum InvalidStructure: String, Codable, Sendable {
    case capturePattern, reservedHeaderFlags, pageCRC, initialBOSOrSequence, repeatedBOS
    case pageSequenceGap, packetContinuation, identificationPage, identificationHeader
    case mappingZeroHeader, commentHeader, commentLengths, mixedHeadersAndAudio
    case emptyAudioPacket, audioGranule, granuleRegression, headerGranule
    case unfinishedPacketGranule, unfinishedPacketAtEOS, unfinishedPacketAtEOF
    case dataAfterEOS, truncatedPageOrTrailingBytes, missingHeadersOrAudio, missingEOS, granuleBeforePreskip
}

public enum UnsupportedStructure: String, Codable, Sendable {
    case oggVersion, opusVersion, mappingFamily, unrecognizedCodec
    case multipleLogicalStreams, chainedStreams, emptyPage, eosWithoutCompletedAudio
    case granuleBeyondExactJSONIntegerRange
}

public enum InspectionLimit: String, Codable, Sendable {
    case inputBytes, packetBytes, pageCount, audioPacketCount, packetSizeHistogramBuckets
}

/// Fixed reasons only: errors never include input bytes, comments, vendor text, paths, hashes, or stream identifiers.
public enum OggInspectionError: Error, Equatable, Codable, Sendable {
    case invalid(InvalidStructure)
    case unsupported(UnsupportedStructure)
    case limitExceeded(InspectionLimit)
    case invalidConfiguration
    case inspectorAlreadyFinished
    case inspectorFailed
}

public enum InspectorStatus: String, Codable, Sendable { case accepting, finished, failed }

public struct OpusIdentification: Equatable, Codable, Sendable {
    public let version: UInt8
    public let channels: UInt8
    public let preSkip: UInt16
    /// Informational input metadata, not a measured microphone or decoder output sample rate.
    public let inputSampleRate: UInt32
    public let outputGainQ78: Int16
    public let mappingFamily: UInt8
}

public struct PacketSizeCount: Equatable, Codable, Sendable {
    public let size: Int
    public let count: Int
}

public struct AudioPagePacketCount: Equatable, Codable, Sendable {
    public let packets: Int
    public let pages: Int
}

/// Successful checked-subset result. It is intentionally not called "valid audio" or "ready for ASR".
public struct OggOpusStructureReport: Equatable, Codable, Sendable {
    public let schema: String
    public let checkedStructurePassed: Bool
    public let inputBytes: Int
    public let pageCount: Int
    public let crcCheckedPages: Int
    public let contiguousPageSequence: Bool
    public let bosPresent: Bool
    public let eosPresent: Bool
    public let continuedPages: Int
    public let audioPages: Int
    public let firstAudioPagePackets: Int
    public let audioPacketsPerPageHistogram: [AudioPagePacketCount]
    public let packetCountIncludingHeaders: Int
    public let audioPacketCount: Int
    public let audioPacketPayloadBytes: Int
    public let sizeHistogram: [PacketSizeCount]
    public let matchingThreeByteSilencePackets: Int
    public let matchingSilenceAudioPacketIndicesZeroBased: [Int]
    public let matchingSilenceIndicesTruncated: Bool
    public let opusHeader: OpusIdentification
    public let firstAudioGranule: Int64
    public let finalGranule: Int64
    public let finalPCMPosition: Int64
    /// A container timeline position. Not decoded duration, recorded duration, or an audio-quality measurement.
    public let finalPCMPositionSeconds: Double
    public let caveats: [String]
}
