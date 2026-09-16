import Foundation

public enum ConversationBackend: String, CaseIterable, Codable, Sendable {
    case deepSeek = "deepseek", hermes
    public var label: String { self == .hermes ? "Hermes · Mac" : "DeepSeek Flash" }
}

public struct ConversationBackendSelection: Equatable, Sendable {
    public struct Binding: Equatable, Sendable { public let id: UUID; public let backend: ConversationBackend }
    public private(set) var selected: ConversationBackend
    public private(set) var active: Binding?
    public init(selected: ConversationBackend = .deepSeek) { self.selected = selected }
    @discardableResult public mutating func select(_ backend: ConversationBackend, standbyEnabled: Bool) -> Bool {
        guard active == nil, !standbyEnabled else { return false }
        selected = backend; return true
    }
    public mutating func begin(id: UUID) -> Binding? {
        guard active == nil else { return nil }
        let value = Binding(id: id, backend: selected); active = value; return value
    }
    public mutating func finish(id: UUID) { if active?.id == id { active = nil } }
}

public enum HermesConversationError: Error, LocalizedError, Equatable {
    case configuration, invalidText, invalidResponse, unavailable, failed, cancelled, timedOut, alreadyStarted
    public var errorDescription: String? {
        switch self {
        case .configuration: return "请配置 HTTPS Hermes 桥接地址和该地址的独立令牌。"
        case .invalidText: return "请输入非空文字，最多 8192 UTF-8 字节。"
        case .invalidResponse: return "Hermes 桥接协议或回答无效；没有切换到其他模型。"
        case .unavailable: return "Hermes 桥接连接失败；没有自动重发或切换模型。"
        case .failed: return "Hermes 未能完成本轮，请检查电脑桥接。"
        case .cancelled: return "Hermes 本轮已取消。"
        case .timedOut: return "Hermes 等待超过 25 秒，已请求停止本轮。"
        case .alreadyStarted: return "此请求已启动，不能重复提交。"
        }
    }
}

/// Immutable, origin-bound configuration. No credential is put in a URL or log.
public struct HermesBridgeConfiguration: Sendable {
    public let endpoint: String
    public let token: String
    public init(endpoint: String, token: String) throws {
        self.endpoint = try Self.normalize(endpoint)
        guard token.range(of: "^[A-Za-z0-9_-]{32,256}$", options: .regularExpression) != nil else { throw HermesConversationError.configuration }
        self.token = token
    }
    public static func normalize(_ input: String) throws -> String {
        guard var url = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/", url.url != nil,
              url.port.map({ (1...65535).contains($0) }) ?? true else { throw HermesConversationError.configuration }
        url.host = host.lowercased(); url.path = ""
        return url.string!
    }
    func request(path: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: endpoint + path)!)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.timeoutInterval = 8
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
}

public struct HermesTaskSnapshot: Decodable, Equatable, Sendable {
    public enum Status: String, Decodable, Sendable { case running, completed, failed, cancelled }
    public let taskId: String, requestId: String, conversationId: String, agent: String
    public let status: Status
    public let answer: String
    public let revision: Int
    public let summary: String, updatedAt: String
    private enum CodingKeys: String, CodingKey { case taskId, requestId, conversationId, agent, status, answer, revision, summary, updatedAt, approval }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.approval), try c.decodeNil(forKey: .approval) else { throw HermesConversationError.invalidResponse }
        taskId = try c.decode(String.self, forKey: .taskId); requestId = try c.decode(String.self, forKey: .requestId)
        conversationId = try c.decode(String.self, forKey: .conversationId); agent = try c.decode(String.self, forKey: .agent)
        status = try c.decode(Status.self, forKey: .status); answer = try c.decode(String.self, forKey: .answer)
        revision = try c.decode(Int.self, forKey: .revision); summary = try c.decode(String.self, forKey: .summary)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
    }
}

/// Accepts bounded cumulative snapshots; emits only new text and one completion.
public struct HermesSnapshotReducer {
    public struct Update: Equatable { public let delta: String; public let complete: Bool; public let status: HermesTaskSnapshot.Status }
    private let requestID: String, conversationID: String
    private var previous: HermesTaskSnapshot?
    public init(requestID: UUID, conversationID: UUID) {
        self.requestID = requestID.uuidString.lowercased(); self.conversationID = conversationID.uuidString.lowercased()
    }
    public mutating func accept(_ data: Data) throws -> Update {
        guard data.count <= 65_536 else { throw HermesConversationError.invalidResponse }
        let value: HermesTaskSnapshot
        do { value = try JSONDecoder().decode(HermesTaskSnapshot.self, from: data) }
        catch { throw HermesConversationError.invalidResponse }
        guard value.taskId == requestID, value.requestId == requestID, value.conversationId == conversationID,
              value.agent == "hermes", value.revision >= 0, value.answer.utf8.count <= 8192,
              value.summary.utf8.count <= 1024, value.updatedAt.utf8.count <= 64,
              value.status != .completed || !value.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw HermesConversationError.invalidResponse
        }
        if let previous {
            guard value.revision >= previous.revision, value.answer.utf8.starts(with: previous.answer.utf8) else { throw HermesConversationError.invalidResponse }
            if value.revision == previous.revision || previous.status != .running {
                guard value == previous else { throw HermesConversationError.invalidResponse }
                return .init(delta: "", complete: false, status: value.status)
            }
        }
        let delta = String(decoding: value.answer.utf8.dropFirst(previous?.answer.utf8.count ?? 0), as: UTF8.self)
        previous = value
        return .init(delta: delta, complete: value.status == .completed, status: value.status)
    }
}

private final class ConversationNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public enum HermesBridgeHTTP {
    public static func send(_ request: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = min(25, request.timeoutInterval)
        configuration.timeoutIntervalForResource = min(30, request.timeoutInterval + 2)
        let session = URLSession(configuration: configuration, delegate: ConversationNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw HermesConversationError.unavailable }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation(); data.append(byte)
            guard data.count <= 65_536 else { throw HermesConversationError.invalidResponse }
        }
        return data
    }
    public static func health(configuration: HermesBridgeConfiguration) async throws {
        struct Health: Decodable { let ok: Bool; let agent: String; let mode: String; let protocolVersion: Int }
        let data = try await send(configuration.request(path: "/v1/health"))
        let health = try JSONDecoder().decode(Health.self, from: data)
        guard health.ok, health.agent == "hermes", health.mode == "conversation-only", health.protocolVersion == 1 else { throw HermesConversationError.invalidResponse }
    }
}

/// One client-known task ID, one create attempt. Cancellation uses a separate task
/// so a lost create response can still be stopped through the server tombstone.
@MainActor public final class HermesConversationOperation {
    public let requestID: UUID
    public let conversationID: UUID
    private let configuration: HermesBridgeConfiguration
    private let send: (URLRequest) async throws -> Data
    private let pause: () async throws -> Void
    private let onStopUnconfirmed: () -> Void
    private var started = false, cancelled = false, completed = false, timedOut = false
    private var worker: Task<Void, Error>?
    private var stopTask: Task<Void, Never>?
    public init(configuration: HermesBridgeConfiguration, requestID: UUID, conversationID: UUID,
                send: @escaping (URLRequest) async throws -> Data = HermesBridgeHTTP.send,
                pause: @escaping () async throws -> Void = { try await Task.sleep(nanoseconds: 500_000_000) },
                onStopUnconfirmed: @escaping () -> Void = {}) {
        self.configuration = configuration; self.requestID = requestID; self.conversationID = conversationID
        self.send = send; self.pause = pause; self.onStopUnconfirmed = onStopUnconfirmed
    }
    public func run(text: String, onText: @escaping (String, Bool) -> Void) async throws {
        guard !started else { throw HermesConversationError.alreadyStarted }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 8192 else { throw HermesConversationError.invalidText }
        try Task.checkCancellation()
        started = true
        let worker = Task { @MainActor in try await self.perform(text: text, onText: onText) }
        self.worker = worker
        let deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }
            guard let self, !self.completed else { return }
            self.timedOut = true; self.cancel()
        }
        defer { deadline.cancel(); self.worker = nil }
        do {
            try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: {
                Task { @MainActor in self.cancel() }
            })
            if !completed { try Task.checkCancellation() }
        } catch {
            cancel()
            if timedOut { throw HermesConversationError.timedOut }
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw (error as? HermesConversationError) ?? .unavailable
        }
    }
    private func perform(text: String, onText: @escaping (String, Bool) -> Void) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["agent": "hermes", "workspaceId": "conversation",
            "requestId": requestID.uuidString.lowercased(), "conversationId": conversationID.uuidString.lowercased(), "text": text, "mode": "read-only"])
        try checkCancellation()
        var data = try await send(configuration.request(path: "/v1/tasks", body: body))
        var reducer = HermesSnapshotReducer(requestID: requestID, conversationID: conversationID)
        var bufferedAnswer = ""
        while true {
            try checkCancellation()
            let update = try reducer.accept(data)
            switch update.status {
            case .failed: throw HermesConversationError.failed
            case .cancelled: throw HermesConversationError.cancelled
            case .running, .completed:
                // Validate every snapshot, but this conversation-only version
                // exposes the full answer only after confirmed completion.
                bufferedAnswer += update.delta
                // Completion callbacks may synchronously close the voice receiver.
                // Mark remote completion first, so normal cleanup sends no stop.
                if update.complete {
                    completed = true
                    onText(bufferedAnswer, true)
                    return
                }
            }
            try await pause(); try checkCancellation()
            data = try await send(configuration.request(path: "/v1/tasks/" + requestID.uuidString.lowercased()))
        }
    }
    private func checkCancellation() throws {
        try Task.checkCancellation(); if cancelled { throw CancellationError() }
    }
    public func cancel() {
        guard !completed else { return }
        cancelled = true; worker?.cancel()
        guard started, stopTask == nil else { return }
        let body = try! JSONSerialization.data(withJSONObject: ["conversationId": conversationID.uuidString.lowercased()])
        let request = configuration.request(path: "/v1/tasks/" + requestID.uuidString.lowercased() + "/stop", body: body)
        let send = send, failed = onStopUnconfirmed, id = requestID, conversation = conversationID
        stopTask = Task { @MainActor in
            do {
                let data = try await send(request)
                var reducer = HermesSnapshotReducer(requestID: id, conversationID: conversation)
                let value = try reducer.accept(data)
                guard value.status == .cancelled || value.status == .completed || value.status == .failed else { throw HermesConversationError.invalidResponse }
            } catch { failed() }
        }
    }
    /// Hosts can keep the configuration locked until the bounded stop attempt ends.
    public func waitForStop() async { await stopTask?.value }
}
