import Foundation

public enum TextOffsetLimitError: Error, Equatable, Sendable {
    case invalidLimits
    case inputTooLarge
    case tooManyBoundaries
}

/// Local memory/work limits, not a maximum manuscript size promised by glasses.
public struct TextOffsetLimits: Equatable, Sendable {
    public let maxInputUTF8Bytes: Int
    /// Includes the initial zero boundary. Character boundaries cannot outnumber
    /// scalar boundaries, so this also bounds both Character-index arrays.
    public let maxScalarBoundaries: Int

    public static let conservative = TextOffsetLimits(
        uncheckedBytes: 262_144, scalarBoundaries: 65_537
    )

    public init(maxInputUTF8Bytes: Int, maxScalarBoundaries: Int) throws {
        guard maxInputUTF8Bytes > 0, maxScalarBoundaries > 0 else {
            throw TextOffsetLimitError.invalidLimits
        }
        self.init(uncheckedBytes: maxInputUTF8Bytes, scalarBoundaries: maxScalarBoundaries)
    }

    private init(uncheckedBytes: Int, scalarBoundaries: Int) {
        maxInputUTF8Bytes = uncheckedBytes
        maxScalarBoundaries = scalarBoundaries
    }
}

/// A text coordinate conversion, not a font shaper or a glasses pixel layout.
public struct TextOffsetMap: Sendable {
    public enum NewlinePolicy: Sendable {
        /// Retain every byte. Use this for offsets into an already prepared file.
        case preserve
        /// Explicitly prepare CRLF and CR as LF, as the inspected iOS mapper does.
        case normalizeToLF
    }

    public enum Boundary: Sendable {
        /// Unicode scalar boundaries. A combining mark may be a separate scalar.
        case unicodeScalar
        /// Swift Character / extended grapheme boundaries, useful for editing UI.
        case character
    }

    public enum OffsetError: Error, Equatable, Sendable {
        case outOfBounds
        case insideUTF16SurrogatePair
        case insideUTF8Scalar
        case insideCharacter
    }

    /// All offsets refer to this string, after the explicitly selected policy.
    public let text: String
    public let utf16Count: Int
    public let utf8Count: Int
    public let scalarUTF16Boundaries: [Int]
    public let scalarUTF8Boundaries: [Int]
    public let characterUTF16Boundaries: [Int]
    public let characterUTF8Boundaries: [Int]
    private let utf16ToUTF8: [Int: Int]
    private let utf8ToUTF16: [Int: Int]
    private let characterUTF16Set: Set<Int>
    private let characterUTF8Set: Set<Int>

    public init(_ input: String, newlinePolicy: NewlinePolicy = .preserve,
                limits: TextOffsetLimits = .conservative) throws {
        // Do this before newline replacement or any index-table allocation.
        guard input.utf8.count <= limits.maxInputUTF8Bytes else {
            throw TextOffsetLimitError.inputTooLarge
        }
        switch newlinePolicy {
        case .preserve: text = input
        case .normalizeToLF:
            text = input.replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
        }
        var boundaryCount = 1
        for _ in text.unicodeScalars {
            guard boundaryCount < limits.maxScalarBoundaries else {
                throw TextOffsetLimitError.tooManyBoundaries
            }
            boundaryCount += 1
        }
        var units = 0
        var bytes = 0
        var unitBoundaries = [0]
        var byteBoundaries = [0]
        var forward = [0: 0]
        var backward = [0: 0]
        for scalar in text.unicodeScalars {
            units += scalar.value > 0xFFFF ? 2 : 1
            switch scalar.value {
            case 0...0x7F: bytes += 1
            case 0x80...0x7FF: bytes += 2
            case 0x800...0xFFFF: bytes += 3
            default: bytes += 4
            }
            unitBoundaries.append(units)
            byteBoundaries.append(bytes)
            forward[units] = bytes
            backward[bytes] = units
        }
        utf16Count = units
        utf8Count = bytes
        scalarUTF16Boundaries = unitBoundaries
        scalarUTF8Boundaries = byteBoundaries
        utf16ToUTF8 = forward
        utf8ToUTF16 = backward

        var characterUnits = [0]
        var characterBytes = [0]
        units = 0
        bytes = 0
        for character in text {
            units += character.utf16.count
            bytes += character.utf8.count
            characterUnits.append(units)
            characterBytes.append(bytes)
        }
        characterUTF16Boundaries = characterUnits
        characterUTF8Boundaries = characterBytes
        characterUTF16Set = Set(characterUnits)
        characterUTF8Set = Set(characterBytes)
    }

    /// Rejects a UTF-16 position between the two halves of a surrogate pair.
    /// Deliberately does not copy the official mapper's ambiguous interior entry.
    public func utf8Offset(forUTF16Offset offset: Int,
                           boundary: Boundary = .unicodeScalar) throws -> Int {
        guard (0...utf16Count).contains(offset) else { throw OffsetError.outOfBounds }
        guard let result = utf16ToUTF8[offset] else {
            throw OffsetError.insideUTF16SurrogatePair
        }
        if boundary == .character && !characterUTF16Set.contains(offset) {
            throw OffsetError.insideCharacter
        }
        return result
    }

    /// Rejects a byte position inside a multibyte UTF-8 scalar; never rounds.
    public func utf16Offset(forUTF8Offset offset: Int,
                            boundary: Boundary = .unicodeScalar) throws -> Int {
        guard (0...utf8Count).contains(offset) else { throw OffsetError.outOfBounds }
        guard let result = utf8ToUTF16[offset] else { throw OffsetError.insideUTF8Scalar }
        if boundary == .character && !characterUTF8Set.contains(offset) {
            throw OffsetError.insideCharacter
        }
        return result
    }

    public func utf8Range(forUTF16Range range: Range<Int>,
                          boundary: Boundary = .unicodeScalar) throws -> Range<Int> {
        let start = try utf8Offset(forUTF16Offset: range.lowerBound, boundary: boundary)
        let end = try utf8Offset(forUTF16Offset: range.upperBound, boundary: boundary)
        return start..<end
    }

    public func utf16Range(forUTF8Range range: Range<Int>,
                           boundary: Boundary = .unicodeScalar) throws -> Range<Int> {
        let start = try utf16Offset(forUTF8Offset: range.lowerBound, boundary: boundary)
        let end = try utf16Offset(forUTF8Offset: range.upperBound, boundary: boundary)
        return start..<end
    }
}
