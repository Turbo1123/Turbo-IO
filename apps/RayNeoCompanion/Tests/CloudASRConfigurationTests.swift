import XCTest
@testable import RayNeoCompanion

final class CloudASRConfigurationTests: XCTestCase {
    func testHostIsExplicitAndScopedWithoutDefaultTenant() throws {
        let suite = "turboio-host-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(CloudASRHostSettings.current(defaults: defaults), "")
        XCTAssertTrue(CloudASRHostSettings.save(" TENANT.EXAMPLE.ALIYUNCS.COM ", defaults: defaults))
        XCTAssertEqual(CloudASRHostSettings.current(defaults: defaults), "tenant.example.aliyuncs.com")
        XCTAssertNotEqual(CloudASRHostSettings.service(for: "first.example.aliyuncs.com"), CloudASRHostSettings.service(for: "second.example.aliyuncs.com"))
        XCTAssertFalse(CloudASRHostSettings.save("https://bad.example.aliyuncs.com", defaults: defaults))
        XCTAssertEqual(CloudASRHostSettings.current(defaults: defaults), "tenant.example.aliyuncs.com")
    }
    func testHostRejectsURLsCredentialsPortsAndUnrelatedOrigins() {
        for value in ["", "example.com", "127.0.0.1", "a.aliyuncs.com.evil.com", "a.aliyuncs.com:443", "user@a.aliyuncs.com", "a.aliyuncs.com/path", "a.aliyuncs.com?key=x", "a..aliyuncs.com", "-a.aliyuncs.com", "a-.aliyuncs.com", "a\n.aliyuncs.com"] {
            XCTAssertNil(CloudASRHostSettings.normalize(value), value)
        }
    }
}
