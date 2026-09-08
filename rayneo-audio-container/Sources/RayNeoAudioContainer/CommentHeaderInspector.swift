/// Tracks only lengths and the fixed signature. Vendor/comment/padding bytes are consumed, never retained.
struct CommentHeaderInspector: Sendable {
    private enum State: Sendable {
        case signature(Int)
        case vendorLength(Int, UInt32)
        case vendorBytes(UInt32)
        case commentCount(Int, UInt32)
        case commentLength(comments: UInt32, bytes: Int, value: UInt32)
        case commentBytes(comments: UInt32, bytes: UInt32)
        case padding
    }
    private var state = State.signature(0)
    private static let signature = Array("OpusTags".utf8)

    mutating func consume(_ byte: UInt8) throws {
        switch state {
        case .signature(let at):
            guard byte == Self.signature[at] else { throw OggInspectionError.invalid(.commentHeader) }
            state = at == 7 ? .vendorLength(0, 0) : .signature(at + 1)
        case .vendorLength(let at, let value):
            let value = value | (UInt32(byte) << (at * 8))
            state = at == 3 ? (value == 0 ? .commentCount(0, 0) : .vendorBytes(value)) : .vendorLength(at + 1, value)
        case .vendorBytes(let remaining):
            state = remaining == 1 ? .commentCount(0, 0) : .vendorBytes(remaining - 1)
        case .commentCount(let at, let value):
            let value = value | (UInt32(byte) << (at * 8))
            state = at == 3 ? (value == 0 ? .padding : .commentLength(comments: value, bytes: 0, value: 0)) : .commentCount(at + 1, value)
        case .commentLength(let comments, let at, let value):
            let value = value | (UInt32(byte) << (at * 8))
            if at == 3 {
                state = value == 0 ? nextComment(after: comments) : .commentBytes(comments: comments, bytes: value)
            } else {
                state = .commentLength(comments: comments, bytes: at + 1, value: value)
            }
        case .commentBytes(let comments, let bytes):
            state = bytes == 1 ? nextComment(after: comments) : .commentBytes(comments: comments, bytes: bytes - 1)
        case .padding:
            break // Optional trailing padding is allowed; no text decoding or content storage.
        }
    }

    private func nextComment(after count: UInt32) -> State {
        count == 1 ? .padding : .commentLength(comments: count - 1, bytes: 0, value: 0)
    }

    func finish() throws {
        guard case .padding = state else { throw OggInspectionError.invalid(.commentLengths) }
    }
}
