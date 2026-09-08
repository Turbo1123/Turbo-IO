import Foundation

/// Pure, version-pinned iOS version-exchange TLV codec. No transport, persistence or handshake state.
/// Sources: IOS_PAIRING_PREFLIGHT_20260907.md and IOS_PEER_AUTH_INPUTS_20260907.md.
public enum IOSVersionExchange {
    public static let wireBusinessID: UInt8 = 0x10
    public static let outerTag: UInt8 = 0x11

    /// Errors contain only field tags/categories, never identifiers, names or peer bytes.
    public enum CodecError: Error, Equatable {
        case invalidLimits, invalidIdentifierLength, payloadTooLarge, tooManyFields
        case emptyText(tag: UInt8), fieldTooLarge(tag: UInt8)
        case wrongBusinessID, opaqueSliceMetadata, invalidOuterTag, invalidOuterLength
        case truncatedField, duplicateKnownField(tag: UInt8), invalidUTF8(tag: UInt8)
    }

    /// Local memory/work limits, not measured firmware or MTU capabilities.
    public struct Limits: Equatable, Sendable {
        public let maxPayloadBytes: Int
        public let maxFieldBytes: Int
        public let maxFields: Int

        /// Payload includes the three-byte outer TLV header; field limits apply to inner values.
        public init(maxPayloadBytes: Int = 4_096, maxFieldBytes: Int = 1_024,
                    maxFields: Int = 32) throws {
            guard (3...65_524).contains(maxPayloadBytes), (0...65_521).contains(maxFieldBytes),
                  (0...256).contains(maxFields) else { throw CodecError.invalidLimits }
            self.maxPayloadBytes = maxPayloadBytes
            self.maxFieldBytes = maxFieldBytes
            self.maxFields = maxFields
        }

        private init() { maxPayloadBytes = 4_096; maxFieldBytes = 1_024; maxFields = 32 }
        public static let standard = Limits()
    }

    /// Observed tag 0x1b values. Selecting a value does not create or prove a binding.
    public enum BondRelationValue: UInt8, Equatable, Sendable {
        case otherOrUnavailable = 0x01
        case mutual = 0x02
    }

    /// Caller must select the observed model policy; no guessing from a display name.
    public enum ModelPolicy: Equatable, Sendable {
        case includeBondTag(BondRelationValue)
        /// Official RNModelType.V4 (internal index 5) omits 0x1b.
        case omitForV4
    }

    public struct Request: Equatable, Sendable {
        /// Caller-owned protocol identity, not a hardware MAC or an identity read from the official app.
        public let phoneProtocolIdentifier: Data
        public let phoneName: String
        /// Resolved DeviceList.deviceName or modelIdentifier fallback, supplied by the caller.
        public let phoneModelName: String
        public let modelPolicy: ModelPolicy

        /// Local strict policy: six identity bytes and nonempty names. No trim/Unicode normalization.
        /// Six bytes matches the normal official identity path, not every possible overridden cache.
        public init(phoneProtocolIdentifier: Data, phoneName: String, phoneModelName: String,
                    modelPolicy: ModelPolicy, limits: Limits = .standard) throws {
            try Self.validate(phoneProtocolIdentifier, phoneName, phoneModelName, modelPolicy, limits)
            self.phoneProtocolIdentifier = phoneProtocolIdentifier
            self.phoneName = phoneName
            self.phoneModelName = phoneModelName
            self.modelPolicy = modelPolicy
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.phoneProtocolIdentifier == rhs.phoneProtocolIdentifier &&
            lhs.phoneName.utf8.elementsEqual(rhs.phoneName.utf8) &&
            lhs.phoneModelName.utf8.elementsEqual(rhs.phoneModelName.utf8) &&
            lhs.modelPolicy == rhs.modelPolicy
        }

        /// Exactly one outer TLV, with six or seven inner TLVs in verified outbound order.
        public func encodedPayload(limits: Limits = .standard) throws -> Data {
            try Self.validate(phoneProtocolIdentifier, phoneName, phoneModelName, modelPolicy, limits)
            var fields = [
                TLV(tag: 0x10, value: Data([0x01])),
                TLV(tag: 0x11, value: phoneProtocolIdentifier),
                TLV(tag: 0x12, value: Data(phoneName.utf8)),
                TLV(tag: 0x13, value: Data([0x01])),
                TLV(tag: 0x16, value: Data("iPhone".utf8)),
                TLV(tag: 0x17, value: Data(phoneModelName.utf8))
            ]
            if case let .includeBondTag(relation) = modelPolicy {
                fields.append(TLV(tag: 0x1b, value: Data([relation.rawValue])))
            }
            var inner = Data()
            for field in fields { inner.append(try field.encoded()) }
            return try TLV(tag: IOSVersionExchange.outerTag, value: inner).encoded()
        }

        /// No sequence allocator, fragmentation or send side effect. Raw flags are explicitly caller supplied.
        public func transportFrame(messageNumber: UInt16, flags: UInt8, address: UInt8? = nil,
                                   limits: Limits = .standard,
                                   frameLimits: TransportFrame.Limits = .standard) throws -> TransportFrame {
            try TransportFrame(messageNumber: messageNumber, flags: flags, address: address,
                               wireBusinessID: IOSVersionExchange.wireBusinessID,
                               payload: encodedPayload(limits: limits), limits: frameLimits)
        }

        private static func validate(_ identifier: Data, _ name: String, _ model: String,
                                     _ policy: ModelPolicy, _ limits: Limits) throws {
            guard identifier.count == 6 else { throw CodecError.invalidIdentifierLength }
            // Measure before Data construction. Bounded prefix also avoids scanning an unbounded String.
            let nameCount = try textCount(name, tag: 0x12, maximum: limits.maxFieldBytes)
            let modelCount = try textCount(model, tag: 0x17, maximum: limits.maxFieldBytes)
            guard limits.maxFieldBytes >= 6 else { throw CodecError.fieldTooLarge(tag: 0x11) }
            let count: Int
            if case .includeBondTag = policy { count = 7 } else { count = 6 }
            guard count <= limits.maxFields else { throw CodecError.tooManyFields }
            // All lengths above are bounded by 65521. The remaining values total 14 or 15 bytes.
            let valueBytes = 14 + nameCount + modelCount + (count == 7 ? 1 : 0)
            guard 3 + count * 3 + valueBytes <= limits.maxPayloadBytes else {
                throw CodecError.payloadTooLarge
            }
        }

        private static func textCount(_ text: String, tag: UInt8, maximum: Int) throws -> Int {
            let count = text.utf8.prefix(maximum + 1).count
            guard count > 0 else { throw CodecError.emptyText(tag: tag) }
            guard count <= maximum else { throw CodecError.fieldTooLarge(tag: tag) }
            return count
        }
    }

    public struct Field: Equatable, Sendable {
        public let tag: UInt8
        public let value: Data
        fileprivate init(_ field: TLV) { tag = field.tag; value = field.value }
    }

    /// Only tags with directly observed receive-side handling. 0x11/0x19 remain uninterpreted bytes.
    public enum ObservedResponseTag: UInt8, Sendable {
        case opaque11 = 0x11
        case serialNumber = 0x14
        case mfiSerialNumber = 0x18
        case opaque19 = 0x19
    }

    /// A syntactically decoded container, NOT version compatibility, peer authentication or pairing success.
    public struct Response: Equatable, Sendable {
        /// Original order and bytes, including unknown tags and repeated unknown tags.
        public let fields: [Field]
        fileprivate init(fields: [Field]) { self.fields = fields }

        /// nil means absent; Data() means present with an empty value. There is no TLV null type.
        public func value(for tag: ObservedResponseTag) -> Data? {
            fields.first { $0.tag == tag.rawValue }?.value
        }

        /// UTF-8 was validated when decoding. Empty text stays empty, not missing.
        public var serialNumber: String? {
            value(for: .serialNumber).flatMap { String(data: $0, encoding: .utf8) }
        }
        public var mfiSerialNumber: String? {
            value(for: .mfiSerialNumber).flatMap { String(data: $0, encoding: .utf8) }
        }
        public var unknownFields: [Field] {
            fields.filter { ObservedResponseTag(rawValue: $0.tag) == nil }
        }
    }

    /// Direction-specific response decoding. No required inner fields are invented.
    /// Local policy rejects duplicates of observed singular tags and invalid known UTF-8;
    /// unknown fields remain raw and may repeat. No implicit progress to authentication.
    public static func decodeResponse(wireBusinessID: UInt8, payload: Data,
                                      limits: Limits = .standard) throws -> Response {
        guard wireBusinessID == Self.wireBusinessID else { throw CodecError.wrongBusinessID }
        guard payload.count <= limits.maxPayloadBytes else { throw CodecError.payloadTooLarge }
        // Prescan all resource, header and field constraints BEFORE TLV.decode allocates arrays/copies.
        try payload.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard bytes.count >= 3 else { throw CodecError.invalidOuterLength }
            guard bytes[0] == outerTag else { throw CodecError.invalidOuterTag }
            let declared = Int(bytes[1]) << 8 | Int(bytes[2])
            guard declared == bytes.count - 3 else { throw CodecError.invalidOuterLength }
            var offset = 3, count = 0
            var observed = Set<UInt8>()
            while offset < bytes.count {
                guard count < limits.maxFields else { throw CodecError.tooManyFields }
                count += 1
                guard bytes.count - offset >= 3 else { throw CodecError.truncatedField }
                let tag = bytes[offset]
                let length = Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2])
                offset += 3
                guard length <= limits.maxFieldBytes else { throw CodecError.fieldTooLarge(tag: tag) }
                guard length <= bytes.count - offset else { throw CodecError.truncatedField }
                if let known = ObservedResponseTag(rawValue: tag) {
                    guard observed.insert(tag).inserted else { throw CodecError.duplicateKnownField(tag: tag) }
                    if known == .serialNumber || known == .mfiSerialNumber {
                        guard String(bytes: bytes[offset..<(offset + length)], encoding: .utf8) != nil else {
                            throw CodecError.invalidUTF8(tag: tag)
                        }
                    }
                }
                offset += length
            }
        }
        // The outer header has already been strictly validated; reuse the shared inner TLV codec.
        return Response(fields: try TLV.decode(Data(payload.dropFirst(3))).map(Field.init))
    }

    /// Caller must have a complete frame. Opaque slice information is not silently treated as reassembly.
    public static func decodeResponse(from frame: TransportFrame,
                                      limits: Limits = .standard) throws -> Response {
        guard frame.sliceMetadata.opaqueBytes.isEmpty else { throw CodecError.opaqueSliceMetadata }
        return try decodeResponse(wireBusinessID: frame.wireBusinessID, payload: frame.payload, limits: limits)
    }
}
