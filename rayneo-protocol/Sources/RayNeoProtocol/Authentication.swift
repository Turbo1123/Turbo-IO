import Foundation
import CryptoKit

public enum ProtocolError: Error, Equatable {
    case invalidLength, invalidHex, missingAccount, truncatedTLV, duplicateTag
}

/// Reconstructed from supplied Android RNAuthManager; not yet iOS wire-verified.
/// Pure calculations only: no login, pairing-state changes, transport or key logs.
public enum Authentication {
    // A protocol constant, not a user/device secret.
    private static let salt = Data([0x07,0x12,0xc8,0xad,0x27,0x74,0x41,0x95,0xde,0x5f,0xa1,0xea,0x6d,0x02,0x5f,0xb8])

    public static func decodeHex(_ text: String) throws -> Data {
        let bytes = Array(text.utf8)
        guard bytes.count.isMultiple(of: 2) else { throw ProtocolError.invalidHex }
        var data = Data()
        for i in stride(from: 0, to: bytes.count, by: 2) {
            guard let n = UInt8(String(bytes: bytes[i...i+1], encoding: .utf8) ?? "", radix: 16) else { throw ProtocolError.invalidHex }
            data.append(n)
        }
        return data
    }

    private static func check(_ random: Data, _ phone: Data, _ glasses: Data) throws {
        guard random.count == 4, phone.count == 6, glasses.count == 6 else { throw ProtocolError.invalidLength }
    }

    /// Guest branch is explicit: never silently downgrade a bound account.
    public static func guestProof(random: Data, phone: Data, glasses: Data) throws -> Data {
        try check(random, phone, glasses)
        return Data(SHA256.hash(data: random + phone + glasses + salt))
    }

    public static func boundProof(random: Data, phone: Data, glasses: Data, accountID: String, bondKey: Data) throws -> Data {
        try check(random, phone, glasses)
        guard !accountID.isEmpty else { throw ProtocolError.missingAccount }
        guard bondKey.count == 32 else { throw ProtocolError.invalidLength }
        return Data(SHA256.hash(data: random + phone + glasses + Data(accountID.utf8) + bondKey))
    }

    /// Call-site evidence uses accountID here, NOT glasses serial number.
    public static func bondKey(sharedSecret: Data, accountID: String) throws -> Data {
        guard sharedSecret.count == 32 else { throw ProtocolError.invalidLength }
        guard !accountID.isEmpty else { throw ProtocolError.missingAccount }
        return Data(SHA256.hash(data: sharedSecret + salt + Data(accountID.utf8)))
    }

    public static func sharedSecret(privateKey: P256.KeyAgreement.PrivateKey, peerX963: Data) throws -> Data {
        guard peerX963.count == 65, peerX963.first == 4 else { throw ProtocolError.invalidLength }
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: peerX963)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        return secret.withUnsafeBytes { Data($0) }
    }

    /// Android's session derivation appends UTF-8 HEX TEXT, not decoded key bytes.
    /// Preserve the key string's exact case; peer interop is not yet verified.
    public static func sessionKey(localRandom: Data, peerRandom: Data, phone: Data, glasses: Data, bondKeyHex: String?) throws -> Data {
        try check(localRandom, phone, glasses)
        guard peerRandom.count == 4 else { throw ProtocolError.invalidLength }
        var material = localRandom + peerRandom + phone + glasses + salt
        if let hex = bondKeyHex {
            guard try decodeHex(hex).count == 32 else { throw ProtocolError.invalidLength }
            material += Data(hex.utf8)
        }
        return Data(SHA256.hash(data: material))
    }

    public static func proofMatches(_ received: Data, expected: Data) -> Bool {
        guard received.count == 32, expected.count == 32 else { return false }
        // Avoid early exit on differing bytes; not a constant-time guarantee
        // across all Swift optimizer/toolchain versions.
        var difference: UInt8 = 0
        for (a,b) in zip(received, expected) { difference |= a ^ b }
        return difference == 0
    }
}
