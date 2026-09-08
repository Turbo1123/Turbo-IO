import XCTest
@testable import RayNeoCompanion

@MainActor final class DisplayObservationTests: XCTestCase {
    func testDisabledAndWrongBusinessNeverCapture() throws {
        let o = DisplayObservation(); o.connection(true,phase:"idle")
        let data = try DeviceBusinessWire.encode(type:5,json:["text":"private"])
        o.packet(data,business:13,inbound:false); XCTAssertTrue(o.events.isEmpty)
        o.enabled = true; o.packet(data,business:99,inbound:false); XCTAssertTrue(o.events.isEmpty)
    }
    func testPreviewAndExitComeFromGlassesOnly() throws {
        let o = DisplayObservation(); o.enabled = true; o.connection(true,phase:"idle")
        func packet(_ action: Int) throws -> Data {
            let raw = try JSONSerialization.data(withJSONObject:["scence":2,"app":["name":"com.rayneo.liteos.todo","action":action]])
            return try DeviceBusinessWire.encode(type:24,json:["cmd":"glass_preview","payload":["data":String(decoding:raw,as:UTF8.self)]])
        }
        o.packet(try packet(1),business:15,inbound:false); XCTAssertTrue(o.page.isEmpty)
        o.packet(try packet(1),business:15,inbound:true); XCTAssertEqual(o.page["app"] as? String,"待办")
        o.packet(try packet(2),business:15,inbound:true); XCTAssertEqual(o.page["name"] as? String,"应用已退出；等待下一页面")
        o.connection(false,phase:"waitingForConnection"); XCTAssertTrue(o.page.isEmpty)
        o.packet(try packet(1),business:15,inbound:true); XCTAssertTrue(o.page.isEmpty)
    }
    func testTextIsOptInBoundedAndCleared() throws {
        let o = DisplayObservation(); o.enabled = true; o.connection(true,phase:"idle")
        let data = try DeviceBusinessWire.encode(type:5,json:["text":"测试 ASR","key":"DO_NOT_EXPORT"])
        o.packet(data,business:13,inbound:false); XCTAssertEqual(o.question,"")
        o.includesText = true; o.packet(data,business:13,inbound:false); XCTAssertEqual(o.question,"测试 ASR")
        for _ in 0..<95 { o.voiceMetadata(type:11) }; XCTAssertEqual(o.events.count,80)
        let json = try JSONSerialization.data(withJSONObject:o.snapshot())
        XCTAssertFalse(String(decoding:json,as:UTF8.self).contains("DO_NOT_EXPORT"))
        o.includesText = false; XCTAssertEqual(o.question,""); XCTAssertTrue(o.events.isEmpty)
    }
    func testAudioAndUnknownPreviewNamesAreNotExported() throws {
        let o = DisplayObservation(); o.enabled = true; o.connection(true,phase:"idle"); o.includesText = true
        let count = o.events.count
        o.packet(try DeviceBusinessWire.encode(type:3,json:[:],bytes:Data([1,2,3])),business:13,inbound:true)
        XCTAssertEqual(o.events.count,count)
        let raw = "{\"scence\":2,\"app\":{\"name\":\"private-name\",\"action\":1},\"private\":\"secret\"}"
        o.packet(try DeviceBusinessWire.encode(type:24,json:["cmd":"glass_preview","payload":["data":raw]]),business:15,inbound:true)
        let json = String(decoding:try JSONSerialization.data(withJSONObject:o.snapshot()),as:UTF8.self)
        XCTAssertFalse(json.contains("private-name")); XCTAssertFalse(json.contains("secret"))
        XCTAssertEqual(o.page["app"] as? String,"未知应用")
    }
    func testAnswerRoundsAndQueueLoss() throws {
        let o = DisplayObservation(); o.enabled = true; o.connection(true,phase:"idle"); o.includesText = true
        for (id,text) in [("a","甲"),("a","乙"),("b","丙")] {
            o.packet(try DeviceBusinessWire.encode(type:32,json:["uuid":id,"answer":["text":text]]),business:13,inbound:false)
        }
        XCTAssertEqual(o.answer,"丙")
        o.loss(); XCTAssertTrue(o.page.isEmpty); XCTAssertEqual(o.events.last?["kind"] as? String,"loss")
    }
    func testHTTPRequiresSingleTokenAndRejectsBrowserAndWrites() {
        let token = String(repeating:"a",count:32)
        let header = "Authorization: Bearer \(token)\r\n"
        XCTAssertTrue(DisplayObserverServer.authorized(Data("GET /snapshot HTTP/1.1\r\n\(header)\r\n".utf8),token:token))
        for raw in ["GET /snapshot HTTP/1.1\r\n\r\n", "POST /snapshot HTTP/1.1\r\n\(header)\r\n",
                    "GET /snapshot HTTP/1.1\r\n\(header)\(header)\r\n", "GET /snapshot HTTP/1.1\r\n\(header)Origin: https://bad.example\r\n\r\n"] {
            XCTAssertFalse(DisplayObserverServer.authorized(Data(raw.utf8),token:token))
        }
    }
    func testCombiningTextCannotGrowSnapshotWithoutBound() throws {
        let o = DisplayObservation(); o.enabled = true; o.connection(true,phase:"idle"); o.includesText = true
        let text = "a" + String(repeating:"\u{0301}",count:1000)
        let packet = try DeviceBusinessWire.encode(type:32,json:["uuid":"a","answer":["text":text]])
        for _ in 0..<100 { o.packet(packet,business:13,inbound:false) }
        XCTAssertLessThan(o.answer.utf8.count,16400)
        XCTAssertLessThan(try JSONSerialization.data(withJSONObject:o.snapshot()).count,250000)
        o.newUtterance(); XCTAssertEqual(o.answer,""); XCTAssertEqual(o.question,"")
    }
}
