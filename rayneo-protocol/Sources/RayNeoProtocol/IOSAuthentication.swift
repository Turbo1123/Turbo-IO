import Foundation
import CryptoKit

/// Pure computations recovered from iOS RayneoNet 1.2.35 sendAuth/receiveAuth.
/// Deliberately separate from Android Authentication (accountID/bondKey/ECDH).
/// No transport, random generation, retry state, credential storage or logging.
public enum IOSAuthentication {
    public enum AuthenticationError: Error, Equatable {
        case invalidProfile, invalidInputLength, invalidProofLength, proofMismatch
    }

    /// Explicit expected lengths: the iOS handshake lengths are not yet hardware-verified.
    /// The 1024-byte component cap is a local allocation policy, not a firmware capability.
    public struct Profile: Equatable, Sendable {
        public let randomBytes: Int
        public let phoneIdentifierBytes: Int
        public let glassesAddressBytes: Int

        public init(randomBytes: Int, phoneIdentifierBytes: Int, glassesAddressBytes: Int) throws {
            guard (1...1024).contains(randomBytes), (1...1024).contains(phoneIdentifierBytes),
                  (1...1024).contains(glassesAddressBytes) else { throw AuthenticationError.invalidProfile }
            self.randomBytes = randomBytes
            self.phoneIdentifierBytes = phoneIdentifierBytes
            self.glassesAddressBytes = glassesAddressBytes
        }
    }

    // Program constant independently recovered from the iOS binary, not a user secret.
    private static let salt = Data([0x07, 0x12, 0xc8, 0xad, 0x27, 0x74, 0x41, 0x95,
                                    0xde, 0x5f, 0xa1, 0xea, 0x6d, 0x02, 0x5f, 0xb8])

    /// P is the protocol device identifier, NOT a proven iPhone hardware Bluetooth MAC.
    /// G is the already hex-decoded mainBtMAC; callers must not pass its UTF-8 hex text.
    public static func phoneProof(localRandom: Data, phoneProtocolIdentifier: Data,
                                  glassesAddress: Data, profile: Profile) throws -> Data {
        try check(random: localRandom, phone: phoneProtocolIdentifier, glasses: glassesAddress, profile: profile)
        return digest([localRandom, phoneProtocolIdentifier, glassesAddress, salt])
    }

    public static func verifyGlassProof(_ proof: Data, glassRandom: Data, phoneProtocolIdentifier: Data,
                                        glassesAddress: Data, profile: Profile) throws -> Bool {
        try check(random: glassRandom, phone: phoneProtocolIdentifier, glasses: glassesAddress, profile: profile)
        guard proof.count == 32 else { throw AuthenticationError.invalidProofLength }
        let expected = digest([glassRandom, phoneProtocolIdentifier, glassesAddress, salt])
        // No early exit for differing bytes; Swift optimization is not a constant-time guarantee.
        var difference: UInt8 = 0
        for (received, wanted) in zip(proof, expected) { difference |= received ^ wanted }
        return difference == 0
    }

    /// Raw calculation only. Does NOT authenticate the peer or establish a session.
    /// Prefer verifiedSessionKey when consuming an untrusted peer's response.
    public static func sessionKey(localRandom: Data, glassRandom: Data, phoneProtocolIdentifier: Data,
                                  glassesAddress: Data, profile: Profile) throws -> Data {
        try check(random: localRandom, phone: phoneProtocolIdentifier, glasses: glassesAddress, profile: profile)
        guard glassRandom.count == profile.randomBytes else { throw AuthenticationError.invalidInputLength }
        return digest([localRandom, glassRandom, phoneProtocolIdentifier, glassesAddress, salt])
    }

    /// Rejects the peer proof before returning derived bytes. Application pairing-attempt/state
    /// checks and replay protection are still required; this helper cannot replace them.
    public static func verifiedSessionKey(localRandom: Data, glassRandom: Data, glassProof: Data,
                                          phoneProtocolIdentifier: Data, glassesAddress: Data,
                                          profile: Profile) throws -> Data {
        try check(random: localRandom, phone: phoneProtocolIdentifier, glasses: glassesAddress, profile: profile)
        guard try verifyGlassProof(glassProof, glassRandom: glassRandom,
                                   phoneProtocolIdentifier: phoneProtocolIdentifier,
                                   glassesAddress: glassesAddress, profile: profile) else {
            throw AuthenticationError.proofMismatch
        }
        return try sessionKey(localRandom: localRandom, glassRandom: glassRandom,
                              phoneProtocolIdentifier: phoneProtocolIdentifier,
                              glassesAddress: glassesAddress, profile: profile)
    }

    private static func check(random: Data, phone: Data, glasses: Data, profile: Profile) throws {
        guard random.count == profile.randomBytes, phone.count == profile.phoneIdentifierBytes,
              glasses.count == profile.glassesAddressBytes else { throw AuthenticationError.invalidInputLength }
    }

    private static func digest(_ fields: [Data]) -> Data {
        var hash = SHA256()
        for field in fields { hash.update(data: field) }
        return Data(hash.finalize())
    }
}
