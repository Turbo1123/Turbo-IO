import XCTest
@testable import RayNeoProtocol
final class AssistantVADPrototypeTests: XCTestCase {
    func testAllStatusesAreType4NotRecorderControl() {
        for status in AssistantVADPrototype.Status.allCases {
            let body = Data("{\"rc\":\(status.rawValue)}".utf8)
            XCTAssertEqual(AssistantVADPrototype.status(status), Data([8,1,16,4,26,8]) + body + Data([34,0]))
            XCTAssertNotEqual(AssistantVADPrototype.status(status), AssistantRecorderPrototype.control(start:true))
        }
    }
}
