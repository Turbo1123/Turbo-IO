import Foundation
import RayNeoSession

/// Semantic commands only. A concrete transport owns serialization, authentication and acknowledgements.
public enum GlassesSessionCommand: Equatable, Sendable {
    case startCapture(round: RoundToken)
    case stopCapture(round: RoundToken)
    case transcript(round: RoundToken, text: String, isFinal: Bool)
    case response(round: RoundToken, text: String, isFinal: Bool)
    case ttsStatus(round: RoundToken, status: TTSStatus)
    case responseComplete(round: RoundToken)
    case exit(round: RoundToken, reason: SessionExitReason)
    case showApproval(ApprovalPresentation)
    case startApprovalCapture(ApprovalCaptureToken)
    case stopApprovalCapture(ApprovalCaptureToken)

    public var round: RoundToken {
        switch self {
        case let .startCapture(round), let .stopCapture(round), let .responseComplete(round): return round
        case let .transcript(round, _, _), let .response(round, _, _), let .ttsStatus(round, _), let .exit(round, _): return round
        case let .showApproval(presentation): return presentation.binding.context.originRound
        case let .startApprovalCapture(capture), let .stopApprovalCapture(capture): return capture.binding.context.originRound
        }
    }
}

public protocol GlassesSessionTransport: Sendable {
    /// Return after bounded admission/send processing. A normal return is NOT a glasses execution ACK.
    /// Must honor task cancellation; a noncooperative writer can send after a timeout despite this runtime.
    func send(_ command: GlassesSessionCommand) async throws
}

public protocol SessionRuntimeClock: Sendable {
    func sleep(nanoseconds: UInt64) async throws
}

public struct SystemSessionRuntimeClock: SessionRuntimeClock {
    public init() {}
    public func sleep(nanoseconds: UInt64) async throws { try await Task.sleep(nanoseconds: nanoseconds) }
}

public struct SessionRuntimeDependencies: Sendable {
    public let localASR: (any ASRProvider)?
    public let cloudASR: (any ASRProvider)?
    public let model: any ConversationModelProvider
    public let synthesis: (any SpeechSynthesisProvider)?
    public let playback: (any SpeechPlaybackAdapter)?
    public let transport: any GlassesSessionTransport
    public let clock: any SessionRuntimeClock
    public let wallTime: @Sendable () -> Date
    public let localApprovalASR: (any ApprovalASRProvider)?
    public let cloudApprovalASR: (any ApprovalASRProvider)?

    /// Explicit dependencies: no default endpoint, credentials, recognizer, audio session or transport.
    public init(localASR: (any ASRProvider)? = nil, cloudASR: (any ASRProvider)? = nil,
                model: any ConversationModelProvider, synthesis: (any SpeechSynthesisProvider)? = nil,
                playback: (any SpeechPlaybackAdapter)? = nil, transport: any GlassesSessionTransport,
                clock: any SessionRuntimeClock = SystemSessionRuntimeClock(),
                wallTime: @escaping @Sendable () -> Date = { Date() },
                localApprovalASR: (any ApprovalASRProvider)? = nil, cloudApprovalASR: (any ApprovalASRProvider)? = nil) {
        self.localASR = localASR; self.cloudASR = cloudASR; self.model = model
        self.synthesis = synthesis; self.playback = playback; self.transport = transport; self.clock = clock
        self.wallTime = wallTime
        self.localApprovalASR = localApprovalASR; self.cloudApprovalASR = cloudApprovalASR
    }
}

public struct SessionRuntimeConfiguration: Equatable, Sendable {
    public let session: VoiceSessionConfiguration
    public let audioBufferChunks: Int
    public let transportQueueCommands: Int
    public let transportTimeoutMilliseconds: UInt64
    public let maximumCleanupTasks: Int
    public let maximumPendingClockTasks: Int
    public let observationBufferUpdates: Int
    public let approvalCapacity: Int
    public let approval: ApprovalSubsessionConfiguration
    public let approvalHandoffTimeoutMilliseconds: UInt64

    public init(session: VoiceSessionConfiguration = .init(), audioBufferChunks: Int = 32,
                transportQueueCommands: Int = 64, transportTimeoutMilliseconds: UInt64 = 5_000,
                maximumCleanupTasks: Int = 32, maximumPendingClockTasks: Int = 64,
                observationBufferUpdates: Int = 32, approvalCapacity: Int = 1_024,
                approval: ApprovalSubsessionConfiguration = .init(), approvalHandoffTimeoutMilliseconds: UInt64 = 5_000) {
        self.session = session; self.audioBufferChunks = min(256, max(1, audioBufferChunks))
        self.transportQueueCommands = min(1_024, max(1, transportQueueCommands))
        self.transportTimeoutMilliseconds = min(60_000, max(1, transportTimeoutMilliseconds))
        self.maximumCleanupTasks = min(256, max(1, maximumCleanupTasks))
        self.maximumPendingClockTasks = min(512, max(1, maximumPendingClockTasks))
        self.observationBufferUpdates = min(256, max(1, observationBufferUpdates))
        self.approvalCapacity = min(10_000, max(1, approvalCapacity))
        self.approval = approval
        self.approvalHandoffTimeoutMilliseconds = min(15_000, max(1, approvalHandoffTimeoutMilliseconds))
    }
}

public enum SessionRuntimeIssue: Equatable, Sendable {
    case missingASR(ASRSource)
    case wrongASRProviderSource
    case missingSpeechProvider
    case providerFailed(SessionStage)
    case audioBackpressure
    case transportBackpressure
    case transportFailed
    case transportTimedOut
    case cleanupBackpressure
    case invalidSpeechAudio
    case emptySpeechAudio
    case clockFailed
    case transportCancellationBackpressure
    case clockBackpressure
    case approvalHandoffTimedOut
    case missingApprovalASR(ASRSource)
    case approvalASRFailed
    case approvalInvalidAudio
    case approvalAudioBackpressure
    case approvalClockInvalid
}

public struct SessionRuntimeSnapshot: Equatable, Sendable {
    public let session: SessionSnapshot
    public let revision: UInt64
    public let activeProviderTasks: Int
    public let activeCleanupTasks: Int
    public let retiringTransportTasks: Int
    public let retiringClockTasks: Int
    public let outstandingClockTasks: Int
    public let scheduledTimeouts: Int
    public let pendingTransportCommands: Int
    public let droppedObservationUpdates: UInt64
    public let lastIssue: SessionRuntimeIssue?
    public let isShutdown: Bool
    public let approval: RuntimeApprovalSnapshot

    /// Includes cancelled provider work until both its original task and cancel hook have returned.
    public var outstandingProviderLifecycles: Int { activeProviderTasks + activeCleanupTasks }
}

public struct SessionRuntimeObservation: Sendable {
    public let id: UUID
    public let updates: AsyncStream<SessionRuntimeSnapshot>
}

public enum RuntimeApprovalPhase: String, Sendable {
    case inactive, preparing, awaitingPresentation, awaitingToolApproval, awaitingPhoneConfirmation
    case capturingConfirmation, decisionReady, draining, failed
}
public struct RuntimeApprovalSnapshot: Equatable, Sendable {
    public let phase: RuntimeApprovalPhase
    public let suspensionID: UUID?
    public let presentation: ApprovalPresentation?
    public let capture: ApprovalCapturePrompt?
    /// Display only. The host must use takePendingApprovalDecision, not replay snapshot decisions.
    public let lastDecision: ApprovalDecision?
    public let hasPendingDecision: Bool
    public let lastRejection: ApprovalSubsessionRejection?
}
public enum RuntimeApprovalAdmission: Equatable, Sendable {
    case preparing(suspensionID: UUID)
    case rejected(ApprovalSubsessionRejection)
}
