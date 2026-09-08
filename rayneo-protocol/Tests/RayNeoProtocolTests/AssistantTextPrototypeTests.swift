import XCTest
@testable import RayNeoProtocol

final class AssistantTextPrototypeTests: XCTestCase {
    func testSyntheticGoldenVector() throws {
        let body = Data("{\"final\":true,\"text\":\"test\"}".utf8)
        XCTAssertEqual(try AssistantTextPrototype.asrText("test", isFinal:true),
                       Data([8,1,16,5,26,UInt8(body.count)]) + body)
    }
    func testUnicodeEscapingAndMultibyteLength() throws {
        let text = String(repeating:"中文\"\n", count:20)
        let packet = try AssistantTextPrototype.asrText(text, isFinal:false)
        let metadata = try BusinessEnvelopeMetadata.inspect(packet)
        XCTAssertEqual(metadata.version,1)
        XCTAssertEqual(metadata.messageType,5)
        XCTAssertGreaterThan(metadata.messageBytes!,127)
        let body = try JSONSerialization.jsonObject(with:packet.suffix(metadata.messageBytes!)) as! [String:Any]
        XCTAssertEqual(body["text"] as? String,text)
        XCTAssertEqual(body["final"] as? Bool,false)
        XCTAssertNil(body["isFinal"], "Swift API argument name is not the ASR wire key")
    }
    func testLocalConservativeUTF8Limit() {
        XCTAssertThrowsError(try AssistantTextPrototype.asrText(String(repeating:"中",count:342), isFinal:true))
    }
    func testBothBoundaryValuesUseOfficialKeyOnly() throws {
        for final in [false,true] {
            let packet = try AssistantTextPrototype.asrText("句末",isFinal:final)
            let metadata = try BusinessEnvelopeMetadata.inspect(packet)
            let body = try JSONSerialization.jsonObject(with:packet.suffix(metadata.messageBytes!)) as! [String:Any]
            XCTAssertEqual(Set(body.keys), Set(["text","final"]))
            XCTAssertEqual(body["final"] as? Bool,final)
        }
    }
}
