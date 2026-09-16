# Native Teleprompter Follow Trial Implementation Plan

> **For agentic workers:** Execute inline in this existing feature checkout. The workspace contains unrelated user work; stage only files named by this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user explicitly request a trial of the glasses' native speech-following teleprompter while keeping constant-speed mode intact.

**Architecture:** An app-local mode type constructs the preparation JSON; `scroll=1` is a trial candidate, whereas the existing constant-speed request stays `scroll=2`. `CompanionDeviceFeatures` records the requested mode for one session and bypasses JSON parsing for inbound type-9 teleprompter audio. The UI labels the mode as unverified and requires exit/reprepare to change it.

**Tech Stack:** Swift 5, SwiftUI, XCTest, XcodeGen, RayNeo business envelope metadata.

---

### Task 1: Preparation and inbound filtering

**Files:**
- Create: `apps/RayNeoCompanion/Sources/GlassesPrompterMode.swift`
- Create: `apps/RayNeoCompanion/Tests/GlassesPrompterModeTests.swift`
- Modify: `apps/RayNeoCompanion/Sources/CompanionDeviceFeatures.swift`

- [ ] **Step 1: Write failing tests.** Add these independent XCTest cases (with `import XCTest` and `@testable import RayNeoCompanion`):

```swift
func testPreparationModesPreservePayloadAndOnlyChangeScroll() {
    let fixed = GlassesPrompterMode.constantSpeed.preparationPayload(did: "d", total: 3, speed: 120)
    let follow = GlassesPrompterMode.nativeFollowTrial.preparationPayload(did: "d", total: 3, speed: 120)
    XCTAssertEqual(fixed["scroll"] as? Int, 2)
    XCTAssertEqual(follow["scroll"] as? Int, 1)
    for key in ["action", "did", "total", "speed", "pageOffset", "highLightOffset"] {
        XCTAssertEqual(String(describing: fixed[key]), String(describing: follow[key]))
    }
}
func testOpaqueTeleprompterAudioIsFilteredBeforeJSONParsing() {
    let packet = Data([8, 1, 16, 9, 26, 3, 255, 254, 253])
    XCTAssertTrue(GlassesPrompterMode.isOpaqueAudio(business: 20, packet: packet))
    XCTAssertFalse(GlassesPrompterMode.isOpaqueAudio(business: 14, packet: packet))
}
```

- [ ] **Step 2: Verify red.** Generate the source-only project with `xcodegen generate --no-env --quiet --spec artifacts/localization/simulator-staging.json --project-root apps/RayNeoCompanion --project artifacts/localization/simulator-project`; run `xcodebuild -quiet -project artifacts/localization/simulator-project/RayNeoCompanion.xcodeproj -scheme RayNeoCompanion -destination 'platform=iOS Simulator,id=D37948C5-01C2-489A-9F5E-C31A9F988840' -derivedDataPath artifacts/localization/simulator-build -parallel-testing-enabled NO test -only-testing:RayNeoCompanionTests/GlassesPrompterModeTests`. Expect missing-type compilation errors.
- [ ] **Step 3: Implement minimal app-local type.** Add `enum GlassesPrompterMode: String, CaseIterable { case constantSpeed, nativeFollowTrial }`, `preparationPayload(did:total:speed:) -> [String: Any]`, and `static func isOpaqueAudio(business: UInt8, packet: Data) -> Bool` using `BusinessEnvelopeMetadata.inspect(packet)` for type 9. Build the payload with `["action":1,"did":did,"total":total,"scroll":self == .constantSpeed ? 2 : 1,"speed":speed,"pageOffset":0,"highLightOffset":0]`.
- [ ] **Step 4: Verify green.** Regenerate and rerun focused XCTest; then connect `prepareTeleprompter(..., mode: .constantSpeed)` to the builder, record the mode in published session state, and reset it when the session stops. Before `DeviceBusinessWire(data)`, return early for opaque type-9 audio. Keep existing readiness, size and connection checks.

### Task 2: Mode controls and honest status

**Files:**
- Modify: `apps/RayNeoCompanion/Sources/DeviceFeatureViews.swift`
- Modify: `apps/RayNeoCompanion/Sources/CompanionDeviceFeatures.swift`
- Modify: `apps/RayNeoCompanion/Sources/App/Localization/LocalizedStatus.swift`
- Modify: `apps/RayNeoCompanion/Resources/Localizable.xcstrings`
- Test: `apps/RayNeoCompanion/Tests/GlassesPrompterModeTests.swift`

- [ ] **Step 1: Write a failing test.** Add `XCTAssertTrue(GlassesPrompterMode.constantSpeed.canAdjustSpeed)` and `XCTAssertFalse(GlassesPrompterMode.nativeFollowTrial.canAdjustSpeed)` in a dedicated test method.
- [ ] **Step 2: Verify red.** Rerun the focused XCTest and confirm `canAdjustSpeed` is missing.
- [ ] **Step 3: Implement minimal behavior.** Add a two-option picker before preparation; hide speed slider and apply-speed control for native trial; disable switching the picker while a document is active; include a user-facing note about microphone/network/fee uncertainty and a confirmation dialog. Display the requested mode separately from ACK status; never call an ACK proof of speech tracking. Guard type-7 speed change to the constant-speed session. Localize new copy in both languages and new status keys in `LocalizedStatus`.
- [ ] **Step 4: Verify green and build.** Run focused XCTest, localization checks, then build the simulator app. Review the diff for any accidental changes to signing, pairing, generated projects, vendor binaries or credentials.

### Task 3: Manual hardware acceptance

**Files:** none

- [ ] **Step 1: Install only after simulator verification using the existing isolated device staging, preserving the current bundle ID and pairing state.**
- [ ] **Step 2: Ask the user to read a short script, pause, vary pace, exit, and confirm the original fixed-speed mode still works.** Only after these observations may the trial label be changed to a verified feature in a later task.
