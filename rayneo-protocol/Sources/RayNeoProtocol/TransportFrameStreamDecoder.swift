import Foundation

/// Bounded chunk/concatenation decoder. No magic-header scanning, recovery, ACKs or reassembly.
/// Own one instance per physical connection, and call reset only after deliberate recovery.
public struct TransportFrameStreamDecoder: Sendable {
    public enum StreamError: Error, Equatable {
        case invalidLimits, bufferLimitExceeded, tooManyFrames, failed, finished
    }

    public let limits: TransportFrame.Limits
    public let maxBufferedBytes: Int
    public let maxFramesPerAppend: Int
    private var buffer = Data()
    public private(set) var isFailed = false
    public private(set) var isFinished = false
    public var bufferedByteCount: Int { buffer.count }

    /// Hard allocation policy: at most 1 MiB buffered and 1024 output frames per append.
    public init(limits: TransportFrame.Limits = .standard, maxBufferedBytes: Int = 131_082,
                maxFramesPerAppend: Int = 256) throws {
        guard (limits.maxFrameBytes...1_048_576).contains(maxBufferedBytes),
              (1...1024).contains(maxFramesPerAppend) else { throw StreamError.invalidLimits }
        self.limits = limits
        self.maxBufferedBytes = maxBufferedBytes
        self.maxFramesPerAppend = maxFramesPerAppend
    }

    /// A failing append returns no frames from that append, clears buffered bytes and latches failure.
    /// Earlier successful appends cannot be retracted. CRC is not authentication; gate dispatch separately.
    public mutating func append(_ chunk: Data) throws -> [TransportFrame] {
        guard !isFailed else { throw StreamError.failed }
        guard !isFinished else { throw StreamError.finished }
        do {
            guard chunk.count <= maxBufferedBytes - buffer.count else { throw StreamError.bufferLimitExceeded }
            buffer.append(chunk)
            var result: [TransportFrame] = []
            while buffer.count >= 4 {
                let count = try TransportFrame.declaredByteCount(buffer, limits: limits)
                guard buffer.count >= count else { break }
                guard result.count < maxFramesPerAppend else { throw StreamError.tooManyFrames }
                result.append(try TransportFrame.decode(Data(buffer.prefix(count)), limits: limits))
                buffer.removeFirst(count)
            }
            return result
        } catch {
            buffer.removeAll(keepingCapacity: false)
            isFailed = true
            throw error
        }
    }

    /// Marks EOF. An unfinished frame is an error, not a silently ignored tail.
    public mutating func finish() throws {
        guard !isFailed else { throw StreamError.failed }
        guard !isFinished else { throw StreamError.finished }
        guard buffer.isEmpty else {
            buffer.removeAll(keepingCapacity: false)
            isFailed = true
            throw TransportFrame.CodecError.truncated
        }
        isFinished = true
    }

    public mutating func reset() {
        buffer.removeAll(keepingCapacity: false)
        isFailed = false
        isFinished = false
    }
}
