import XCTest
@testable import RayNeoCompanion

final class GlassesPrompterModeTests: XCTestCase {
    func testPreparationModesPreservePayloadAndOnlyChangeScroll() {
        let fixed = GlassesPrompterMode.constantSpeed.preparationPayload(did: "d", total: 3, speed: 120)
        let follow = GlassesPrompterMode.nativeFollowTrial.preparationPayload(did: "d", total: 3, speed: 120)

        XCTAssertEqual(fixed["scroll"] as? Int, 2)
        XCTAssertEqual(follow["scroll"] as? Int, 1)
        XCTAssertEqual(fixed["action"] as? Int, 1)
        XCTAssertEqual(fixed["did"] as? String, "d")
        XCTAssertEqual(fixed["total"] as? Int, 3)
        XCTAssertEqual(fixed["speed"] as? Int, 120)
        XCTAssertEqual(fixed["pageOffset"] as? Int, 0)
        XCTAssertEqual(fixed["highLightOffset"] as? Int, 0)
        for key in ["action", "did", "total", "speed", "pageOffset", "highLightOffset"] {
            XCTAssertEqual(String(describing: fixed[key]), String(describing: follow[key]), key)
        }
    }

    func testOpaqueTeleprompterAudioIsFilteredBeforeJSONParsing() {
        let packet = Data([8, 1, 16, 9, 26, 3, 255, 254, 253])
        XCTAssertTrue(GlassesPrompterMode.isOpaqueAudio(business: 20, packet: packet))
        XCTAssertFalse(GlassesPrompterMode.isOpaqueAudio(business: 14, packet: packet))
        XCTAssertFalse(GlassesPrompterMode.isOpaqueAudio(business: 20, packet: Data([8, 1, 16, 8])))
        XCTAssertFalse(GlassesPrompterMode.isOpaqueAudio(business: 20, packet: Data([255])))
    }

    func testOnlyConstantSpeedModeCanChangeItsScrollSpeed() {
        XCTAssertTrue(GlassesPrompterMode.constantSpeed.canAdjustSpeed)
        XCTAssertFalse(GlassesPrompterMode.nativeFollowTrial.canAdjustSpeed)
    }
}
