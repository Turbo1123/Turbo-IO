import XCTest
@testable import RayNeoCompanion

final class WeatherstackTests: XCTestCase {
    private let now = Date(timeIntervalSince1970:1_800_000_000)
    private func fixture(_ mutate: (inout [String:Any]) -> Void = { _ in }) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with:WeatherstackCodec.historicalSample) as? [String:Any])
        mutate(&value)
        return try JSONSerialization.data(withJSONObject:value)
    }
    func testUserHistoricalSampleDecodesButCannotSend() throws {
        let sample = try WeatherstackCodec.decode(WeatherstackCodec.historicalSample,fetchedAt:now,sample:true)
        XCTAssertEqual(sample.city,"San Francisco"); XCTAssertEqual(sample.celsius,16)
        XCTAssertEqual(sample.providerCode,122); XCTAssertEqual(sample.description,"Overcast")
        XCTAssertTrue(sample.usedLegacyTemperatureKey); XCTAssertFalse(sample.canSend(at:now))
        XCTAssertEqual(sample.sourceDate,sample.observedAt)
        // It is also stale even if returned by a live endpoint today.
        XCTAssertFalse(try WeatherstackCodec.decode(WeatherstackCodec.historicalSample,fetchedAt:now).canSend(at:now))
    }
    func testStandardTemperatureWinsAndRoundsOnlyAtLensBoundary() throws {
        let bytes = try fixture { value in
            var current = value["current"] as! [String:Any]; current["temperature"] = 15.6; value["current"] = current
        }
        let parsed = try WeatherstackCodec.decode(bytes)
        XCTAssertEqual(parsed.celsius,15.6); XCTAssertEqual(parsed.lensTemperature,16)
        XCTAssertFalse(parsed.usedLegacyTemperatureKey)
    }
    func testNeverTreatsBoolMissingOrOutOfRangeTemperatureAsZero() throws {
        for temperature in [true, "16", 90] as [Any] {
            let bytes = try fixture { value in
                var current = value["current"] as! [String:Any]; current["temperature"] = temperature; value["current"] = current
            }
            XCTAssertThrowsError(try WeatherstackCodec.decode(bytes))
        }
        let missing = try fixture { value in
            var current = value["current"] as! [String:Any]; current.removeValue(forKey:"temparature"); value["current"] = current
        }
        XCTAssertThrowsError(try WeatherstackCodec.decode(missing))
    }
    func testFahrenheitAndKelvinAreRejectedNotReinterpreted() throws {
        for unit in ["f","s",""] {
            let bytes = try fixture { $0["request"] = ["unit":unit] }
            XCTAssertThrowsError(try WeatherstackCodec.decode(bytes)) { XCTAssertEqual($0 as? WeatherstackError,.unit) }
        }
    }
    func testFreshnessUsesTimezoneNotLocaltimeEpochAndRejectsMissingZone() throws {
        let bytes = try fixture { value in
            value["location"] = ["name":"Beijing","country":"China","timezone_id":"Asia/Shanghai","localtime":"2026-09-08 08:10","localtime_epoch":0]
            value["current"] = ["temperature":27,"weather_code":122,"weather_descriptions":["Overcast"],"observation_time":"12:00 AM"]
        }
        let clock = ISO8601DateFormatter().date(from:"2026-09-08T00:10:00Z")!
        let parsed = try WeatherstackCodec.decode(bytes,fetchedAt:clock)
        XCTAssertEqual(parsed.sourceDate,clock); XCTAssertTrue(parsed.canSend(at:clock))
        XCTAssertFalse(parsed.canSend(at:clock.addingTimeInterval(1_801)))
        XCTAssertFalse(parsed.canSend(at:clock.addingTimeInterval(-1)))
        let missingZone = try fixture { value in value["location"] = ["name":"Beijing","country":"China","localtime":"2026-09-08 08:10"] }
        XCTAssertNil(try WeatherstackCodec.decode(missingZone).sourceDate)
    }
    func testUTCObservationCanBelongToPreviousDay() throws {
        let clock = ISO8601DateFormatter().date(from:"2026-09-08T00:10:00Z")!
        let bytes = try fixture { value in
            value["location"] = ["name":"Beijing","country":"China","timezone_id":"Asia/Shanghai","localtime":"2026-09-08 08:10"]
            value["current"] = ["temperature":27,"weather_code":122,"weather_descriptions":["Overcast"],"observation_time":"11:50 PM"]
        }
        let parsed = try WeatherstackCodec.decode(bytes,fetchedAt:clock)
        XCTAssertEqual(parsed.observedAt,clock.addingTimeInterval(-1_200)); XCTAssertTrue(parsed.canSend(at:clock))
    }
    func testRemoteErrorsNeverExposeServerTextOrCredentialURL() {
        let bytes = Data(#"{"success":false,"error":{"code":101,"info":"https://api.weatherstack.com/current?access_key=DO-NOT-ECHO","type":"secret"}}"#.utf8)
        XCTAssertThrowsError(try WeatherstackCodec.decode(bytes)) {
            XCTAssertEqual($0 as? WeatherstackError,.remote(101))
            XCTAssertFalse($0.localizedDescription.contains("DO-NOT-ECHO")); XCTAssertFalse($0.localizedDescription.contains("https"))
        }
    }
    func testBoundedPayloadAndMalformedJSON() {
        XCTAssertThrowsError(try WeatherstackCodec.decode(Data(repeating:32,count:WeatherstackCodec.limit+1))) {
            XCTAssertEqual($0 as? WeatherstackError,.oversized)
        }
        XCTAssertThrowsError(try WeatherstackCodec.decode(Data("not-json".utf8)))
    }
    func testRequestUsesPinnedHTTPSAndEncodedSingleCityCelsius() throws {
        let request = try WeatherstackRequest.make(city:"San Francisco, USA & test",key:"synthetic-test-key")
        let url = try XCTUnwrap(request.url); let parts = try XCTUnwrap(URLComponents(url:url,resolvingAgainstBaseURL:false))
        XCTAssertEqual(parts.scheme,"https"); XCTAssertEqual(parts.host,"api.weatherstack.com"); XCTAssertEqual(parts.path,"/current")
        XCTAssertEqual(parts.queryItems?.first(where:{$0.name == "query"})?.value,"San Francisco, USA & test")
        XCTAssertEqual(parts.queryItems?.first(where:{$0.name == "units"})?.value,"m")
        XCTAssertEqual(parts.queryItems?.count,3); XCTAssertEqual(request.cachePolicy,.reloadIgnoringLocalCacheData)
    }
    func testEmptyKeyBatchAndIPLookupRejected() {
        for city in ["", "fetch:ip", "city;city", "a\nb", String(repeating:"x",count:161)] {
            XCTAssertThrowsError(try WeatherstackRequest.make(city:city,key:"synthetic-test-key"))
        }
        XCTAssertThrowsError(try WeatherstackRequest.make(city:"Beijing",key:""))
        XCTAssertThrowsError(try WeatherstackRequest.make(city:"Beijing",key:"secret\nheader"))
    }
    @MainActor func testNoKeyDoesNotCallNetwork() async {
        var calls = 0
        let controller = WeatherstackController(fetch:{ _,_ in calls += 1; throw WeatherstackError.network },readKey:{nil})
        await controller.refresh(city:"Beijing")
        XCTAssertEqual(calls,0); XCTAssertFalse(controller.busy); XCTAssertNil(controller.snapshot)
    }
    @MainActor func testControllerPreviewAndNetworkFailureRemainHonest() async {
        let controller = WeatherstackController(fetch:{ _,_ in throw URLError(.badURL,userInfo:[NSURLErrorKey:"synthetic-secret"]) },readKey:{"synthetic-test-key"})
        controller.previewSample(); XCTAssertEqual(controller.snapshot?.isSample,true)
        await controller.refresh(city:"Beijing")
        XCTAssertNil(controller.snapshot); XCTAssertFalse(controller.busy)
        XCTAssertFalse(controller.message.contains("synthetic-secret")); XCTAssertTrue(controller.message.contains("请求失败"))
    }
    @MainActor func testHistoricalSnapshotCannotReachLensSender() throws {
        let store = CompanionStore()
        let sample = try WeatherstackCodec.decode(WeatherstackCodec.historicalSample,sample:true)
        store.features.sendWeatherstack(sample,icon:100)
        XCTAssertEqual(store.features.error,WeatherstackError.stale.localizedDescription)
    }
}
