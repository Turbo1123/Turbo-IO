import XCTest
import Foundation
@testable import RayNeoAudioContainer

// Fixtures are synthetic container bytes, never real recordings. No codec is invoked.
private func independentCRC(_ bytes: Data) -> UInt32 {
    var crc: UInt32 = 0
    for byte in bytes {
        crc ^= UInt32(byte) << 24
        for _ in 0..<8 {
            let top = crc & 0x8000_0000 != 0
            crc = crc &<< 1
            if top { crc ^= 0x04c1_1db7 }
        }
    }
    return crc
}

private func put<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
    let bits = UInt64(truncatingIfNeeded: value)
    for index in 0..<MemoryLayout<T>.size { data[offset + index] = UInt8(truncatingIfNeeded: bits >> (index * 8)) }
}

private func recheck(_ page: Data) -> Data {
    var page = page
    put(UInt32(0), into: &page, at: 22)
    put(independentCRC(page), into: &page, at: 22)
    return page
}

private func page(_ sequence: UInt32, flags: UInt8, granule: Int64, laces: [UInt8], payload: Data, stream: UInt32 = 117) -> Data {
    precondition(laces.count <= 255 && laces.reduce(0, { $0 + Int($1) }) == payload.count)
    var result = Data(repeating: 0, count: 27 + laces.count)
    result.replaceSubrange(0..<4, with: Data("OggS".utf8))
    result[5] = flags
    put(granule, into: &result, at: 6)
    put(stream, into: &result, at: 14)
    put(sequence, into: &result, at: 18)
    result[26] = UInt8(laces.count)
    result.replaceSubrange(27..<(27 + laces.count), with: laces)
    result.append(payload)
    return recheck(result)
}

private func head() -> Data {
    var result = Data(repeating: 0, count: 19)
    result.replaceSubrange(0..<8, with: Data("OpusHead".utf8))
    result[8] = 1; result[9] = 2
    put(UInt16(312), into: &result, at: 10)
    put(UInt32(16_000), into: &result, at: 12)
    return result
}

private func tags(vendor: Data = Data("SYNTHETIC_VENDOR_NOT_FOR_OUTPUT".utf8), comments: [Data] = [], padding: Data = Data()) -> Data {
    var result = Data("OpusTags".utf8)
    func appendLength(_ length: Int) {
        let start = result.count
        result.append(Data(repeating: 0, count: 4))
        put(UInt32(length), into: &result, at: start)
    }
    appendLength(vendor.count); result.append(vendor)
    appendLength(comments.count)
    for comment in comments { appendLength(comment.count); result.append(comment) }
    result.append(padding)
    return result
}

private func base() -> [Data] {
    let h = head(), t = tags()
    return [page(0, flags: 2, granule: 0, laces: [UInt8(h.count)], payload: h),
            page(1, flags: 0, granule: 0, laces: [UInt8(t.count)], payload: t)]
}

private func fixture() -> [Data] {
    base() + [page(2, flags: 4, granule: 960, laces: [3], payload: Data([0xf8, 0xff, 0xfe]))]
}

private func joined(_ pages: [Data]) -> Data { pages.reduce(into: Data()) { $0.append($1) } }

private func inspect(_ pages: [Data], chunkSize: Int = 65_536, limits: InspectionLimits = InspectionLimits()) throws -> OggOpusStructureReport {
    let bytes = joined(pages)
    var inspector = try OggOpusInspector(limits: limits)
    for at in stride(from: 0, to: bytes.count, by: chunkSize) {
        try inspector.push(bytes.subdata(in: at..<min(at + chunkSize, bytes.count)))
    }
    return try inspector.finish()
}

private func reject(_ pages: [Data], as expected: OggInspectionError, limits: InspectionLimits = InspectionLimits(), file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertThrowsError(try inspect(pages, limits: limits), file: file, line: line) {
        XCTAssertEqual($0 as? OggInspectionError, expected, file: file, line: line)
    }
}

final class OggOpusInspectorTests: XCTestCase {
    func testIndependentCRCVectorAndZeroedFieldNeverMutateInput() {
        XCTAssertEqual(OggCRC32.compute(Data("123456789".utf8)), 0x89a1_897f)
        XCTAssertEqual(independentCRC(Data("123456789".utf8)), 0x89a1_897f)
        let original = fixture()[0]
        let checksum = original[22..<26].enumerated().reduce(UInt32(0)) { $0 | (UInt32($1.element) << ($1.offset * 8)) }
        XCTAssertEqual(OggCRC32.compute(original, zeroPageChecksumField: true), checksum)
        XCTAssertEqual(original, fixture()[0])
    }

    func testEverySingleSplitAndManyChunkSizesAreEquivalent() throws {
        let bytes = joined(fixture())
        let expected = try inspect(fixture())
        for split in 0...bytes.count {
            var inspector = try OggOpusInspector()
            try inspector.push(bytes.subdata(in: 0..<split))
            try inspector.push(Data())
            try inspector.push(bytes.subdata(in: split..<bytes.count))
            XCTAssertEqual(try inspector.finish(), expected)
        }
        for size in [1, 2, 3, 7, 26, 27, 28, 31, 63, 127, 255, 65_536] {
            XCTAssertEqual(try inspect(fixture(), chunkSize: size), expected)
        }
        XCTAssertEqual(expected.pageCount, 3)
        XCTAssertEqual(expected.crcCheckedPages, 3)
        XCTAssertEqual(expected.audioPacketCount, 1)
        XCTAssertEqual(expected.packetCountIncludingHeaders, 3)
        XCTAssertEqual(expected.finalPCMPosition, 648)
        XCTAssertEqual(expected.opusHeader.inputSampleRate, 16_000)
    }

    func testReportsAndErrorsContainNoVendorCommentsContentOrStreamNumber() throws {
        let t = tags(vendor: Data("PRIVATE_VENDOR_ABC".utf8), comments: [Data("PRIVATE_BODY_XYZ".utf8)], padding: Data("PADDING_PRIVATE".utf8))
        let pages = [fixture()[0], page(1, flags: 0, granule: 0, laces: [UInt8(t.count)], payload: t), fixture()[2]]
        let report = try inspect(pages)
        let json = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        for secret in ["PRIVATE_VENDOR", "PRIVATE_BODY", "PADDING_PRIVATE", "serial", "streamNumber", "filename"] {
            XCTAssertFalse(json.contains(secret))
        }
        var inspector = try OggOpusInspector()
        try inspector.push(pages[0])
        XCTAssertEqual(String(reflecting: inspector), "OggOpusInspector(status: accepting)")
        let errorData = try JSONEncoder().encode(OggInspectionError.unsupported(.multipleLogicalStreams))
        XCTAssertFalse(String(decoding: errorData, as: UTF8.self).contains("117"))
    }

    func testContinuedAudioExact255AndZeroLaceTermination() throws {
        let result = try inspect(base() + [
            page(2, flags: 0, granule: -1, laces: [255], payload: Data(repeating: 1, count: 255)),
            page(3, flags: 5, granule: 960, laces: [0], payload: Data())
        ], chunkSize: 13)
        XCTAssertEqual(result.continuedPages, 1)
        XCTAssertEqual(result.sizeHistogram, [PacketSizeCount(size: 255, count: 1)])
        XCTAssertEqual(result.audioPages, 1)
    }

    func testCommentHeaderCanSpanPagesWithoutRetainingText() throws {
        let t = tags(vendor: Data(repeating: 0x61, count: 248), comments: [Data(), Data(repeating: 0x62, count: 280)], padding: Data([0, 1, 255]))
        XCTAssertGreaterThan(t.count, 510)
        let remainder = t.count - 510
        let result = try inspect([
            fixture()[0],
            page(1, flags: 0, granule: -1, laces: [255], payload: t.subdata(in: 0..<255)),
            page(2, flags: 1, granule: -1, laces: [255], payload: t.subdata(in: 255..<510)),
            page(3, flags: 1, granule: 0, laces: [UInt8(remainder)], payload: t.subdata(in: 510..<t.count)),
            page(4, flags: 4, granule: 960, laces: [1], payload: Data([7]))
        ], chunkSize: 1)
        XCTAssertEqual(result.continuedPages, 2)
        XCTAssertEqual(result.audioPacketCount, 1)
    }

    func testExactSilencePatternAndBoundedIndices() throws {
        let other = Data([0xf8, 0xff, 0xfd]), match = Data([0xf8, 0xff, 0xfe])
        let payload = other + (0..<40).reduce(into: Data()) { bytes, _ in bytes.append(match) }
        let result = try inspect(base() + [page(2, flags: 4, granule: 40_000, laces: Array(repeating: 3, count: 41), payload: payload)])
        XCTAssertEqual(result.matchingThreeByteSilencePackets, 40)
        XCTAssertEqual(result.matchingSilenceAudioPacketIndicesZeroBased, Array(1...32))
        XCTAssertTrue(result.matchingSilenceIndicesTruncated)
        let none = try inspect(fixture(), limits: InspectionLimits(maximumStoredSilenceIndices: 0))
        XCTAssertEqual(none.matchingThreeByteSilencePackets, 1)
        XCTAssertEqual(none.matchingSilenceAudioPacketIndicesZeroBased, [])
        XCTAssertTrue(none.matchingSilenceIndicesTruncated)
    }

    func testCRCCorruptionTruncationAndTrailingBytesCannotPass() throws {
        var corrupted = fixture()
        corrupted[2][corrupted[2].count - 1] ^= 1
        reject(corrupted, as: .invalid(.pageCRC))
        let bytes = joined(fixture())
        for count in [1, 4, 26, bytes.count - 1] {
            reject([Data(bytes.prefix(count))], as: .invalid(.truncatedPageOrTrailingBytes))
        }
        reject([bytes, Data([0])], as: .invalid(.truncatedPageOrTrailingBytes))
        var badCapture = fixture(); badCapture[0][0] = 0
        reject(badCapture, as: .invalid(.capturePattern))
    }

    func testPageSequenceBOSReservedFlagsAndEOSAreDistinct() {
        var pages = fixture(); pages[2][18] = 99; pages[2] = recheck(pages[2])
        reject(pages, as: .invalid(.pageSequenceGap))
        pages = fixture(); pages[2][5] = 6; pages[2] = recheck(pages[2])
        reject(pages, as: .invalid(.repeatedBOS))
        pages = fixture(); pages[2][5] = 12; pages[2] = recheck(pages[2])
        reject(pages, as: .invalid(.reservedHeaderFlags))
        pages = fixture(); pages[0][5] = 0; pages[0] = recheck(pages[0])
        reject(pages, as: .invalid(.initialBOSOrSequence))
        pages = fixture(); pages[0][18] = 1; pages[0] = recheck(pages[0])
        reject(pages, as: .invalid(.initialBOSOrSequence))
        pages = fixture(); pages[2][5] = 0; pages[2] = recheck(pages[2])
        reject(pages, as: .invalid(.missingEOS))
        reject(fixture() + [fixture()[2]], as: .invalid(.dataAfterEOS))
    }

    func testUnsupportedVariantsAreNotReportedAsDamagedFiles() {
        var pages = fixture(); pages[1][14] = 99; pages[1] = recheck(pages[1])
        reject(pages, as: .unsupported(.multipleLogicalStreams))
        pages = fixture(); pages[0][4] = 1; pages[0] = recheck(pages[0])
        reject(pages, as: .unsupported(.oggVersion))
        var h = head(); h[8] = 2
        reject([page(0, flags: 2, granule: 0, laces: [19], payload: h)] + Array(fixture().dropFirst()), as: .unsupported(.opusVersion))
        h = head(); h[18] = 1
        reject([page(0, flags: 2, granule: 0, laces: [19], payload: h)] + Array(fixture().dropFirst()), as: .unsupported(.mappingFamily))
        h = head(); h[0] = 0
        reject([page(0, flags: 2, granule: 0, laces: [19], payload: h)] + Array(fixture().dropFirst()), as: .unsupported(.unrecognizedCodec))
        reject(fixture() + [page(0, flags: 2, granule: 0, laces: [19], payload: head(), stream: 222)], as: .unsupported(.chainedStreams))
        reject(base() + [page(2, flags: 0, granule: -1, laces: [], payload: Data())], as: .unsupported(.emptyPage))
    }

    func testContinuationAndEmptyPacketsCannotPass() {
        var pages = fixture(); pages[2][5] = 5; pages[2] = recheck(pages[2])
        reject(pages, as: .invalid(.packetContinuation))
        reject(base() + [page(2, flags: 4, granule: -1, laces: [255], payload: Data(repeating: 1, count: 255))], as: .invalid(.unfinishedPacketAtEOS))
        reject(base() + [page(2, flags: 0, granule: -1, laces: [255], payload: Data(repeating: 1, count: 255))], as: .invalid(.unfinishedPacketAtEOF))
        reject(base() + [page(2, flags: 4, granule: 960, laces: [0], payload: Data())], as: .invalid(.emptyAudioPacket))
        reject(base() + [page(2, flags: 0, granule: -1, laces: [255], payload: Data(repeating: 1, count: 255)),
                         page(3, flags: 4, granule: 960, laces: [0], payload: Data())], as: .invalid(.packetContinuation))
    }

    func testIdentificationShapeAndHeaderPageIsolation() {
        var h = head(); h[9] = 0
        reject([page(0, flags: 2, granule: 0, laces: [19], payload: h)] + Array(fixture().dropFirst()), as: .invalid(.mappingZeroHeader))
        h = head(); h.append(0)
        reject([page(0, flags: 2, granule: 0, laces: [20], payload: h)] + Array(fixture().dropFirst()), as: .invalid(.mappingZeroHeader))
        h = Data(head().prefix(18))
        reject([page(0, flags: 2, granule: 0, laces: [18], payload: h)] + Array(fixture().dropFirst()), as: .invalid(.identificationHeader))
        let t = tags()
        reject([page(0, flags: 2, granule: 0, laces: [19, UInt8(t.count)], payload: head() + t), fixture()[2]], as: .invalid(.identificationPage))
        reject([fixture()[0], page(1, flags: 0, granule: 0, laces: [UInt8(t.count), 1], payload: t + Data([1]))], as: .invalid(.mixedHeadersAndAudio))
        // Even a partial audio packet after the completed comment packet violates the mandatory page break.
        reject([fixture()[0], page(1, flags: 0, granule: 0, laces: [UInt8(t.count), 255], payload: t + Data(repeating: 1, count: 255))], as: .invalid(.mixedHeadersAndAudio))
    }

    func testCommentLengthsCountAndPadding() throws {
        let valid = tags(vendor: Data(), comments: [Data(), Data("SYNTHETIC".utf8)], padding: Data([1, 2, 255]))
        let result = try inspect([fixture()[0], page(1, flags: 0, granule: 0, laces: [UInt8(valid.count)], payload: valid), fixture()[2]])
        XCTAssertEqual(result.audioPacketCount, 1)
        for offset in [8, 12] {
            var bad = tags(vendor: Data())
            put(UInt32.max, into: &bad, at: offset)
            reject([fixture()[0], page(1, flags: 0, granule: 0, laces: [UInt8(bad.count)], payload: bad), fixture()[2]], as: .invalid(.commentLengths))
        }
        var bad = tags(vendor: Data(), comments: [Data([1])]); put(UInt32.max, into: &bad, at: 16)
        reject([fixture()[0], page(1, flags: 0, granule: 0, laces: [UInt8(bad.count)], payload: bad), fixture()[2]], as: .invalid(.commentLengths))
        bad = tags(); bad[0] = 0
        reject([fixture()[0], page(1, flags: 0, granule: 0, laces: [UInt8(bad.count)], payload: bad), fixture()[2]], as: .invalid(.commentHeader))
    }

    func testGranulesAndPCMPositionDoNotClaimDecodedDuration() throws {
        let sample = Data([1])
        reject(base() + [page(2, flags: 0, granule: 1920, laces: [1], payload: sample),
                         page(3, flags: 4, granule: 960, laces: [1], payload: sample)], as: .invalid(.granuleRegression))
        reject(base() + [page(2, flags: 4, granule: 100, laces: [1], payload: sample)], as: .invalid(.granuleBeforePreskip))
        reject(base() + [page(2, flags: 4, granule: -1, laces: [1], payload: sample)], as: .invalid(.audioGranule))
        reject(base() + [page(2, flags: 4, granule: Int64.max, laces: [1], payload: sample)], as: .unsupported(.granuleBeyondExactJSONIntegerRange))
        var wrongHeader = fixture()[0]; put(Int64(1), into: &wrongHeader, at: 6); wrongHeader = recheck(wrongHeader)
        reject([wrongHeader] + Array(fixture().dropFirst()), as: .invalid(.headerGranule))
        reject(base() + [page(2, flags: 0, granule: 0, laces: [255], payload: Data(repeating: 1, count: 255))], as: .invalid(.unfinishedPacketGranule))
        let report = try inspect(base() + [page(2, flags: 4, granule: 1272, laces: [1], payload: sample)])
        XCTAssertEqual(report.finalPCMPositionSeconds, 0.02)
        XCTAssertTrue(report.caveats.joined().contains("not measured decoded"))
        // The sample deliberately has no duration validation: accepting the container is not decoding the packet.
    }

    func testCountAndByteLimitsFailClosed() {
        let bytes = joined(fixture())
        reject(fixture(), as: .limitExceeded(.inputBytes), limits: InspectionLimits(maximumInputBytes: bytes.count - 1))
        reject(fixture(), as: .limitExceeded(.pageCount), limits: InspectionLimits(maximumPages: 2))
        reject(base() + [page(2, flags: 4, granule: 1920, laces: [1, 1], payload: Data([1, 2]))], as: .limitExceeded(.audioPacketCount), limits: InspectionLimits(maximumAudioPackets: 1))
        reject(base() + [page(2, flags: 4, granule: 1920, laces: [1, 2], payload: Data([1, 2, 3]))], as: .limitExceeded(.packetSizeHistogramBuckets), limits: InspectionLimits(maximumPacketSizeHistogramBuckets: 1))
        reject(base() + [page(2, flags: 0, granule: -1, laces: [255], payload: Data(repeating: 1, count: 255)),
                         page(3, flags: 5, granule: 960, laces: [46], payload: Data(repeating: 1, count: 46))], as: .limitExceeded(.packetBytes), limits: InspectionLimits(maximumPacketBytes: 300))
    }

    func testLargestPageAndHugeCallerChunkKeepPageBufferBounded() throws {
        let huge = page(2, flags: 0, granule: -1, laces: Array(repeating: 255, count: 255), payload: Data(repeating: 1, count: 65_025))
        XCTAssertEqual(huge.count, OggOpusInspector.maximumOggPageBytes)
        let all = joined(base() + [huge, page(3, flags: 5, granule: 960, laces: [0], payload: Data())])
        var inspector = try OggOpusInspector()
        try inspector.push(all)
        XCTAssertEqual(inspector.peakBufferedPageBytes, OggOpusInspector.maximumOggPageBytes)
        XCTAssertEqual(inspector.bufferedPageBytes, 0)
        let report = try inspector.finish()
        XCTAssertEqual(report.audioPacketPayloadBytes, 65_025)
        XCTAssertEqual(report.sizeHistogram, [PacketSizeCount(size: 65_025, count: 1)])
    }

    func testEmptyInputHeadersOnlyAndTerminalLifecycle() throws {
        reject([], as: .invalid(.missingHeadersOrAudio))
        reject(base(), as: .invalid(.missingHeadersOrAudio))
        var complete = try OggOpusInspector()
        try complete.push(joined(fixture())); _ = try complete.finish()
        XCTAssertEqual(complete.status, .finished)
        XCTAssertThrowsError(try complete.finish()) { XCTAssertEqual($0 as? OggInspectionError, .inspectorAlreadyFinished) }
        XCTAssertThrowsError(try complete.push(Data())) { XCTAssertEqual($0 as? OggInspectionError, .inspectorAlreadyFinished) }
        var failed = try OggOpusInspector()
        XCTAssertThrowsError(try failed.push(Data(repeating: 0, count: 27)))
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.bufferedPageBytes, 0)
        XCTAssertThrowsError(try failed.push(joined(fixture()))) { XCTAssertEqual($0 as? OggInspectionError, .inspectorFailed) }
        XCTAssertThrowsError(try failed.finish()) { XCTAssertEqual($0 as? OggInspectionError, .inspectorFailed) }
    }

    func testCancelledInspectionCannotResume() async throws {
        let result = try await Task { () throws -> InspectorStatus in
            var inspector = try OggOpusInspector()
            withUnsafeCurrentTask { $0?.cancel() }
            do { try inspector.push(joined(fixture())); XCTFail("must cancel") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertThrowsError(try inspector.finish()) { XCTAssertEqual($0 as? OggInspectionError, .inspectorFailed) }
            return inspector.status
        }.value
        XCTAssertEqual(result, .failed)
    }

    func testInvalidLimitsAreRejectedWithoutAllocating() {
        for limits in [InspectionLimits(maximumInputBytes: 0), InspectionLimits(maximumPacketBytes: 18),
                       InspectionLimits(maximumPages: 0), InspectionLimits(maximumAudioPackets: 0),
                       InspectionLimits(maximumPacketSizeHistogramBuckets: 0), InspectionLimits(maximumStoredSilenceIndices: -1)] {
            XCTAssertThrowsError(try OggOpusInspector(limits: limits)) { XCTAssertEqual($0 as? OggInspectionError, .invalidConfiguration) }
        }
    }

    func testEverySingleByteMutationFailsWithoutRepairingCRC() {
        let original = joined(fixture())
        for index in 0..<original.count {
            var changed = original
            changed[index] ^= 1
            XCTAssertThrowsError(try inspect([changed]), "byte \(index) must not pass")
        }
    }

    func testMonoUnknownInputRateAndSignedGainRemainMetadata() throws {
        var h = head(); h[9] = 1
        put(UInt32(0), into: &h, at: 12)
        put(Int16(-384), into: &h, at: 16)
        let report = try inspect([page(0, flags: 2, granule: 0, laces: [19], payload: h)] + Array(fixture().dropFirst()))
        XCTAssertEqual(report.opusHeader.channels, 1)
        XCTAssertEqual(report.opusHeader.inputSampleRate, 0)
        XCTAssertEqual(report.opusHeader.outputGainQ78, -384)
    }

    func testPageAndPacketHistogramsAndExactInputLimit() throws {
        let pages = base() + [
            page(2, flags: 0, granule: 2880, laces: [1, 2, 1], payload: Data([1, 2, 3, 4])),
            page(3, flags: 4, granule: 3840, laces: [2], payload: Data([5, 6]))
        ]
        let report = try inspect(pages, limits: InspectionLimits(maximumInputBytes: joined(pages).count))
        XCTAssertEqual(report.firstAudioPagePackets, 3)
        XCTAssertEqual(report.audioPacketsPerPageHistogram, [AudioPagePacketCount(packets: 1, pages: 1), AudioPagePacketCount(packets: 3, pages: 1)])
        XCTAssertEqual(report.sizeHistogram, [PacketSizeCount(size: 1, count: 2), PacketSizeCount(size: 2, count: 2)])
        XCTAssertEqual(report.audioPacketCount, 4)
        XCTAssertEqual(report.audioPacketPayloadBytes, 6)
    }
}
