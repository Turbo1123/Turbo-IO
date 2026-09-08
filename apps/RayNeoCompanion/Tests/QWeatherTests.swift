import XCTest
@testable import RayNeoCompanion

@MainActor final class QWeatherTests: XCTestCase {
    let time = Date()
    func config(verified: Bool = false) -> QWeatherConfiguration {
        var c = QWeatherConfiguration(); c.host = "test.qweatherapi.com"
        if verified { c.verifiedIcons["104"] = 104 }; return c
    }
    func defaults(_ c: QWeatherConfiguration) throws -> UserDefaults {
        let d = UserDefaults(suiteName:"QWeatherTests.\(UUID())")!
        d.set(try JSONEncoder().encode(c),forKey:"companion.v1.qweatherDashboard"); return d
    }
    func sample() -> QWeatherSnapshot { .init(temperature:21.91,condition:"阴",code:104,fetchedAt:time,attributions:["https://developer.qweather.com/attribution.html"]) }
    func settle(_ c: QWeatherDashboard) async {
        for _ in 0..<200 { if !c.busy { return }; await Task.yield() }; XCTAssertFalse(c.busy)
    }
    func testHostAndCoordinatesCannotLeakKeyToArbitraryEndpoint() throws {
        var c = config()
        for host in ["evil.example", "qweatherapi.com.evil.test", "https://test.qweatherapi.com", "a.qweatherapi.com/path", "user@a.qweatherapi.com", "a.qweatherapi.com:443"] {
            c.host = host; XCTAssertThrowsError(try QWeatherClient.request(c,key:"synthetic"))
        }
        c = config()
        for coordinate in ["90.01", "39.123", "39?secret", "NaN"] {
            c.latitude = coordinate; XCTAssertThrowsError(try QWeatherClient.request(c,key:"synthetic"))
        }
    }
    func testUsesCurrentNotForecastAndKeyOnlyInHeader() throws {
        let r = try QWeatherClient.request(config(),key:"synthetic-key")
        XCTAssertEqual(r.url?.path,"/weather/v1/current/39.92/116.41")
        XCTAssertEqual(r.value(forHTTPHeaderField:"X-QW-Api-Key"),"synthetic-key")
        XCTAssertFalse(r.url!.absoluteString.contains("synthetic"))
        XCTAssertThrowsError(try QWeatherClient.request(config(),key:"bad\nheader"))
    }
    func testNewSchemaUnitAndReceiptAgeAreExplicit() throws {
        let fixture = #"{"temperature":{"value":21.91,"unit":"°C"},"condition":{"text":"阴","code":"104"},"metadata":{"attributions":["QWeather"]}}"#
        let s = try QWeatherClient.decode(Data(fixture.utf8),now:time)
        XCTAssertEqual(s.lensTemperature,22); XCTAssertEqual(s.code,104); XCTAssertEqual(s.fetchedAt,time)
        XCTAssertTrue(s.isFresh(time)); XCTAssertFalse(s.isFresh(time.addingTimeInterval(601)))
        XCTAssertFalse(s.isFresh(time.addingTimeInterval(-1)))
        for bad in [fixture.replacingOccurrences(of:"°C",with:"°F"),fixture.replacingOccurrences(of:"21.91",with:"true"),fixture.replacingOccurrences(of:"21.91",with:"99"),"{}"] {
            XCTAssertThrowsError(try QWeatherClient.decode(Data(bad.utf8),now:time))
        }
    }
    func testWireIsHomeWeatherNotCardAndHasCurrentTemperature() throws {
        let wire = try DeviceBusinessWire(QWeatherClient.dashboardWire(sample(),configuration:config(),icon:104,now:time))
        XCTAssertEqual(wire.type,18); XCTAssertEqual(wire.json["cmd"] as? String,"current_weather_update")
        let p = try XCTUnwrap(wire.json["payload"] as? [String:Any])
        let inner = try XCTUnwrap(p["data"] as? String)
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(inner.utf8)) as? [String:Any])
        XCTAssertEqual(j["location"] as? String,"北京"); XCTAssertEqual(j["temp"] as? Int,22)
        XCTAssertEqual(j["icon"] as? Int,104); XCTAssertNil(j["hourly"])
        XCTAssertThrowsError(try QWeatherClient.dashboardWire(sample(),configuration:config(),icon:104,now:time.addingTimeInterval(601)))
    }
    func testNoKeyAndOfflineNeverCallNetwork() async throws {
        var device: String?, queries = 0
        let c = QWeatherDashboard(defaults:try defaults(config()),device:{device},occupied:{false},readKey:{_ in nil},fetch:{_,_ in queries += 1; throw QWeatherError.network},send:{_ in XCTFail()})
        c.tick(); device = "A"; c.tick(); await settle(c); XCTAssertEqual(queries,0)
        XCTAssertTrue(c.status.contains("API Key"))
    }
    func testCandidateRequiresExplicitSendAndCardAckCannotCompleteIt() async throws {
        var sends = 0; let s = sample()
        let c = QWeatherDashboard(defaults:try defaults(config()),device:{"A"},occupied:{false},readKey:{_ in "synthetic"},fetch:{_,_ in s},send:{_ in sends += 1})
        c.tick(); await settle(c); XCTAssertEqual(sends,0)
        c.testCandidate(); XCTAssertEqual(sends,1)
        func ack(_ command: String, _ value: Any = 0) throws -> DeviceBusinessWire {
            try DeviceBusinessWire(DeviceBusinessWire.encode(type:19,json:["cmd":command,"payload":["value":value]]))
        }
        c.receive(device:"A",wire:try ack("weather_update")); XCTAssertTrue(c.reply.contains("等待"))
        c.receive(device:"B",wire:try ack("current_weather_update")); XCTAssertTrue(c.reply.contains("等待"))
        c.receive(device:"A",wire:try ack("current_weather_update",true)); XCTAssertTrue(c.reply.contains("等待"))
        c.receive(device:"A",wire:try ack("current_weather_update")); XCTAssertTrue(c.reply.contains("value=0"))
        XCTAssertTrue(c.reply.contains("没有请求 ID"))
    }
    func testVerifiedAutoOnceReconnectUsesCacheAndBusyDefers() async throws {
        var device: String? = "A", occupied = true, queries = 0, sends = 0
        let s = sample()
        let c = QWeatherDashboard(defaults:try defaults(config(verified:true)),device:{device},occupied:{occupied},readKey:{_ in "synthetic"},fetch:{_,_ in queries += 1; return s},send:{_ in sends += 1})
        c.tick(); XCTAssertEqual(queries,0); occupied = false; c.tick(); await settle(c)
        c.tick(); XCTAssertEqual(sends,1)
        device = nil; c.tick(); device = "A"; c.tick(); await settle(c)
        XCTAssertEqual(queries,1); XCTAssertEqual(sends,2)
    }
    func testDisconnectDropsLateFetch() async throws {
        var device: String? = "A", continuation: CheckedContinuation<QWeatherSnapshot,Error>?
        let c = QWeatherDashboard(defaults:try defaults(config(verified:true)),device:{device},occupied:{false},readKey:{_ in "synthetic"},fetch:{_,_ in try await withCheckedThrowingContinuation { continuation = $0 }},send:{_ in XCTFail()})
        c.tick(); for _ in 0..<200 { if continuation != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(continuation); device = nil; c.tick(); pending.resume(returning:sample())
        for _ in 0..<20 { await Task.yield() }; XCTAssertNil(c.snapshot)
    }
    func testTimeoutAndSendErrorsDoNotReportSuccess() async throws {
        var clock = time; let s = sample()
        let c = QWeatherDashboard(defaults:try defaults(config(verified:true)),device:{"A"},occupied:{false},readKey:{_ in "synthetic"},fetch:{_,_ in s},now:{clock},send:{_ in })
        c.tick(); await settle(c); clock = time.addingTimeInterval(9); c.tick()
        XCTAssertTrue(c.reply.contains("未观察"))
        let failed = QWeatherDashboard(defaults:try defaults(config(verified:true)),device:{"A"},occupied:{false},readKey:{_ in "synthetic"},fetch:{_,_ in s},send:{_ in throw DeviceFeatureError.disconnected})
        failed.tick(); await settle(failed); XCTAssertTrue(failed.reply.contains("失败"))
    }
}
