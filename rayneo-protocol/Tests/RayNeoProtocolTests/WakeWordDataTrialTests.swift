import XCTest
@testable import RayNeoProtocol

final class WakeWordDataTrialTests: XCTestCase {
    func testCandidateChangesOnlyDataAndRestoresObservedPacket() throws {
        let body = Data(#"{"cmd":"set_ai_wakeup_word","payload":{"data":"Hey Norman","mode":1,"value":0}}"#.utf8)
        XCTAssertEqual(try WakeWordDataTrial.candidatePacket(), Data([8,1,16,16,26,UInt8(body.count)]) + body + Data([34,0]))
        XCTAssertEqual(try WakeWordDataTrial.restorePacket(), try LauncherControlPrototype.encode(.officialWakeWord))
    }

    func testSingleWriteExpiresIntoOneRestoreSubmission() throws {
        var trial = WakeWordDataTrial()
        XCTAssertEqual(try trial.begin(device: "fixture", now: 10), try WakeWordDataTrial.candidatePacket())
        XCTAssertEqual(trial.target, "fixture")
        XCTAssertTrue(trial.attempted)
        XCTAssertThrowsError(try trial.begin(device: "fixture", now: 11))
        XCTAssertNil(try trial.automaticRestore(device: "fixture", now: 129))
        XCTAssertEqual(try trial.automaticRestore(device: "fixture", now: 130), try WakeWordDataTrial.restorePacket())
        XCTAssertEqual(trial.phase, .restoreSubmitted)
        XCTAssertNil(try trial.automaticRestore(device: "fixture", now: 140))
        XCTAssertEqual(trial.target, "fixture", "Send success must not clear unverified recovery.")
    }

    func testRestartRecoversOnlySameTargetAndRequiresOwnerVerification() throws {
        var trial = WakeWordDataTrial(recoveryTarget: "fixture", attempted: true)
        XCTAssertThrowsError(try trial.begin(device: "fixture", now: 0))
        XCTAssertNil(try trial.automaticRestore(device: nil, now: 0))
        XCTAssertNil(try trial.automaticRestore(device: "other", now: 0))
        XCTAssertThrowsError(try trial.confirmRestored(device: "fixture"))
        XCTAssertNotNil(try trial.automaticRestore(device: "fixture", now: 0))
        XCTAssertThrowsError(try trial.confirmRestored(device: "other"))
        try trial.confirmRestored(device: "fixture")
        XCTAssertNil(trial.target)
        XCTAssertThrowsError(try trial.begin(device: "fixture", now: 10))
    }

    func testManualRecoveryDoesNotWaitForDeadlineOrSelectAnotherDevice() throws {
        var trial = WakeWordDataTrial()
        XCTAssertThrowsError(try trial.restore(device: "fixture"))
        _ = try trial.begin(device: "fixture", now: 10)
        XCTAssertThrowsError(try trial.restore(device: "other"))
        XCTAssertEqual(try trial.restore(device: "fixture"), try WakeWordDataTrial.restorePacket())
        XCTAssertNil(try trial.automaticRestore(device: "fixture", now: 200))
        XCTAssertEqual(try trial.restore(device: "fixture"), try WakeWordDataTrial.restorePacket(), "Owner may retry a failed restoration.")
    }

    func testFailedTrialSubmissionRequiresRecoveryWithoutRepeatingCandidate() throws {
        var trial = WakeWordDataTrial()
        _ = try trial.begin(device: "fixture", now: 0)
        trial.requireRecovery()
        XCTAssertNotNil(try trial.automaticRestore(device: "fixture", now: 1))
        XCTAssertNil(try trial.automaticRestore(device: "fixture", now: 2))
        XCTAssertThrowsError(try trial.begin(device: "fixture", now: 3))
    }

    func testInvalidClockAndTargetDoNotArmTrial() throws {
        var trial = WakeWordDataTrial()
        XCTAssertThrowsError(try trial.begin(device: "", now: 1))
        XCTAssertThrowsError(try trial.begin(device: "fixture", now: .nan))
        XCTAssertThrowsError(try trial.begin(device: "fixture", now: .infinity))
        XCTAssertFalse(trial.attempted)
        XCTAssertNil(trial.target)
    }
}
