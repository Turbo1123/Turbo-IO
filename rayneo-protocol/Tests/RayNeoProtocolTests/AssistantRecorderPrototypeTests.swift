import XCTest
@testable import RayNeoProtocol

final class AssistantRecorderPrototypeTests: XCTestCase {
    func testStartAndStopVectors() throws {
        for (start, rc) in [(true,1),(false,2)] {
            let packet = AssistantRecorderPrototype.control(start:start)
            XCTAssertEqual(packet, Data([8,1,16,2,26,8,123,34,114,99,34,58,UInt8(48+rc),125,34,0]))
            let metadata = try BusinessEnvelopeMetadata.inspect(packet)
            XCTAssertEqual(metadata.messageType, 2)
            XCTAssertEqual(metadata.messageBytes, 8)
            XCTAssertEqual(metadata.dataBytes, 0)
        }
    }
}
