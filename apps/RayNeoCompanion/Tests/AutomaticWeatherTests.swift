import XCTest
@testable import RayNeoCompanion

@MainActor final class AutomaticWeatherTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName:"AutomaticWeatherTests.\(UUID())")! }
    private func snapshot(_ now: Date, sample: Bool = false) -> WeatherstackSnapshot {
        WeatherstackSnapshot(city:"Beijing",country:"China",celsius:27,description:"test-only",
            providerCode:122,sourceLocalTime:"test",sourceDate:now,observedAt:now,fetchedAt:now,
            usedLegacyTemperatureKey:false,isSample:sample)
    }
    private func settle(_ controller: AutomaticWeather) async {
        for _ in 0..<100 { if !controller.busy { return }; await Task.yield() }
        XCTAssertFalse(controller.busy)
    }
    func testBeijingDefaultMissingKeyAndOfflineNeverFetchOrSend() async {
        var device: String?, queries = 0, sends = 0
        let c = AutomaticWeather(defaults:defaults(),device:{device},isBusy:{false},readKey:{nil},
            fetch:{ _,_ in queries += 1; throw WeatherstackError.network },send:{ _,_ in sends += 1 })
        XCTAssertEqual(c.configuration.city,"Beijing, China")
        c.tick(); XCTAssertTrue(c.status.contains("认证连接"))
        device = "A"; c.tick(); await settle(c)
        XCTAssertTrue(c.status.contains("缺少 Weatherstack Key"))
        for _ in 0..<20 { c.tick() }
        XCTAssertEqual(queries,0); XCTAssertEqual(sends,0)
    }
    func testOnlyOncePerConnectionAndFreshCacheOnReconnect() async {
        var device: String? = "A", queries = 0, sends = 0
        let time = Date(), data = snapshot(Date())
        let c = AutomaticWeather(defaults:defaults(),device:{device},isBusy:{false},readKey:{"test-key"},
            fetch:{ city,_ in XCTAssertEqual(city,"Beijing, China"); queries += 1; return data },now:{time.addingTimeInterval(1)},
            send:{ value,icon in XCTAssertEqual(value.city,"Beijing"); XCTAssertEqual(icon,100); sends += 1 })
        c.confirmIcon(providerCode:122,firmwareCode:100); await settle(c)
        for _ in 0..<10 { c.tick() }; await settle(c)
        XCTAssertEqual(queries,1); XCTAssertEqual(sends,1)
        device = nil; c.tick(); device = "A"; c.tick(); await settle(c)
        XCTAssertEqual(queries,1); XCTAssertEqual(sends,2)
        XCTAssertTrue(c.status.contains("已提交")); XCTAssertTrue(c.status.contains("镜片仍需确认"))
    }
    func testUnknownIconDoesNotGuessAndExplicitMappingReusesResult() async {
        let data = snapshot(Date()); var sends = 0, queries = 0
        let c = AutomaticWeather(defaults:defaults(),device:{"A"},isBusy:{false},readKey:{"test-key"},
            fetch:{ _,_ in queries += 1; return data },send:{ _,_ in sends += 1 })
        c.tick(); await settle(c); XCTAssertEqual(sends,0); XCTAssertTrue(c.status.contains("尚未核对"))
        c.confirmIcon(providerCode:122,firmwareCode:100); await settle(c)
        XCTAssertEqual(sends,1); XCTAssertEqual(queries,1)
    }
    func testBusyDefersQueryAndSend() async {
        var occupied = true, sends = 0, queries = 0
        let data = snapshot(Date())
        let c = AutomaticWeather(defaults:defaults(),device:{"A"},isBusy:{occupied},readKey:{"test-key"},
            fetch:{ _,_ in queries += 1; occupied = true; return data },send:{ _,_ in sends += 1 })
        c.confirmIcon(providerCode:122,firmwareCode:100); XCTAssertEqual(queries,0)
        occupied = false; c.tick(); await settle(c); XCTAssertEqual(queries,1); XCTAssertEqual(sends,0)
        occupied = false; c.tick(); await settle(c); XCTAssertEqual(queries,1); XCTAssertEqual(sends,1)
    }
    func testOldResponseCannotSendAfterDisconnectOrDisable() async {
        for disable in [false,true] {
            var device: String? = "A", sends = 0
            var continuation: CheckedContinuation<WeatherstackSnapshot,Error>?
            let c = AutomaticWeather(defaults:defaults(),device:{device},isBusy:{false},readKey:{"test-key"},
                fetch:{ _,_ in try await withCheckedThrowingContinuation { continuation = $0 } },send:{ _,_ in sends += 1 })
            c.confirmIcon(providerCode:122,firmwareCode:100)
            for _ in 0..<100 { if continuation != nil { break }; await Task.yield() }
            let pending = try! XCTUnwrap(continuation)
            if disable { c.configure(city:"Beijing, China",enabled:false) } else { device = nil; c.tick() }
            pending.resume(returning:snapshot(Date()))
            for _ in 0..<20 { await Task.yield() }
            XCTAssertEqual(sends,0); XCTAssertNil(c.snapshot)
        }
    }
    func testSampleAndStaleResultsNeverSend() async {
        for data in [snapshot(Date(),sample:true), snapshot(Date().addingTimeInterval(-20_000))] {
            var sends = 0
            let c = AutomaticWeather(defaults:defaults(),device:{"A"},isBusy:{false},readKey:{"test-key"},
                fetch:{ _,_ in data },send:{ _,_ in sends += 1 })
            c.confirmIcon(providerCode:122,firmwareCode:100); await settle(c)
            XCTAssertEqual(sends,0); XCTAssertEqual(c.status,WeatherstackError.stale.localizedDescription)
        }
    }
    func testFailureDoesNotRetryEachPollAndReconnectIsRateLimited() async {
        var device: String? = "A", queries = 0, time = Date()
        let c = AutomaticWeather(defaults:defaults(),device:{device},isBusy:{false},readKey:{"test-key"},
            fetch:{ _,_ in queries += 1; throw WeatherstackError.network },now:{time},send:{ _,_ in XCTFail() })
        c.tick(); await settle(c)
        for _ in 0..<10 { c.tick() }; XCTAssertEqual(queries,1)
        device = nil; c.tick(); device = "A"; c.tick(); XCTAssertEqual(queries,1)
        time = time.addingTimeInterval(61); c.tick(); await settle(c); XCTAssertEqual(queries,2)
    }
    func testTransportThrowCannotBecomeSuccess() async {
        let data = snapshot(Date())
        let c = AutomaticWeather(defaults:defaults(),device:{"A"},isBusy:{false},readKey:{"test-key"},
            fetch:{ _,_ in data },send:{ _,_ in throw DeviceFeatureError.disconnected })
        c.confirmIcon(providerCode:122,firmwareCode:100); await settle(c)
        XCTAssertTrue(c.status.contains("下发失败")); XCTAssertFalse(c.status.contains("已提交"))
    }
    func testSavedCityAndSwitchRestoreWithoutSecretsOrAutomaticNetwork() {
        let storage = defaults()
        let c = AutomaticWeather(defaults:storage,device:{nil},isBusy:{false},readKey:{nil},send:{ _,_ in XCTFail() })
        c.configure(city:"London, UK",enabled:false); c.confirmIcon(providerCode:122,firmwareCode:100)
        let restored = AutomaticWeather(defaults:storage,device:{nil},isBusy:{false},readKey:{nil},send:{ _,_ in XCTFail() })
        XCTAssertEqual(restored.configuration.city,"London, UK"); XCTAssertFalse(restored.configuration.enabled)
        XCTAssertEqual(restored.configuration.icons["122"],100)
        c.configure(city:"fetch:ip",enabled:true); XCTAssertEqual(c.configuration.city,"London, UK")
        c.confirmIcon(providerCode:122,firmwareCode:1000); XCTAssertEqual(c.configuration.icons["122"],100)
    }
}
