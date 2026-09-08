import XCTest
@testable import RayNeoProtocol

final class AssistantAnswerPrototypeTests: XCTestCase {
    func testSeparateAnswerAndQuestion() throws {
        let id = UUID()
        let packet = try AssistantAnswerPrototype.chat("七。",isFinal:false,roundID:id,query:"三加四？",timestampMilliseconds:123)
        let meta = try BusinessEnvelopeMetadata.inspect(packet)
        XCTAssertEqual(meta.version,1); XCTAssertEqual(meta.messageType,32)
        let body = try JSONSerialization.jsonObject(with:packet.suffix(meta.messageBytes!)) as! [String:Any]
        XCTAssertEqual(body["query"] as? String,"三加四？")
        XCTAssertEqual(body["sid"] as? String,id.uuidString.lowercased())
        XCTAssertEqual(body["uuid"] as? String,body["sid"] as? String)
        XCTAssertEqual(body["intent"] as? String,"chat")
        XCTAssertEqual(body["sub"] as? String,"workflow")
        XCTAssertEqual(body["round"] as? Int,-1)
        XCTAssertEqual((body["payload"] as? [String:String])?.count,0)
        XCTAssertNil(body["commandRequestId"])
        XCTAssertNil(body["answerText"])
        let answer = body["answer"] as! [String:Any]
        XCTAssertEqual(answer["text"] as? String,"七。")
        XCTAssertEqual(answer["isFinal"] as? Bool,false)
    }
    func testBounds() {
        XCTAssertThrowsError(try AssistantAnswerPrototype.chat("",isFinal:false,roundID:UUID(),query:"",timestampMilliseconds:0))
        XCTAssertThrowsError(try AssistantAnswerPrototype.chat(String(repeating:"中",count:171),isFinal:true,roundID:UUID(),query:"",timestampMilliseconds:0))
        XCTAssertThrowsError(try AssistantAnswerPrototype.chat("好",isFinal:true,roundID:UUID(),query:String(repeating:"a",count:513),timestampMilliseconds:0))
    }
    func testEmptyFinalAndSeparateCompletion() throws {
        let packet = try AssistantAnswerPrototype.chat("",isFinal:true,roundID:UUID(),query:"",timestampMilliseconds:0)
        let meta = try BusinessEnvelopeMetadata.inspect(packet)
        XCTAssertEqual(meta.messageType,32)
        let body = try JSONSerialization.jsonObject(with:packet.suffix(meta.messageBytes!)) as! [String:Any]
        XCTAssertEqual((body["answer"] as? [String:Any])?["text"] as? String,"")
        XCTAssertEqual(AssistantResponseCompletePrototype.complete(),Data([8,1,16,12,26,2,123,125,34,0]))
    }
}
