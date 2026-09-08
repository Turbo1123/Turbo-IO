import XCTest
@testable import RayNeoProtocol

final class TransportFrameStreamDecoderTests: XCTestCase {
    private func frame(_ number: UInt16 = 1) throws -> TransportFrame {
        try TransportFrame(messageNumber: number, flags: 0, wireBusinessID: 0x7f, payload: Data([1, 2, 3]))
    }

    func testEveryTwoChunkSplitIncludingHeaderAndCRC() throws {
        let expected = try frame(), bytes = try expected.encoded()
        for split in 0...bytes.count {
            var decoder = try TransportFrameStreamDecoder()
            let first = try decoder.append(bytes.prefix(split))
            let second = try decoder.append(bytes.dropFirst(split))
            XCTAssertEqual(first + second, [expected])
            XCTAssertEqual(decoder.bufferedByteCount, 0)
            try decoder.finish()
            XCTAssertTrue(decoder.isFinished)
        }
    }

    func testByteAtATimeAndCoalescedFramesWithPartialTail() throws {
        let first = try frame(1), second = try frame(2), third = try frame(3)
        var decoder = try TransportFrameStreamDecoder(), result: [TransportFrame] = []
        for byte in try first.encoded() { result += try decoder.append(Data([byte])) }
        let tail = try third.encoded()
        result += try decoder.append(second.encoded() + tail.prefix(6))
        XCTAssertEqual(result, [first, second])
        XCTAssertEqual(decoder.bufferedByteCount, 6)
        XCTAssertEqual(try decoder.append(tail.dropFirst(6)), [third])
        try decoder.finish()
    }

    func testMalformedAppendLatchesFailureAndDoesNotResync() throws {
        var decoder = try TransportFrameStreamDecoder()
        let bytes = try frame().encoded()
        XCTAssertThrowsError(try decoder.append(Data([0, 0, 0, 0]) + bytes)) {
            XCTAssertEqual($0 as? TransportFrame.CodecError, .invalidHead)
        }
        XCTAssertTrue(decoder.isFailed)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
        XCTAssertThrowsError(try decoder.append(bytes)) { XCTAssertEqual($0 as? TransportFrameStreamDecoder.StreamError, .failed) }
        decoder.reset()
        XCTAssertFalse(decoder.isFailed)
        XCTAssertEqual(try decoder.append(bytes), [try frame()])
    }

    func testBadCRCAfterValidFrameRejectsWholeAppend() throws {
        var decoder = try TransportFrameStreamDecoder()
        let good = try frame().encoded()
        var bad = good; bad[bad.count - 1] ^= 1
        XCTAssertThrowsError(try decoder.append(good + bad)) { XCTAssertEqual($0 as? TransportFrame.CodecError, .crcMismatch) }
        XCTAssertTrue(decoder.isFailed)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testEOFRejectsEveryPartialFrame() throws {
        let bytes = try frame().encoded()
        for count in 1..<bytes.count {
            var decoder = try TransportFrameStreamDecoder()
            XCTAssertTrue(try decoder.append(bytes.prefix(count)).isEmpty)
            XCTAssertThrowsError(try decoder.finish()) { XCTAssertEqual($0 as? TransportFrame.CodecError, .truncated) }
            XCTAssertTrue(decoder.isFailed)
            XCTAssertEqual(decoder.bufferedByteCount, 0)
        }
    }

    func testFinishedDecoderRequiresExplicitReset() throws {
        var decoder = try TransportFrameStreamDecoder()
        try decoder.finish()
        XCTAssertThrowsError(try decoder.append(Data())) { XCTAssertEqual($0 as? TransportFrameStreamDecoder.StreamError, .finished) }
        XCTAssertThrowsError(try decoder.finish())
        decoder.reset()
        XCTAssertFalse(decoder.isFinished)
        XCTAssertEqual(try decoder.append(frame().encoded()), [try frame()])
    }

    func testBufferLimitIncludesPreviouslyBufferedBytes() throws {
        let limits = try TransportFrame.Limits(maxFrameBytes: 64, maxPayloadBytes: 54)
        var decoder = try TransportFrameStreamDecoder(limits: limits, maxBufferedBytes: 64)
        XCTAssertTrue(try decoder.append(Data([0xaa, 0x55, 0, 58])).isEmpty)
        XCTAssertThrowsError(try decoder.append(Data(repeating: 0, count: 61))) {
            XCTAssertEqual($0 as? TransportFrameStreamDecoder.StreamError, .bufferLimitExceeded)
        }
        XCTAssertTrue(decoder.isFailed)
        XCTAssertEqual(decoder.bufferedByteCount, 0)
    }

    func testFrameCountLimitAndInvalidLimits() throws {
        var decoder = try TransportFrameStreamDecoder(maxFramesPerAppend: 1)
        let bytes = try frame().encoded()
        XCTAssertThrowsError(try decoder.append(bytes + bytes)) { XCTAssertEqual($0 as? TransportFrameStreamDecoder.StreamError, .tooManyFrames) }
        XCTAssertThrowsError(try TransportFrameStreamDecoder(maxBufferedBytes: 100))
        XCTAssertThrowsError(try TransportFrameStreamDecoder(maxBufferedBytes: 1_048_577))
        XCTAssertThrowsError(try TransportFrameStreamDecoder(maxFramesPerAppend: 0))
        XCTAssertThrowsError(try TransportFrameStreamDecoder(maxFramesPerAppend: 1025))
    }

    func testOversizeDeclaredFrameFailsBeforeWaitingForPayload() throws {
        let limits = try TransportFrame.Limits(maxFrameBytes: 64, maxPayloadBytes: 54)
        var decoder = try TransportFrameStreamDecoder(limits: limits)
        XCTAssertThrowsError(try decoder.append(Data([0xaa, 0x55, 0xff, 0xff]))) {
            XCTAssertEqual($0 as? TransportFrame.CodecError, .frameTooLarge)
        }
        XCTAssertTrue(decoder.isFailed)
    }

    func testContinuousUntrustedInputCannotAccumulateAfterFailure() throws {
        var decoder = try TransportFrameStreamDecoder()
        for _ in 0..<3 { XCTAssertTrue(try decoder.append(Data([0])).isEmpty) }
        XCTAssertThrowsError(try decoder.append(Data([0])))
        for _ in 0..<1024 {
            XCTAssertThrowsError(try decoder.append(Data(repeating: 0xaa, count: 1024))) {
                XCTAssertEqual($0 as? TransportFrameStreamDecoder.StreamError, .failed)
            }
            XCTAssertEqual(decoder.bufferedByteCount, 0)
        }
    }

    func testMaximumDeclaredFrameAsManyChunksRemainsBounded() throws {
        let expected = try TransportFrame(messageNumber: 7, flags: 0,
                                          sliceMetadata: .init(opaqueBytes: Data(repeating: 0xa5, count: 7)),
                                          wireBusinessID: 0xee, payload: Data(repeating: 0xaa, count: 65_524))
        let encoded = try expected.encoded()
        var decoder = try TransportFrameStreamDecoder(maxBufferedBytes: 65_541)
        var received: [TransportFrame] = []
        for start in stride(from: 0, to: encoded.count, by: 1024) {
            received += try decoder.append(encoded.subdata(in: start..<min(start + 1024, encoded.count)))
            XCTAssertLessThanOrEqual(decoder.bufferedByteCount, 65_541)
        }
        XCTAssertEqual(received, [expected])
        XCTAssertEqual(decoder.bufferedByteCount, 0)
        try decoder.finish()
    }
}
