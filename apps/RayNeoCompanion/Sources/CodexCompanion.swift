import Foundation
import Combine
import Security

enum CodexBridgeError: LocalizedError {
    case configuration, missingKey, offline, invalidResponse, rejected(String), unknownDelivery
    var errorDescription: String? {
        switch self {
        case .configuration: return "请填写无账号、查询参数的 HTTPS 桥接地址；仅模拟器允许 HTTP 回环地址。"
        case .missingKey: return "请先保存此桥接地址的独立令牌。"
        case .offline: return "桥接未连接，请检查电脑服务与网络。"
        case .invalidResponse: return "桥接响应无效或版本不匹配。"
        case .rejected(let code): return "桥接未接受请求（\(code)）。没有自动重试。"
        case .unknownDelivery: return "上次提交结果未知。请点核对上次提交，不要重复创建任务。"
        }
    }
}

enum CodexEndpoint {
    static func normalize(_ text: String, allowLoopback: Bool = false) throws -> String {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              c.url != nil, c.path.isEmpty || c.path == "/",
              c.scheme == "https" || (allowLoopback && c.scheme == "http" && ["127.0.0.1", "localhost", "[::1]", "::1"].contains(host)) else { throw CodexBridgeError.configuration }
        c.path = ""; c.host = host.lowercased()
        return c.string!
    }
    static var simulatorLoopback: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

enum CodexTokenVault {
    static func get(_ endpoint: String) -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.turboio.codex", kSecAttrAccount as String: endpoint, kSecReturnData as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String, endpoint: String) throws {
        guard token.range(of: "^[A-Za-z0-9_-]{32,256}$", options: .regularExpression) != nil else { throw CodexBridgeError.missingKey }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.turboio.codex", kSecAttrAccount as String: endpoint]
        let attrs: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let rc = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if rc == errSecItemNotFound {
            guard SecItemAdd(query.merging(attrs) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CodexBridgeError.missingKey }
        } else if rc != errSecSuccess { throw CodexBridgeError.missingKey }
    }
}

struct CodexQuestion: Decodable, Identifiable { let id: String; let question: String; let options: [String] }
struct CodexApproval: Decodable, Identifiable {
    let id: String; let taskId: String; let turnId: String; let kind: String; let summary: String
    let questions: [CodexQuestion]; let expiresAt: Double
}
struct CodexTaskState: Decodable, Identifiable {
    let id: String; let threadId: String; let turnId: String?; let status: String; let answer: String; let pending: [CodexApproval]
}
struct CodexBridgeState: Decodable {
    let protocolVersion: Int; let online: Bool; let workspace: String; let readOnly: Bool; let tasks: [CodexTaskState]
    let events: [CodexPushEvent]?
}
private final class CodexNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum CodexHTTP {
    static func call(endpoint: String, token: String, path: String, body: Data?) async throws -> Data {
        let allowed = ["/v1/state", "/v1/message", "/v1/stop", "/v1/decision"]
        guard allowed.contains(path), token.range(of: "^[A-Za-z0-9_-]{32,256}$", options: .regularExpression) != nil else { throw CodexBridgeError.configuration }
        let base = try CodexEndpoint.normalize(endpoint, allowLoopback: CodexEndpoint.simulatorLoopback)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 35; config.timeoutIntervalForResource = 40
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: CodexNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodexBridgeError.invalidResponse }
        var data = Data()
        for try await byte in bytes { try Task.checkCancellation(); data.append(byte); guard data.count <= 2_097_152 else { throw CodexBridgeError.invalidResponse } }
        guard http.statusCode == 200 else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let raw = object?["error"] as? String ?? "http_\(http.statusCode)"
            let safe = raw.range(of: "^[a-z0-9_]{1,80}$", options: .regularExpression) != nil ? raw : "request_failed"
            throw CodexBridgeError.rejected(safe)
        }
        return data
    }
}

/// One catalogue supplies both the model request and the read-only tools UI.
struct CodexToolDescriptor: Identifiable {
    let id: String
    let title: String
    let description: String
    let example: String
    let requiresText: Bool
    var definition: [String: Any] {
        ["type": "function", "function": ["name": id, "description": description,
            "parameters": ["type": "object", "properties": requiresText ? ["text": ["type": "string", "description": "用户交给Codex的完整要求，不添加授权"]] : [:],
                "required": requiresText ? ["text"] : [], "additionalProperties": false]]]
    }
    var schemaJSON: String {
        guard let data = try? JSONSerialization.data(withJSONObject: definition, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "无法显示工具定义" }
        return text
    }
    static let all: [Self] = [
        .init(id: "codex_message", title: "发起 / 继续任务", description: "仅当用户明确要求Codex执行或继续编程任务时调用。发送到App选中的任务，未选择才新建；不适用于普通聊天或权限审批。", example: "让 Codex 检查一下这个项目的目录结构", requiresText: true),
        .init(id: "codex_status", title: "查询进度与结果", description: "用户询问Codex当前任务的进度或结果时调用。", example: "Codex 做完了吗？结果是什么？", requiresText: false),
        .init(id: "codex_stop", title: "停止当前任务", description: "仅用户明确要求停止Codex当前任务时调用。停止回复朗读不等于停止Codex。", example: "停止 Codex 当前任务", requiresText: false)
    ]
}

/// Tool calls cannot approve: approvals only enter through the explicit native UI.
@MainActor final class CodexCompanion: ObservableObject {
    @Published private(set) var endpoint: String
    @Published private(set) var voiceToolsEnabled: Bool
    @Published private(set) var state: CodexBridgeState?
    @Published private(set) var status = "尚未连接电脑桥接"
    @Published private(set) var busy = false
    @Published private(set) var selectedTaskID: String?
    @Published private(set) var hasUnknownDelivery = false
    private let defaults: UserDefaults
    private let key: (String) -> String?
    private let send: (String, String, String, Data?) async throws -> Data
    private var refreshing = false
    private var generation = UUID()
    private let prefix = "companion.codex.v1."
    var selected: CodexTaskState? { state?.tasks.first { $0.id == selectedTaskID } }
    var configured: Bool { !endpoint.isEmpty && key(endpoint) != nil }
    init(defaults: UserDefaults = .standard, key: @escaping (String) -> String? = CodexTokenVault.get,
         send: @escaping (String, String, String, Data?) async throws -> Data = CodexHTTP.call) {
        self.defaults = defaults; self.key = key; self.send = send
        endpoint = defaults.string(forKey: "companion.codex.v1.endpoint") ?? ""
        voiceToolsEnabled = defaults.bool(forKey: "companion.codex.v1.voiceTools")
        selectedTaskID = defaults.string(forKey: "companion.codex.v1.selected")
        hasUnknownDelivery = defaults.data(forKey: "companion.codex.v1.pending") != nil
    }
    func save(endpoint input: String, token: String, voiceTools: Bool) throws {
        guard !busy, !hasUnknownDelivery else { throw CodexBridgeError.unknownDelivery }
        let normalized = try CodexEndpoint.normalize(input, allowLoopback: CodexEndpoint.simulatorLoopback)
        if !token.isEmpty { try CodexTokenVault.save(token, endpoint: normalized) }
        guard key(normalized) != nil else { throw CodexBridgeError.missingKey }
        if normalized != endpoint { selectedTaskID = nil; defaults.removeObject(forKey: prefix + "selected") }
        generation = UUID(); state = nil; endpoint = normalized; voiceToolsEnabled = voiceTools
        defaults.set(endpoint, forKey: prefix + "endpoint"); defaults.set(voiceTools, forKey: prefix + "voiceTools")
        status = "配置已保存；尚未联网。语音工具\(voiceTools ? "已允许" : "已关闭")"
    }
    func select(_ id: String?) {
        guard !busy, !hasUnknownDelivery, id == nil || state?.tasks.contains(where: { $0.id == id }) == true else { return }
        selectedTaskID = id; defaults.set(id, forKey: prefix + "selected")
    }
    func refresh() async {
        guard !refreshing, configured else { return }; refreshing = true; defer { refreshing = false }
        let current = generation, base = endpoint
        do {
            let data = try await send(base, key(base)!, "/v1/state", nil)
            let value = try JSONDecoder().decode(CodexBridgeState.self, from: data)
            guard current == generation else { return }
            guard value.protocolVersion == 1, value.tasks.count <= 16, (value.events?.count ?? 0) <= 128 else { throw CodexBridgeError.invalidResponse }
            state = value; status = value.online ? "电脑桥接在线 · \(value.readOnly ? "只读测试" : "工作区可写，需审批时逐项确认")" : "Codex 进程离线"
        } catch {
            guard current == generation else { return }; state = nil
            status = (error as? CodexBridgeError)?.localizedDescription ?? "桥接连接失败；未自动提交任务"
        }
    }
    private func mutate(_ path: String, body: [String: Any]) async throws -> String {
        guard !busy else { throw CodexBridgeError.rejected("bridge_busy") }
        guard !hasUnknownDelivery else { throw CodexBridgeError.unknownDelivery }
        guard let token = key(endpoint), !endpoint.isEmpty else { throw CodexBridgeError.missingKey }
        let data = try JSONSerialization.data(withJSONObject: body)
        let pending = try JSONSerialization.data(withJSONObject: ["endpoint": endpoint, "path": path, "body": body])
        // At-most-once recovery retains user text locally until outcome is resolved.
        defaults.set(pending, forKey: prefix + "pending"); hasUnknownDelivery = true
        return try await deliver(path, data: data, token: token)
    }
    private func deliver(_ path: String, data: Data, token: String) async throws -> String {
        busy = true; defer { busy = false }
        do {
            let response = try await send(endpoint, token, path, data)
            guard let object = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  object["accepted"] as? Bool == true, let id = object["taskId"] as? String else { throw CodexBridgeError.invalidResponse }
            selectedTaskID = id; defaults.set(id, forKey: prefix + "selected")
            defaults.removeObject(forKey: prefix + "pending"); hasUnknownDelivery = false
            status = "已提交，实际执行结果请看任务状态"; await refresh(); return id
        } catch { status = "提交结果待核对，不会自动重复发送"; throw error }
    }
    func retryPending() async {
        guard !busy, let pending = defaults.data(forKey: prefix + "pending"),
              let object = (try? JSONSerialization.jsonObject(with: pending)) as? [String: Any],
              object["endpoint"] as? String == endpoint, let path = object["path"] as? String,
              let body = object["body"] as? [String: Any], let data = try? JSONSerialization.data(withJSONObject: body), let token = key(endpoint) else { return }
        do { _ = try await deliver(path, data: data, token: token) } catch { status = "仍未确认上次提交；保留原请求编号，未新建重复任务" }
    }
    func message(_ text: String, requestID: String = UUID().uuidString) async throws -> String {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 8192 else { throw CodexBridgeError.rejected("invalid_text") }
        var body: [String: Any] = ["text": text, "requestId": requestID]
        if let id = selectedTaskID { body["taskId"] = id }
        return try await mutate("/v1/message", body: body)
    }
    func stop(requestID: String = UUID().uuidString) async throws {
        guard let id = selectedTaskID else { throw CodexBridgeError.rejected("no_selected_task") }
        _ = try await mutate("/v1/stop", body: ["taskId": id, "requestId": requestID])
    }
    func decide(_ request: CodexApproval, approve: Bool, answers: [String: String] = [:]) async throws {
        guard let task = selected, task.id == request.taskId, task.pending.contains(where: { $0.id == request.id }),
              request.expiresAt > Date().timeIntervalSince1970 * 1000 else { throw CodexBridgeError.rejected("stale_request") }
        _ = try await mutate("/v1/decision", body: ["taskId": task.id, "approvalId": request.id, "decision": approve ? "accept" : "decline", "answers": answers, "requestId": UUID().uuidString])
    }
    var toolDefinitions: [[String: Any]] {
        guard voiceToolsEnabled, configured else { return [] }
        return CodexToolDescriptor.all.map(\.definition)
    }
    func executeTool(name: String, arguments: String, requestID: UUID) async -> String {
        guard voiceToolsEnabled, configured, !Task.isCancelled else { return "Codex 工具未开启。" }
        do {
            guard arguments.utf8.count <= 9000, let obj = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any] else { throw CodexBridgeError.invalidResponse }
            switch name {
            case "codex_message":
                guard obj.count == 1, let text = obj["text"] as? String else { throw CodexBridgeError.invalidResponse }
                let id = try await message(text, requestID: requestID.uuidString)
                return "已交给Codex，任务编号\(id.prefix(4))。任务会继续运行，你可以稍后问进度；需要审批请在手机确认。"
            case "codex_status":
                guard obj.isEmpty else { throw CodexBridgeError.invalidResponse }; await refresh()
                guard state?.online == true, let task = selected else { return "尚未取得当前Codex任务状态，请在Turbo IOCodex页连接并选择任务。" }
                return "Codex：\(task.status)。\(String(task.answer.suffix(350)))" + (task.pending.isEmpty ? "" : "请在手机查看具体提问或审批。")
            case "codex_stop":
                guard obj.isEmpty else { throw CodexBridgeError.invalidResponse }; try await stop(requestID: requestID.uuidString)
                return "已请求Codex停止当前任务，最终状态请在任务页核对。"
            default: return "不支持此工具，未执行任何操作。"
            }
        } catch { return "Codex请求未确认成功，请在手机核对。没有自动重试或批准。" }
    }
}
