import XCTest
@testable import RayNeoProtocol

final class IOSAuthenticationTests: XCTestCase {
    // Synthetic values; sizes here are test choices, not verified iOS handshake requirements.
    private let phone = Data([0, 0x11, 0x22, 0x33, 0x44, 0x55])
    private let glasses = Data([0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
    private let local = Data([1, 2, 3, 4])
    private let peer = Data([0xa1, 0xa2, 0xa3, 0xa4])
    private func profile() throws -> IOSAuthentication.Profile {
        try .init(randomBytes: 4, phoneIdentifierBytes: 6, glassesAddressBytes: 6)
    }
    private func bytes(_ hex: String) throws -> Data { try Authentication.decodeHex(hex) }
    private func glassProof() throws -> Data { try bytes("47b8fc3463200640a800e35c6014009dc2fe2f603c57f7bf23cdd64a160d1209") }

    // Independent Node crypto SHA-256 vectors. No official/real-device credentials used.
    func testPhoneProofGoldenVector() throws {
        XCTAssertEqual(try IOSAuthentication.phoneProof(localRandom: local, phoneProtocolIdentifier: phone,
                                                       glassesAddress: glasses, profile: profile()),
                       try bytes("481bb79704a8523c1e86ae93cfb2bd7204b76984d2d2c3684799d70b58839c84"))
    }

    func testGlassProofGoldenVector() throws {
        XCTAssertTrue(try IOSAuthentication.verifyGlassProof(glassProof(), glassRandom: peer,
                                                             phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile()))
        XCTAssertFalse(try IOSAuthentication.verifyGlassProof(glassProof(), glassRandom: local,
                                                              phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile()))
    }

    func testSessionGoldenVectorAndRandomOrder() throws {
        let key = try IOSAuthentication.sessionKey(localRandom: local, glassRandom: peer,
                                                   phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile())
        XCTAssertEqual(key, try bytes("1f378c42dc42af263497957a736298adaf4b394616290bea5cd4312acb9f3d17"))
        XCTAssertEqual(try IOSAuthentication.sessionKey(localRandom: peer, glassRandom: local,
                                                        phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile()),
                       try bytes("0cc551f16dd05b2a53773d1f3360e84cff830e1d060ace3a6e1d84ec91ebe1bc"))
    }

    func testVerifiedSessionReturnsSameBytesOnlyForMatchingProof() throws {
        let expected = try IOSAuthentication.sessionKey(localRandom: local, glassRandom: peer,
                                                        phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile())
        XCTAssertEqual(try IOSAuthentication.verifiedSessionKey(localRandom: local, glassRandom: peer,
                                                                glassProof: glassProof(), phoneProtocolIdentifier: phone,
                                                                glassesAddress: glasses, profile: profile()), expected)
        var badProof = try glassProof(); badProof[31] ^= 1
        XCTAssertThrowsError(try IOSAuthentication.verifiedSessionKey(localRandom: local, glassRandom: peer,
                                                                    glassProof: badProof, phoneProtocolIdentifier: phone,
                                                                    glassesAddress: glasses, profile: profile())) {
            XCTAssertEqual($0 as? IOSAuthentication.AuthenticationError, .proofMismatch)
        }
    }

    func testEveryProofByteMatters() throws {
        for index in 0..<32 {
            var altered = try glassProof(); altered[index] ^= 1
            XCTAssertFalse(try IOSAuthentication.verifyGlassProof(altered, glassRandom: peer,
                                                                  phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile()))
        }
    }

    func testIdentityOrderAndHexTextCannotSilentlyPass() throws {
        XCTAssertFalse(try IOSAuthentication.verifyGlassProof(glassProof(), glassRandom: peer,
                                                              phoneProtocolIdentifier: glasses, glassesAddress: phone, profile: profile()))
        XCTAssertThrowsError(try IOSAuthentication.phoneProof(localRandom: local, phoneProtocolIdentifier: phone,
                                                            glassesAddress: Data("aabbccddeeff".utf8), profile: profile()))
    }

    func testInvalidProfileAndComponentSizesFailClosed() throws {
        for count in [-1, 0, 1025, Int.max] {
            XCTAssertThrowsError(try IOSAuthentication.Profile(randomBytes: count, phoneIdentifierBytes: 6, glassesAddressBytes: 6))
            XCTAssertThrowsError(try IOSAuthentication.Profile(randomBytes: 4, phoneIdentifierBytes: count, glassesAddressBytes: 6))
            XCTAssertThrowsError(try IOSAuthentication.Profile(randomBytes: 4, phoneIdentifierBytes: 6, glassesAddressBytes: count))
        }
        for count in [0, 3, 5, 1025] {
            XCTAssertThrowsError(try IOSAuthentication.phoneProof(localRandom: Data(repeating: 1, count: count),
                                                                phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile()))
            XCTAssertThrowsError(try IOSAuthentication.sessionKey(localRandom: local, glassRandom: Data(repeating: 1, count: count),
                                                                 phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile()))
        }
        XCTAssertThrowsError(try IOSAuthentication.phoneProof(localRandom: local, phoneProtocolIdentifier: Data(),
                                                            glassesAddress: glasses, profile: profile()))
        XCTAssertThrowsError(try IOSAuthentication.verifiedSessionKey(localRandom: Data(), glassRandom: peer,
                                                                    glassProof: glassProof(), phoneProtocolIdentifier: phone,
                                                                    glassesAddress: glasses, profile: profile()))
    }

    func testProofLengthIsExactlySHA256Size() throws {
        for length in [0, 31, 33, 1024] {
            XCTAssertThrowsError(try IOSAuthentication.verifyGlassProof(Data(repeating: 0, count: length), glassRandom: peer,
                                                                      phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile())) {
                XCTAssertEqual($0 as? IOSAuthentication.AuthenticationError, .invalidProofLength)
            }
        }
    }

    func testExplicitAlternateLengthsDoNotInheritAndroidFourSixRule() throws {
        let alternate = try IOSAuthentication.Profile(randomBytes: 3, phoneIdentifierBytes: 2, glassesAddressBytes: 1)
        let result = try IOSAuthentication.phoneProof(localRandom: Data([1, 2, 3]), phoneProtocolIdentifier: Data([4, 5]),
                                                     glassesAddress: Data([6]), profile: alternate)
        XCTAssertEqual(result.count, 32)
        XCTAssertThrowsError(try IOSAuthentication.phoneProof(localRandom: local, phoneProtocolIdentifier: phone,
                                                            glassesAddress: glasses, profile: alternate))
    }

    func testIOSSessionDoesNotUseAndroidBondKeyText() throws {
        let ios = try IOSAuthentication.sessionKey(localRandom: local, glassRandom: peer,
                                                   phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile())
        let androidBound = try Authentication.sessionKey(localRandom: local, peerRandom: peer, phone: phone,
                                                         glasses: glasses, bondKeyHex: String(repeating: "01", count: 32))
        XCTAssertNotEqual(ios, androidBound)
        // Formula overlap in Android guest mode is arithmetic evidence only, not flow compatibility.
        XCTAssertEqual(ios, try Authentication.sessionKey(localRandom: local, peerRandom: peer, phone: phone,
                                                          glasses: glasses, bondKeyHex: nil))
    }

    func testNonZeroDataSliceInputs() throws {
        let prefixedLocal = Data([9]) + local
        let prefixedProof = Data([8, 7]) + (try glassProof())
        XCTAssertTrue(try IOSAuthentication.verifyGlassProof(prefixedProof.dropFirst(2), glassRandom: peer,
                                                             phoneProtocolIdentifier: phone, glassesAddress: glasses, profile: profile()))
        XCTAssertEqual(try IOSAuthentication.phoneProof(localRandom: prefixedLocal.dropFirst(), phoneProtocolIdentifier: phone,
                                                       glassesAddress: glasses, profile: profile()),
                       try bytes("481bb79704a8523c1e86ae93cfb2bd7204b76984d2d2c3684799d70b58839c84"))
    }

    func testMaximumExplicitFieldLengthsAndOneByteOverRejected() throws {
        let maximum = try IOSAuthentication.Profile(randomBytes: 1024, phoneIdentifierBytes: 1024, glassesAddressBytes: 1024)
        let random = Data(repeating: 1, count: 1024), phoneID = Data(repeating: 2, count: 1024)
        let address = Data(repeating: 3, count: 1024)
        XCTAssertEqual(try IOSAuthentication.phoneProof(localRandom: random, phoneProtocolIdentifier: phoneID,
                                                       glassesAddress: address, profile: maximum).count, 32)
        XCTAssertEqual(try IOSAuthentication.sessionKey(localRandom: random, glassRandom: random,
                                                       phoneProtocolIdentifier: phoneID, glassesAddress: address, profile: maximum).count, 32)
        XCTAssertThrowsError(try IOSAuthentication.phoneProof(localRandom: random, phoneProtocolIdentifier: phoneID + Data([0]),
                                                            glassesAddress: address, profile: maximum))
        XCTAssertThrowsError(try IOSAuthentication.phoneProof(localRandom: random, phoneProtocolIdentifier: phoneID,
                                                            glassesAddress: address + Data([0]), profile: maximum))
    }
}
