import Foundation

public enum HermesTaskError: Error, LocalizedError, Equatable {
    case invalidResponse, invalidInput, busy, unavailable, stalePrompt, decisionUnknown, storage, server(String)
    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Hermes 任务状态无效，请核对原任务；没有重新执行。"
        case .invalidInput: return "请输入有效文字；操作确认只能选择本次允许或拒绝。"
        case .busy: return "已有任务待处理，请先查看任务卡或明确停止。"
        case .unavailable: return "连接中断，任务可能仍在电脑执行。请核对原任务，不要重复提交。"
        case .stalePrompt: return "这条确认已过期，请刷新任务状态。"
        case .decisionUnknown: return "上次确认结果待核对；没有重复发送确认。"
        case .storage: return "任务编号未能可靠保存，本次没有继续发送操作。请检查手机存储。"
        case .server(let code):
            switch code {
            case "unauthorized": return "桥接令牌不匹配。请关闭待命，在原地址更新令牌后核对任务。"
            case "task_client_upgrade_required", "not_found": return "接口或任务未找到。请检查电脑任务桥接；没有重新执行。"
            case "hermes_not_ready", "hermes_unavailable": return "电脑上的 Hermes 尚未就绪，请检查电脑服务。"
            case "busy": return "Hermes 正在执行另一项任务，请等待或明确停止。"
            case "reconcile_required": return "上次任务结果仍需核对，请先在电脑确认。"
            case "stale_prompt": return "这条确认已过期，请刷新任务状态。"
            case "decision_unconfirmed": return "确认结果未知，请刷新核对；没有自动重发。"
            case "stop_unconfirmed": return "停止尚未确认，电脑任务可能仍在执行。"
            default: return "Hermes 未接受此操作，请核对任务状态。"
            }
        }
    }
}

public struct HermesTaskPrompt: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case approval, clarify, localAction }
    public let id: String, kind: Kind, title: String
    public let options: [String]
}
public struct HermesTaskState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case running, waiting, stopping, completed, failed, cancelled, unknown
        public var terminal: Bool { [.completed, .failed, .cancelled].contains(self) }
    }
    public let requestId: String, conversationId: String, status: Status, answer: String, summary: String, revision: Int
    public let prompt: HermesTaskPrompt?
}
public struct HermesTaskReference: Codable, Equatable, Sendable {
    public let endpoint: String
    public let conversationID: UUID
    public var requestID: UUID?
    public var decisionID: UUID?
    public var decisionPromptID: String?
}

/// A request reference survives view/voice cancellation. Only stop() sends stop.
@MainActor public final class HermesTaskClient {
    public let configuration: HermesBridgeConfiguration
    public private(set) var reference: HermesTaskReference
    public private(set) var snapshot: HermesTaskState?
    public private(set) var busy = false
    public var onChange: (() -> Void)?
    private let save: (Data) throws -> Void
    private let send: (URLRequest) async throws -> Data
    public var hasUnfinishedTask: Bool { reference.requestID != nil && snapshot?.status.terminal != true }
    public var decisionNeedsReconciliation: Bool { reference.decisionID != nil && reference.decisionPromptID == snapshot?.prompt?.id }
    public init(configuration: HermesBridgeConfiguration, load: () -> Data?, save: @escaping (Data) throws -> Void,
                send: @escaping (URLRequest) async throws -> Data = HermesTaskHTTP.send) throws {
        self.configuration = configuration; self.save = save; self.send = send
        if let data = load() {
            guard data.count <= 4096, let stored = try? JSONDecoder().decode(HermesTaskReference.self, from: data) else { throw HermesTaskError.invalidResponse }
            reference = stored.endpoint == configuration.endpoint ? stored : .init(endpoint: configuration.endpoint, conversationID: UUID())
        } else { reference = .init(endpoint: configuration.endpoint, conversationID: UUID()) }
        try persist()
    }
    private func persist() throws { try save(JSONEncoder().encode(reference)) }
    private func begin() throws { guard !busy else { throw HermesTaskError.busy }; busy = true; onChange?() }
    private func end() { busy = false; onChange?() }
    private func request(_ path: String, body: [String: String]? = nil) throws -> URLRequest {
        configuration.request(path: path, body: try body.map { try JSONSerialization.data(withJSONObject: $0) })
    }
    public func health() async throws {
        try begin(); defer { end() }
        struct Health: Decodable { let ok: Bool; let agent: String; let mode: String; let protocolVersion: Int; let ready: Bool }
        var probe = try request("/v2/health?conversationId=" + reference.conversationID.uuidString.lowercased())
        probe.timeoutInterval = 60
        let data = try await send(probe)
        guard let health = try? JSONDecoder().decode(Health.self, from: data), health.ok, health.agent == "hermes", health.mode == "tasks", health.protocolVersion == 2, health.ready else { throw HermesTaskError.invalidResponse }
    }
    public func submit(text: String) async throws {
        guard !hasUnfinishedTask else { throw HermesTaskError.busy }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 8192 else { throw HermesTaskError.invalidInput }
        try begin(); defer { end() }
        let previous = reference
        reference.requestID = UUID(); reference.decisionID = nil; reference.decisionPromptID = nil
        do { try persist() } catch { reference = previous; throw error }
        snapshot = nil; onChange?()
        let body = ["requestId": reference.requestID!.uuidString.lowercased(), "conversationId": reference.conversationID.uuidString.lowercased(), "text": text]
        try accept(await send(request("/v2/tasks", body: body)))
    }
    public func refresh() async throws {
        guard let id = reference.requestID else { return }
        try begin(); defer { end() }
        try accept(await send(request("/v2/tasks/" + id.uuidString.lowercased())))
    }
    public func stop() async throws {
        guard let id = reference.requestID, snapshot?.status.terminal != true else { return }
        try begin(); defer { end() }
        try accept(await send(request("/v2/tasks/" + id.uuidString.lowercased() + "/stop", body: ["conversationId": reference.conversationID.uuidString.lowercased()])))
    }
    public func decide(promptID: String, choice: String? = nil, text: String? = nil) async throws {
        guard let id = reference.requestID, let prompt = snapshot?.prompt, snapshot?.status == .waiting, prompt.id == promptID else { throw HermesTaskError.stalePrompt }
        if decisionNeedsReconciliation { throw HermesTaskError.decisionUnknown }
        switch prompt.kind {
        case .approval: guard text == nil, choice == "once" || choice == "deny" else { throw HermesTaskError.invalidInput }
        case .clarify: guard choice == nil, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 4096 else { throw HermesTaskError.invalidInput }
        case .localAction: throw HermesTaskError.invalidInput
        }
        try begin(); defer { end() }
        let previous = reference
        reference.decisionID = UUID(); reference.decisionPromptID = promptID
        do { try persist() } catch { reference = previous; throw error }
        var body = ["conversationId": reference.conversationID.uuidString.lowercased(), "promptId": promptID, "decisionId": reference.decisionID!.uuidString.lowercased()]
        if let choice { body["choice"] = choice }; if let text { body["text"] = text }
        try accept(await send(request("/v2/tasks/" + id.uuidString.lowercased() + "/decision", body: body)))
    }
    /// Explicit user action after checking the computer. Never called by voice.
    public func acknowledgeUnknown() async throws {
        guard let id = reference.requestID, snapshot?.status == .unknown else { throw HermesTaskError.invalidInput }
        try begin(); defer { end() }
        let data = try await send(request("/v2/tasks/" + id.uuidString.lowercased() + "/acknowledge", body: ["conversationId": reference.conversationID.uuidString.lowercased()]))
        try accept(data)
        let previous = reference
        reference.requestID = nil; reference.decisionID = nil; reference.decisionPromptID = nil
        do { try persist() } catch { reference = previous; throw error }
        snapshot = nil
    }
    private func accept(_ data: Data) throws {
        guard data.count <= 262_144, let state = try? JSONDecoder().decode(HermesTaskState.self, from: data),
              state.requestId == reference.requestID?.uuidString.lowercased(), state.conversationId == reference.conversationID.uuidString.lowercased(),
              state.answer.utf8.count <= 32768, state.summary.utf8.count <= 1024, state.revision >= 0 else { throw HermesTaskError.invalidResponse }
        if let prompt = state.prompt {
            guard UUID(uuidString: prompt.id) != nil, prompt.title.utf8.count <= 4096, prompt.options.count <= 12,
                  prompt.options.allSatisfy({ $0.utf8.count <= 512 }), state.status == .waiting || state.status == .stopping else { throw HermesTaskError.invalidResponse }
        }
        if let old = snapshot {
            guard state.revision >= old.revision else { throw HermesTaskError.invalidResponse }
            if state.revision == old.revision { guard state == old else { throw HermesTaskError.invalidResponse } }
            if old.status.terminal { guard state.status == old.status, old.answer.isEmpty || state.answer == old.answer else { throw HermesTaskError.invalidResponse } }
        }
        snapshot = state
        if reference.decisionPromptID != state.prompt?.id { reference.decisionID = nil; reference.decisionPromptID = nil; try persist() }
        onChange?()
    }
}

private final class HermesTaskNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
public enum HermesTaskHTTP {
    public static func send(_ request: URLRequest) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = min(60, max(12, request.timeoutInterval))
        config.timeoutIntervalForResource = min(62, max(15, request.timeoutInterval + 2))
        let session = URLSession(configuration: config, delegate: HermesTaskNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw HermesTaskError.invalidResponse }
            var data = Data()
            for try await byte in bytes { data.append(byte); guard data.count <= 262_144 else { throw HermesTaskError.invalidResponse } }
            guard response.statusCode == 200 else {
                let allowed = ["unauthorized", "task_client_upgrade_required", "not_found", "hermes_not_ready", "hermes_unavailable", "busy", "reconcile_required", "stale_prompt", "decision_unconfirmed", "stop_unconfirmed"]
                let code = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "unavailable"
                throw HermesTaskError.server(allowed.contains(code) ? code : "unavailable")
            }
            return data
        } catch let error as HermesTaskError { throw error }
        catch { throw HermesTaskError.unavailable }
    }
}
