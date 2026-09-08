import XCTest
@testable import RayNeoProtocol

final class LauncherControlPrototypeTests: XCTestCase {
    func testEnableMatchesObservedEnvelopeAndControl() throws {
        let packet = try LauncherControlPrototype.encode(.enableVoiceWakeup)
        let body = Data(#"{"cmd":"set_ai_voice_wakeup","payload":{"data":"","mode":1,"value":0}}"#.utf8)
        XCTAssertEqual(packet, Data([8,1,16,16,26,70]) + body + Data([34,0]))
        let metadata = try BusinessEnvelopeMetadata.inspect(packet)
        XCTAssertEqual(packet.count, 78)
        XCTAssertEqual(metadata.version, 1)
        XCTAssertEqual(metadata.messageType, 16)
        XCTAssertEqual(metadata.messageBytes, 70)
        XCTAssertEqual(metadata.dataBytes, 0)
    }
    func testOtherObservedCommands() throws {
        let word = try LauncherControlPrototype.encode(.officialWakeWord)
        XCTAssertEqual(word.count, 77)
        XCTAssertEqual(try BusinessEnvelopeMetadata.inspect(word).messageType, 16)
        let query = try LauncherControlPrototype.encode(.requestGeneralStatus)
        XCTAssertEqual(query.count, 81)
        XCTAssertEqual(try BusinessEnvelopeMetadata.inspect(query).messageType, 1)
    }
}
