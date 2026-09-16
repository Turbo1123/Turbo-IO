import XCTest
@testable import RayNeoProtocol

final class WakeDiagnosticTests: XCTestCase {
    private func packet(_ text: String, type: UInt8 = 1) -> Data {
        let body = Data(text.utf8)
        var count = body.count
        var length = Data()
        repeat {
            let byte = UInt8(count & 127); count >>= 7
            length.append(byte | (count > 0 ? 128 : 0))
        } while count > 0
        return Data([8, 1, 16, type, 26]) + length + body
    }

    func testMissingEmptyAndOpaqueMessagesRemainDistinct() throws {
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(Data([16,1]))).contains("message=missing"))
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(packet(""))).contains("message=empty"))
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(packet("private spoken words"))).contains("message=opaque"))
    }

    func testOnlySourceEnumAndKnownStructureAreVisible() throws {
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(packet(
            #"{"source":2,"payload":{"wakeType":1,"text":"private spoken words"},"private_field_name":"private value"}"#)))
        XCTAssertTrue(result.contains("source=2"))
        XCTAssertTrue(result.contains("payload.wakeType=1"))
        XCTAssertTrue(result.contains("unknownFields=2"))
        for secret in ["private", "spoken", "field_name"] { XCTAssertFalse(result.contains(secret)) }
    }

    func testStringsBooleansFractionsAndLargeValuesAreNotSourceEnums() throws {
        for value in ["true", "1.5", "-1", "256", "123456789", #""private-source""#] {
            let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(packet("{\"source\":\(value)}")))
            XCTAssertFalse(result.contains("source="), result)
            XCTAssertFalse(result.contains("private-source"))
        }
    }

    func testNeverInterpretsAudioOrOtherMessageTypes() throws {
        XCTAssertNil(try BusinessEnvelopeMetadata.wakeDiagnostic(packet(#"{"source":1}"#, type:3)))
        let wake = packet(#"{"source":1}"#) + Data([34,4,115,101,99,114])
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(wake))
        XCTAssertTrue(result.contains("audioBytes=4"))
        XCTAssertFalse(result.contains("secr"))
    }

    func testMalformedEnvelopeRejectedAndNonObjectJSONOpaque() throws {
        XCTAssertThrowsError(try BusinessEnvelopeMetadata.wakeDiagnostic(Data([16,1,26,5,1])))
        XCTAssertThrowsError(try BusinessEnvelopeMetadata.wakeDiagnostic(Data([16,1,16,1])))
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(packet("[1,2]"))).contains("message=opaque"))
    }

    func testResourceBoundsAndSlicedInput() throws {
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic(packet(String(repeating:"x",count:8193)))).contains("message=oversize"))
        let normal = packet(#"{"payload":{"data":{"payload":{"source":1}}}}"#)
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeDiagnostic((Data([0]) + normal).dropFirst()))
        XCTAssertLessThanOrEqual(result.count, 600)
        XCTAssertFalse(result.contains("source=1"))
    }

    func testSettingsExposeOnlyWakeControlsAndKnownPhrases() throws {
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet(
            #"{"generalSettings":{"voiceWakeup":true,"wakeupWord":"小雷小雷","aiWakeupWord":1,"deviceID":"private-id","private_key":"private-value"}}"#, type:4)))
        XCTAssertTrue(result.contains("generalSettings.voiceWakeup=true"))
        XCTAssertTrue(result.contains("generalSettings.wakeupWord=小雷小雷"))
        XCTAssertTrue(result.contains("generalSettings.aiWakeupWord=1"))
        XCTAssertFalse(result.contains("private"))
        XCTAssertFalse(result.contains("deviceID"))
        XCTAssertFalse(result.contains("supported=true"))
    }

    func testSettingsDecodeNestedDataWithoutExposingArbitraryText() throws {
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet(
            #"{"cmd":"set_ai_wakeup_word","rc":0,"payload":{"mode":1,"value":true,"data":"{\"wakeupWord\":\"private phrase\",\"voiceWakeup\":false}"}}"#, type:17)))
        for value in ["cmd=set_ai_wakeup_word", "rc=0", "payload.mode=1", "payload.value=true", "payload.data.voiceWakeup=false", "wakeupWord:string-redacted"] {
            XCTAssertTrue(result.contains(value), result)
        }
        XCTAssertFalse(result.contains("private"))
    }

    func testSettingsDoNotConfuseAbsentFieldsWithUnsupportedCapability() throws {
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet(#"{"battery":90,"brightness":7}"#, type:1)))
        XCTAssertTrue(result.contains("wakeFields=0"))
        XCTAssertTrue(result.contains("unknownFields=2"))
        XCTAssertFalse(result.contains("battery"))
        XCTAssertFalse(result.contains("unsupported"))
        XCTAssertNil(try BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet("{}", type:25)))
    }

    func testSettingsNeverPrintUnknownCommandsUnboundedNumbersOrAudio() throws {
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet(
            #"{"cmd":"private-command","payload":{"mode":123456789},"wakeWord":"private-word","voiceWakeup":999999}"#, type:4) + Data([34,4,115,101,99,114])))
        for value in ["private", "123456789", "999999", "secr"] { XCTAssertFalse(result.contains(value), result) }
        XCTAssertFalse(result.contains("payload.mode"))
    }

    func testSettingsBoundsMissingOpaqueAndMalformed() throws {
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic(Data([8,1,16,4]))).contains("message=missing"))
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet("[]", type:4))).contains("message=opaque"))
        XCTAssertTrue(try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic(packet(String(repeating:"x",count:8193), type:4))).contains("message=oversize"))
        XCTAssertThrowsError(try BusinessEnvelopeMetadata.wakeSettingsDiagnostic(Data([8,1,16,4,26,5,1])))
        let normal = packet(#"{"payload":{"data":{"data":{"data":{"wakeWord":"Hey Norman"}}}}}"#, type:4)
        let result = try XCTUnwrap(BusinessEnvelopeMetadata.wakeSettingsDiagnostic((Data([0]) + normal).dropFirst()))
        XCTAssertFalse(result.contains("Hey Norman"))
        XCTAssertLessThanOrEqual(result.count, 900)
    }
}
