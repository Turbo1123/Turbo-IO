import XCTest
@testable import RayNeoProtocol

final class AssistantExitPrototypeTests: XCTestCase {
    func testNormalExitIsNotRecorderStop() throws {
        let packet = AssistantExitPrototype.normalExit()
        let metadata = try BusinessEnvelopeMetadata.inspect(packet)
        XCTAssertEqual(metadata.version,1)
        XCTAssertEqual(metadata.messageType,7)
        XCTAssertEqual(metadata.messageBytes,8)
        XCTAssertEqual(metadata.dataBytes,0)
        XCTAssertEqual(String(data:packet.subdata(in:6..<14),encoding:.utf8),#"{"rc":1}"#)
        XCTAssertNotEqual(packet,AssistantRecorderPrototype.control(start:false))
    }
}
