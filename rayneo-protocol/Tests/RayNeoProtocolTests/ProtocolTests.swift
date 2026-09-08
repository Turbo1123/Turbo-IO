import XCTest
import CryptoKit
@testable import RayNeoProtocol

final class ProtocolTests: XCTestCase {
    let phone = Data([0,0x11,0x22,0x33,0x44,0x55])
    let glasses = Data([0xaa,0xbb,0xcc,0xdd,0xee,0xff])
    let random = Data([1,2,3,4])
    let key = Data(0..<32)
    func hex(_ d: Data) -> String { d.map { String(format:"%02x",$0) }.joined() }

    // Independently computed with Python hashlib, synthetic data only.
    func testGuestProofVector() throws {
        XCTAssertEqual(hex(try Authentication.guestProof(random: random, phone: phone, glasses: glasses)), "481bb79704a8523c1e86ae93cfb2bd7204b76984d2d2c3684799d70b58839c84")
    }
    func testBoundProofVector() throws {
        XCTAssertEqual(hex(try Authentication.boundProof(random: random, phone: phone, glasses: glasses, accountID: "test-account", bondKey: key)), "ba2483fb0d0c3aad8b21df5133cb2c9f32d087d4e4a5b8bf89c739965fafa000")
    }
    func testBondUsesAccountID() throws {
        XCTAssertEqual(hex(try Authentication.bondKey(sharedSecret: key, accountID: "test-account")), "ebcd452cc71d3a1a1af1299acc093e1fb6cb09142f7c729f6fd38a4bf3cdd810")
    }
    func testSessionUsesHexText() throws {
        XCTAssertEqual(hex(try Authentication.sessionKey(localRandom: random, peerRandom: Data([0xa1,0xa2,0xa3,0xa4]), phone: phone, glasses: glasses, bondKeyHex: hex(key))), "7368fe1d61a9c94539272f65df3f1ace2e060b0a410a4fcc80b44fb35395d67c")
    }
    func testP256Exchange() throws {
        let a = P256.KeyAgreement.PrivateKey(), b = P256.KeyAgreement.PrivateKey()
        XCTAssertEqual(try Authentication.sharedSecret(privateKey: a, peerX963: b.publicKey.x963Representation), try Authentication.sharedSecret(privateKey: b, peerX963: a.publicKey.x963Representation))
    }
    func testNoSilentAuthDowngrade() {
        XCTAssertThrowsError(try Authentication.boundProof(random: random, phone: phone, glasses: glasses, accountID: "", bondKey: key))
        XCTAssertThrowsError(try Authentication.boundProof(random: Data(), phone: phone, glasses: glasses, accountID: "test", bondKey: key))
        XCTAssertFalse(Authentication.proofMatches(Data(repeating: 0,count:32), expected:key))
        XCTAssertTrue(Authentication.proofMatches(key,expected:key))
    }
    func testAuthTLVRoundtrip() throws {
        let packet = try TLV.authRequest(random: random, proof:key)
        XCTAssertEqual(packet.prefix(3),Data([0x18,0,42]))
        XCTAssertEqual(packet.count,45)
        let outer = try XCTUnwrap(TLV.decode(packet).first)
        let fields = try TLV.authFields(outer.value)
        XCTAssertEqual(fields.random, random)
        XCTAssertEqual(fields.proof,key)
    }
    func testBadTLVs() throws {
        XCTAssertThrowsError(try TLV.decode(Data([1,0])))
        XCTAssertThrowsError(try TLV.decode(Data([1,0,4,1])))
        XCTAssertThrowsError(try TLV(tag:1,value:Data(repeating:0,count:65536)).encoded())
        let repeated = try TLV(tag:0x10,value:random).encoded() + TLV(tag:0x10,value:random).encoded()
        XCTAssertThrowsError(try TLV.authFields(repeated))
    }
    func testHexRejectsInvalidInput() {
        XCTAssertThrowsError(try Authentication.decodeHex("abc"))
        XCTAssertThrowsError(try Authentication.decodeHex("zz"))
    }
}
