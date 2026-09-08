import Foundation

/// Opaque text identity by exact UTF-8 bytes, with no Unicode normalization.
/// Swift String equality alone treats NFC/NFD spellings as canonically equal;
/// that is not sufficient to bind a protocol DID, suggestion UID, or approval.
public struct WireTextIdentity: Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        matches(lhs.rawValue, rhs.rawValue)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.utf8.count)
        for byte in rawValue.utf8 { hasher.combine(byte) }
    }

    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }
}
