import Foundation

/// Missing and JSON null are distinct observations, even when an official
/// handler later gives them the same default. This type does not persist data.
public enum FieldPresence<Value: Equatable & Sendable>: Equatable, Sendable {
    case missing
    case null
    case value(Value)

    public var value: Value? {
        if case .value(let value) = self { return value }
        return nil
    }
}

public enum DisplayPayloadError: Error, Equatable, Sendable {
    case invalidLimits
    case payloadTooLarge
    case excessiveNesting
    case excessiveCollection
    case stringTooLong
    case invalidJSON
    case duplicateKey
    case expectedObject
    case missingField(String)
    case wrongType(String)
    case integerRequired(String)
    case integerOutOfRange(String)
    case unexpectedField(String)
    case wrongAction
    case emptyIdentifier(String)
    case unknownCommand(Int64)
}

/// Local resource limits, NOT discovered firmware limits. The codec checks both
/// inbound and outbound payloads. Callers can select stricter limits explicitly.
public struct DisplayPayloadLimits: Equatable, Sendable {
    public let maxPayloadBytes: Int
    public let maxNestingDepth: Int
    public let maxCollectionElements: Int
    public let maxStringBytes: Int

    public static let conservative = DisplayPayloadLimits(
        uncheckedPayloadBytes: 65_536, nestingDepth: 16,
        collectionElements: 1_024, stringBytes: 16_384
    )

    public init(maxPayloadBytes: Int, maxNestingDepth: Int = 16,
                maxCollectionElements: Int = 1_024, maxStringBytes: Int = 16_384) throws {
        guard maxPayloadBytes > 0, maxNestingDepth > 0, maxNestingDepth <= 128,
              maxCollectionElements > 0, maxStringBytes > 0 else {
            throw DisplayPayloadError.invalidLimits
        }
        self.init(uncheckedPayloadBytes: maxPayloadBytes, nestingDepth: maxNestingDepth,
                  collectionElements: maxCollectionElements, stringBytes: maxStringBytes)
    }

    private init(uncheckedPayloadBytes: Int, nestingDepth: Int,
                 collectionElements: Int, stringBytes: Int) {
        maxPayloadBytes = uncheckedPayloadBytes
        maxNestingDepth = nestingDepth
        maxCollectionElements = collectionElements
        maxStringBytes = stringBytes
    }

    func checkSize(_ data: Data) throws {
        guard data.count <= maxPayloadBytes else { throw DisplayPayloadError.payloadTooLarge }
    }
}

/// A business-local type and its JSON, not a transport packet or a send result.
/// The caller must choose an evidence-backed business route separately.
public struct DisplayJSONMessage: Equatable, Sendable {
    public let type: UInt16
    public let payload: Data

    public init(type: UInt16, payload: Data) {
        self.type = type
        self.payload = payload
    }
}

indirect enum StrictJSONValue {
    case object([String: StrictJSONValue])
    case array([StrictJSONValue])
    case string(String)
    /// Preserving the token makes `1`, `1.0`, `1e0`, true, and large integers
    /// distinguishable. Foundation's NSNumber coercions must not decide a cmd.
    case number(String)
    case bool(Bool)
    case null
}

struct StrictJSONParser {
    private let bytes: [UInt8]
    private let limits: DisplayPayloadLimits
    private var position = 0

    init(data: Data, limits: DisplayPayloadLimits) throws {
        try limits.checkSize(data)
        guard String(data: data, encoding: .utf8) != nil else {
            throw DisplayPayloadError.invalidJSON
        }
        bytes = Array(data)
        self.limits = limits
    }

    mutating func parse() throws -> StrictJSONValue {
        let result = try value(depth: 0)
        skipWhitespace()
        guard position == bytes.count else { throw DisplayPayloadError.invalidJSON }
        return result
    }

    private mutating func value(depth: Int) throws -> StrictJSONValue {
        guard depth < limits.maxNestingDepth else { throw DisplayPayloadError.excessiveNesting }
        skipWhitespace()
        guard position < bytes.count else { throw DisplayPayloadError.invalidJSON }
        switch bytes[position] {
        case 0x7B: return try object(depth: depth)
        case 0x5B: return try array(depth: depth)
        case 0x22: return .string(try string())
        case 0x74: try literal("true"); return .bool(true)
        case 0x66: try literal("false"); return .bool(false)
        case 0x6E: try literal("null"); return .null
        case 0x2D, 0x30...0x39: return .number(try number())
        default: throw DisplayPayloadError.invalidJSON
        }
    }

    private mutating func object(depth: Int) throws -> StrictJSONValue {
        position += 1
        skipWhitespace()
        var result: [String: StrictJSONValue] = [:]
        if consume(0x7D) { return .object(result) }
        while true {
            guard result.count < limits.maxCollectionElements else {
                throw DisplayPayloadError.excessiveCollection
            }
            skipWhitespace()
            guard position < bytes.count, bytes[position] == 0x22 else {
                throw DisplayPayloadError.invalidJSON
            }
            let key = try string()
            guard result[key] == nil else { throw DisplayPayloadError.duplicateKey }
            skipWhitespace()
            guard consume(0x3A) else { throw DisplayPayloadError.invalidJSON }
            result[key] = try value(depth: depth + 1)
            skipWhitespace()
            if consume(0x7D) { return .object(result) }
            guard consume(0x2C) else { throw DisplayPayloadError.invalidJSON }
        }
    }

    private mutating func array(depth: Int) throws -> StrictJSONValue {
        position += 1
        skipWhitespace()
        var result: [StrictJSONValue] = []
        if consume(0x5D) { return .array(result) }
        while true {
            guard result.count < limits.maxCollectionElements else {
                throw DisplayPayloadError.excessiveCollection
            }
            result.append(try value(depth: depth + 1))
            skipWhitespace()
            if consume(0x5D) { return .array(result) }
            guard consume(0x2C) else { throw DisplayPayloadError.invalidJSON }
        }
    }

    private mutating func string() throws -> String {
        let start = position
        position += 1
        while position < bytes.count {
            let byte = bytes[position]
            if byte == 0x22 {
                position += 1
                guard position - start - 2 <= limits.maxStringBytes else {
                    throw DisplayPayloadError.stringTooLong
                }
                let fragment = Data(bytes[start..<position])
                guard let decoded = try? JSONDecoder().decode(String.self, from: fragment) else {
                    throw DisplayPayloadError.invalidJSON
                }
                guard decoded.utf8.count <= limits.maxStringBytes else {
                    throw DisplayPayloadError.stringTooLong
                }
                return decoded
            }
            guard byte >= 0x20 else { throw DisplayPayloadError.invalidJSON }
            if byte == 0x5C {
                position += 1
                guard position < bytes.count else { throw DisplayPayloadError.invalidJSON }
            }
            position += 1
            guard position - start - 1 <= limits.maxStringBytes else {
                throw DisplayPayloadError.stringTooLong
            }
        }
        throw DisplayPayloadError.invalidJSON
    }

    private mutating func number() throws -> String {
        let start = position
        _ = consume(0x2D)
        guard position < bytes.count else { throw DisplayPayloadError.invalidJSON }
        if consume(0x30) {
            if isDigit() { throw DisplayPayloadError.invalidJSON }
        } else {
            guard position < bytes.count, (0x31...0x39).contains(bytes[position]) else {
                throw DisplayPayloadError.invalidJSON
            }
            while isDigit() { position += 1 }
        }
        if consume(0x2E) {
            guard isDigit() else { throw DisplayPayloadError.invalidJSON }
            while isDigit() { position += 1 }
        }
        if position < bytes.count, bytes[position] == 0x65 || bytes[position] == 0x45 {
            position += 1
            if !consume(0x2B) { _ = consume(0x2D) }
            guard isDigit() else { throw DisplayPayloadError.invalidJSON }
            while isDigit() { position += 1 }
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    private func isDigit() -> Bool {
        position < bytes.count && (0x30...0x39).contains(bytes[position])
    }

    private mutating func literal(_ text: String) throws {
        for byte in text.utf8 {
            guard consume(byte) else { throw DisplayPayloadError.invalidJSON }
        }
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard position < bytes.count, bytes[position] == byte else { return false }
        position += 1
        return true
    }

    private mutating func skipWhitespace() {
        while position < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[position]) {
            position += 1
        }
    }
}

struct JSONObject {
    let fields: [String: StrictJSONValue]

    init(_ value: StrictJSONValue) throws {
        guard case .object(let fields) = value else { throw DisplayPayloadError.expectedObject }
        self.fields = fields
    }

    init(data: Data, limits: DisplayPayloadLimits) throws {
        var parser = try StrictJSONParser(data: data, limits: limits)
        try self.init(parser.parse())
    }

    func requireOnly(_ allowed: Set<String>) throws {
        if let extra = Set(fields.keys).subtracting(allowed).sorted().first {
            throw DisplayPayloadError.unexpectedField(extra)
        }
    }

    func int(_ key: String) throws -> Int64 {
        guard let value = fields[key] else { throw DisplayPayloadError.missingField(key) }
        return try Self.integer(value, key: key)
    }

    static func integer(_ value: StrictJSONValue, key: String) throws -> Int64 {
        guard case .number(let raw) = value else { throw DisplayPayloadError.wrongType(key) }
        guard !raw.contains("."), !raw.contains("e"), !raw.contains("E") else {
            throw DisplayPayloadError.integerRequired(key)
        }
        guard let number = Int64(raw) else { throw DisplayPayloadError.integerOutOfRange(key) }
        return number
    }

    func optionalInt(_ key: String) throws -> FieldPresence<Int64> {
        guard let value = fields[key] else { return .missing }
        if case .null = value { return .null }
        return .value(try Self.integer(value, key: key))
    }

    func optionalBool(_ key: String) throws -> FieldPresence<Bool> {
        guard let value = fields[key] else { return .missing }
        if case .null = value { return .null }
        guard case .bool(let bool) = value else { throw DisplayPayloadError.wrongType(key) }
        return .value(bool)
    }

    func identifier(_ key: String) throws -> String {
        guard let value = fields[key] else { throw DisplayPayloadError.missingField(key) }
        guard case .string(let string) = value else { throw DisplayPayloadError.wrongType(key) }
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DisplayPayloadError.emptyIdentifier(key)
        }
        return string
    }
}

/// Only for constructing a known schema. Decode again before returning so the
/// same size, nesting, duplicate-key and string limits govern outbound JSON.
func encodeJSON(_ value: [String: Any], limits: DisplayPayloadLimits) throws -> Data {
    // All currently supported outbound models are flat. Bound their strings and
    // aggregate unescaped size BEFORE asking Foundation to allocate encoded Data.
    guard value.count <= limits.maxCollectionElements else {
        throw DisplayPayloadError.excessiveCollection
    }
    var minimumSize = 2
    var isFirst = true
    for (key, item) in value {
        guard key.utf8.count <= limits.maxStringBytes else { throw DisplayPayloadError.stringTooLong }
        let itemSize: Int
        if let string = item as? String {
            guard string.utf8.count <= limits.maxStringBytes else { throw DisplayPayloadError.stringTooLong }
            itemSize = string.utf8.count
        } else {
            // Numeric and boolean values here are known, bounded scalar types.
            guard item is Int || item is Int64 || item is Bool || item is NSNull else {
                throw DisplayPayloadError.invalidJSON
            }
            itemSize = 1
        }
        let quotes = item is String ? 2 : 0
        for size in [key.utf8.count, itemSize, 3, quotes, isFirst ? 0 : 1] {
            guard size <= limits.maxPayloadBytes,
                  minimumSize <= limits.maxPayloadBytes - size else {
                throw DisplayPayloadError.payloadTooLarge
            }
            minimumSize += size
        }
        isFirst = false
    }
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    _ = try JSONObject(data: data, limits: limits)
    return data
}

func validateIdentifier(_ value: String, key: String,
                         limits: DisplayPayloadLimits = .conservative) throws {
    guard value.utf8.count <= limits.maxStringBytes else { throw DisplayPayloadError.stringTooLong }
    guard value.utf8.count <= limits.maxPayloadBytes else { throw DisplayPayloadError.payloadTooLarge }
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw DisplayPayloadError.emptyIdentifier(key)
    }
}
