import Foundation
import RayNeoDisplay
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A fixed local integration demonstration. No arguments become payload data;
/// there are no transports, accounts, microphone permissions, or tool adapters.
@main
struct DisplayDemo {
    enum DemoError: Error {
        case unexpectedDecodedCase
        case invalidSyntheticFixture
    }

    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] || arguments == ["-h"] {
            print("rayneo-display-demo: fixed synthetic local JSON report; no network, device, or tool execution. Usage: rayneo-display-demo [--help]")
            return
        }
        guard arguments.isEmpty else {
            writeError("unsupported_arguments")
            exit(2)
        }
        do {
            let report: [String: Any] = [
                "schemaVersion": 1,
                "evidence": "synthetic_local_integration_only",
                "mode": "offline_no_transport",
                "safety": [
                    "deviceRequests": 0, "networkRequests": 0, "toolsExecuted": 0,
                    "automaticApproval": false, "lensDisplayVerified": false,
                    "physicalGestureVerified": false
                ],
                "textOffsets": try textOffsets(),
                "progress": try progress(),
                "todos": try todos(),
                "suggestions": try suggestions(),
                "boundaries": [
                    "JSON encoding is not transport submission.",
                    "Transport submission and ACK are not applied state or lens verification.",
                    "Progress sequence is local, not a wire field.",
                    "Todo plans do not write or create tasks; raw time has no inferred unit.",
                    "Parsed accept is not tool authorization; no pending-request registry or executor is attached.",
                    "Suggestion type 33 is encoded from confirmed static fields; no card display is verified."
                ]
            ]
            var output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            output.append(0x0A)
            FileHandle.standardOutput.write(output)
        } catch {
            // Fixed status only: never print arbitrary error/payload contents.
            writeError("synthetic_demo_failed")
            exit(1)
        }
    }

    private static func writeError(_ code: String) {
        FileHandle.standardError.write(Data("{\"error\":\"\(code)\",\"deviceRequests\":0,\"toolsExecuted\":0}\n".utf8))
    }

    static func textOffsets() throws -> [String: Any] {
        let input = "A中🙂B\r\n"
        let preserved = try TextOffsetMap(input)
        let normalized = try TextOffsetMap(input, newlinePolicy: .normalizeToLF)
        var rejected: [[String: Any]] = []
        do {
            _ = try normalized.utf8Offset(forUTF16Offset: 3)
            throw DemoError.invalidSyntheticFixture
        } catch TextOffsetMap.OffsetError.insideUTF16SurrogatePair {
            rejected.append(["coordinate": "utf16", "offset": 3, "reason": "inside_surrogate_pair"])
        }
        do {
            _ = try normalized.utf16Offset(forUTF8Offset: 5)
            throw DemoError.invalidSyntheticFixture
        } catch TextOffsetMap.OffsetError.insideUTF8Scalar {
            rejected.append(["coordinate": "utf8", "offset": 5, "reason": "inside_multibyte_scalar"])
        }
        return [
            "input": input,
            "normalization": "explicit_CRLF_CR_to_LF",
            "normalizedText": normalized.text,
            "preservedCounts": ["utf16": preserved.utf16Count, "utf8": preserved.utf8Count],
            "normalizedCounts": ["utf16": normalized.utf16Count, "utf8": normalized.utf8Count],
            "scalarBoundaries": zip(normalized.scalarUTF16Boundaries, normalized.scalarUTF8Boundaries).map {
                ["utf16": $0.0, "utf8": $0.1]
            },
            "validConversion": ["utf16": 4, "utf8": try normalized.utf8Offset(forUTF16Offset: 4)],
            "rejectedInteriorOffsets": rejected,
            "isPixelOrGlyphLayout": false
        ]
    }

    static func progress() throws -> [String: Any] {
        let codec = TeleprompterJSONCodec()
        let did = "synthetic-did-01"
        var tracker = try TeleprompterProgressTracker(did: did, connectionGeneration: 7)
        var events: [[String: Any]] = []

        func observed(_ identifier: String, page: Int64, highlight: Int64) throws -> TeleprompterPositionObserved {
            // Encode a fixed App request only as a local schema fixture. Reuse its
            // known symmetric progress shape to exercise glasses-request decoding.
            let fixture = try codec.encodeAppRequest(.progress(
                did: identifier, pageOffset: page, highLightOffset: highlight, autoSync: false
            ))
            guard case .progress(let result) = try codec.decodeGlassesRequest(type: fixture.type, payload: fixture.payload)
            else { throw DemoError.unexpectedDecodedCase }
            return result
        }

        let first = try observed(did, page: 0, highlight: 4)
        events.append(["case": "same_did_current_generation", "result": progressResult(tracker.observe(first, connectionGeneration: 7))])
        events.append(["case": "duplicate_position", "result": progressResult(tracker.observe(first, connectionGeneration: 7))])

        let wrong = try observed("synthetic-old-did", page: 4, highlight: 8)
        let explicitAck = try codec.encodeAppResponse(type: .progress, did: wrong.did, code: .accepted)
        // Intentionally demonstrate that even a code 1 ACK does not authorize
        // this wrong-DID observation to update the active tracker.
        events.append([
            "case": "wrong_did_despite_explicit_code_1_ack",
            "ack": ["type": explicitAck.type, "code": 1, "encodedOnly": true, "sent": false],
            "result": progressResult(tracker.observe(wrong, connectionGeneration: 7))
        ])
        events.append([
            "case": "old_generation_same_did",
            "result": progressResult(tracker.observe(try observed(did, page: 4, highlight: 8), connectionGeneration: 6))
        ])
        return [
            "fixtureOrigin": "hardcoded_synthetic_JSON_not_captured_glasses_traffic",
            "events": events,
            "finalLocalSequence": tracker.localSequence,
            "finalObservedPosition": [
                "pageOffset": tracker.position?.pageOffset ?? -1,
                "highLightOffset": tracker.position?.highLightOffset ?? -1
            ],
            "lensState": "not_verified"
        ]
    }

    static func progressResult(_ result: TeleprompterProgressTracker.Result) -> [String: Any] {
        switch result {
        case .staleConnection: return ["state": "stale_connection_ignored"]
        case .differentDocument: return ["state": "different_document_ignored"]
        case .duplicate: return ["state": "duplicate_ignored"]
        case .sequenceExhausted: return ["state": "local_sequence_exhausted"]
        case .updated(let sequence): return ["state": "local_observation_updated", "localSequence": sequence]
        }
    }

    static func todos() throws -> [String: Any] {
        let codec = TodoJSONCodec()
        let payload = Data(#"{"eventID":101,"status":1,"isImportant":null,"lastModifiedTime":123456789}"#.utf8)
        guard case .status(let observed) = try codec.decodeGlassesMessage(type: 4, payload: payload)
        else { throw DemoError.unexpectedDecodedCase }
        let existing = TodoImmediateUpdatePlanner.ExistingTask(eventID: 101, completed: false, important: true)
        let known = TodoImmediateUpdatePlanner.plan(observed, existing: existing)
        let unknown = TodoImmediateUpdatePlanner.plan(observed, existing: nil)
        let repeated = TodoImmediateUpdatePlanner.plan(observed, existing: .init(eventID: 101, completed: true, important: true))
        return [
            "fixtureOrigin": "hardcoded_synthetic_status",
            "knownExistingTask": todoPlan(known),
            "unknownTask": todoPlan(unknown),
            "alreadyCompletedTask": todoPlan(repeated),
            "rawLastModifiedTime": observed.lastModifiedTime.rawValue,
            "timeUnit": "unverified_not_converted",
            "tasksCreated": 0,
            "persistenceWrites": 0
        ]
    }

    static func todoPlan(_ plan: TodoImmediateUpdatePlanner.Plan) -> [String: Any] {
        switch plan {
        case .unknownTask: return ["state": "unknown_task_rejected_no_creation"]
        case .noChange: return ["state": "no_change"]
        case .update(let changes):
            return [
                "state": "local_plan_only",
                "completed": changes.completed.map { $0 as Any } ?? NSNull(),
                "important": changes.important.map { $0 as Any } ?? NSNull(),
                "requiresEchoSuppressionByHost": changes.shouldSuppressImmediateEcho,
                "persisted": false
            ]
        }
    }

    static func suggestions() throws -> [String: Any] {
        let codec = SuggestionJSONCodec()
        let cards = SuggestionCardJSONCodec()
        let fixtures: [(String, SuggestionCardAppRequest)] = [
            ("synthetic_todo_add", .add(
                suggestUID: "synthetic-request-01", suggestType: .todo,
                title: "本地确认测试", source: "独立 App", content: "仅测试结构，不执行工具", timeRange: nil
            )),
            ("synthetic_calendar_add", .add(
                suggestUID: "synthetic-calendar-01", suggestType: .calendar,
                title: "本地时间展示测试", source: "独立 App", content: "合成日程，不写系统日历",
                timeRange: "09:00–10:00"
            )),
            ("synthetic_todo_delete", .delete(suggestUID: "synthetic-request-01", suggestType: .todo))
        ]
        var outboundCards: [[String: Any]] = []
        for (purpose, request) in fixtures {
            let encoded = try cards.encodeAppRequest(request)
            guard let object = try JSONSerialization.jsonObject(with: encoded.payload) as? [String: Any]
            else { throw DemoError.invalidSyntheticFixture }
            outboundCards.append([
                "purpose": purpose, "businessLocalType": encoded.type, "syntheticPayload": object,
                "encodedOnly": true, "sent": false, "lensDisplayed": false
            ])
        }
        do {
            _ = try SuggestionCardCategory(validatingRawValue: 99)
            throw DemoError.invalidSyntheticFixture
        } catch SuggestionCardEncodingError.unsupportedSuggestType(99) {
            // The fixed unknown category never becomes a guessed card type.
        }
        var events: [[String: Any]] = []
        for (raw, expected) in [(1, "accept_observed_not_authorized"), (2, "reject_observed")] {
            let fixture = Data("{\"suggestUID\":\"synthetic-request-01\",\"suggestType\":1,\"cmd\":\(raw)}".utf8)
            guard case .operation(let observed) = try codec.decodeGlassesOperation(type: 34, payload: fixture)
            else { throw DemoError.unexpectedDecodedCase }
            let actual: String
            switch observed.command {
            case .accept: actual = "accept_observed_not_authorized"
            case .reject: actual = "reject_observed"
            case .unknown: throw DemoError.invalidSyntheticFixture
            }
            guard actual == expected else { throw DemoError.invalidSyntheticFixture }
            // There is no pending-request registry or real operation here. The
            // explicit ACK is therefore failure, not fabricated success.
            let ack = try codec.encodeAppAcknowledgement(
                suggestUID: observed.suggestUID, suggestType: observed.suggestType, code: .otherFailure
            )
            events.append([
                "rawCommand": raw, "state": actual, "toolAuthorized": false,
                "explicitAck": [
                    "type": ack.type, "code": SuggestionAcknowledgementCode.otherFailure.rawValue,
                    "reason": "demo_has_no_bound_pending_request_or_executor",
                    "encodedOnly": true, "sent": false
                ]
            ])
        }

        let unknownFixture = Data(#"{"suggestUID":"synthetic-request-01","suggestType":1,"cmd":99}"#.utf8)
        do {
            _ = try codec.decodeGlassesOperation(type: 34, payload: unknownFixture)
            throw DemoError.invalidSyntheticFixture
        } catch DisplayPayloadError.unknownCommand(99) {
            events.append(["rawCommand": 99, "state": "unknown_command_rejected", "ackEncoded": false, "toolAuthorized": false])
        }
        let retaining = SuggestionJSONCodec(unknownCommandPolicy: .retainUnknown)
        guard case .operation(let rawObservation) = try retaining.decodeGlassesOperation(type: 34, payload: unknownFixture),
              rawObservation.command == .unknown(99) else { throw DemoError.invalidSyntheticFixture }
        return [
            "fixtureOrigin": "hardcoded_synthetic_operations_no_physical_gesture",
            "outboundCards": outboundCards,
            "unknownSuggestionType": ["rawValue": 99, "state": "unsupported_category_rejected"],
            "events": events,
            "explicitRetainUnknownPolicy": ["state": "unknown_retained_never_accept", "rawCommand": 99],
            "pendingRequestRegistryAttached": false,
            "executorAttached": false,
            "toolsExecuted": 0,
            "headGestureVerified": false,
            "type33SuggestionDisplay": "encoded_only_not_verified"
        ]
    }
}
