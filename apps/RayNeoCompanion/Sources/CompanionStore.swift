import Foundation
import Combine
import Security
import UniformTypeIdentifiers

struct LocalTodo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var completed = false
    var createdAt = Date()
    var dueAt: Date?
    var archivedAt: Date?
    var wireID: Int64?
    var wireDeviceID: String?
    var important: Bool?
    var delivery: TodoDelivery?
    var reminderSourceID: String?
    var reminderImportedAt: Date?
    var reminderDueComponents: DateComponents?
}

struct LocalRecording: Identifiable, Codable {
    var id = UUID()
    var name: String
    var storedFilename: String
    var importedAt = Date()
    var byteCount: Int64
}

struct ModelConfiguration: Codable, Equatable {
    var endpoint = ""
    var model = ""
    var recognition = "待实测决定"
    var speech = "待接入"
}

enum ConfigurationError: LocalizedError {
    case invalidEndpoint, embeddedCredentials, missingEndpointForCredential, keychain(Int32)
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请输入有效的 HTTPS 服务地址；留空可仅保存草稿。"
        case .embeddedCredentials: return "地址中不能包含账号、密码、查询参数或片段；密钥请填写到独立输入框。"
        case .missingEndpointForCredential: return "保存密钥前请先填写 HTTPS 地址；密钥必须绑定到具体服务。"
        case .keychain: return "无法安全保存密钥，请检查设备解锁状态后重试。"
        }
    }
}

enum ModelEndpoint {
    static func canonicalize(_ input: String) throws -> String {
        let endpoint = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return "" }
        guard var url = URLComponents(string: endpoint), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              url.url != nil else { throw ConfigurationError.invalidEndpoint }
        guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ConfigurationError.embeddedCredentials
        }
        url.scheme = "https"; url.host = host.lowercased()
        if url.port == 443 { url.port = nil }
        while url.percentEncodedPath.hasSuffix("/") { url.percentEncodedPath.removeLast() }
        guard let value = url.string else { throw ConfigurationError.invalidEndpoint }
        return value
    }
}

enum CredentialVault {
    private static let service = "io.turboio.companion.model"
    static func hasKey(for endpoint: String) -> Bool {
        guard let normalized = try? ModelEndpoint.canonicalize(endpoint), !normalized.isEmpty else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: normalized, kSecReturnAttributes as String: true]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }
    static func store(_ key: String, for endpoint: String) throws {
        guard !key.isEmpty else { return }
        let normalized = try ModelEndpoint.canonicalize(endpoint)
        guard !normalized.isEmpty else { throw ConfigurationError.missingEndpointForCredential }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: normalized]
        let data = Data(key.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(insert as CFDictionary, nil)
            if result != errSecSuccess { throw ConfigurationError.keychain(result) }
        } else if update != errSecSuccess { throw ConfigurationError.keychain(update) }
    }
    static func remove(for endpoint: String) throws {
        let normalized = try ModelEndpoint.canonicalize(endpoint)
        guard !normalized.isEmpty else { return }
        let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: normalized] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw ConfigurationError.keychain(result) }
    }
}

@MainActor
final class CompanionStore: ObservableObject {
    @Published var selectedTab = 0
    @Published var demoMode = ProcessInfo.processInfo.arguments.contains("--ui-demo")
    @Published private(set) var todos: [LocalTodo] = []
    @Published private(set) var recordings: [LocalRecording] = []
    @Published private(set) var configuration = ModelConfiguration()
    @Published private(set) var prompterText = ""
    @Published private(set) var isImporting = false
    @Published var message: String?
    let archive: LocalArchiveController
    let books: BookLibrary
    let timeline: ConversationTimeline
    let voice: CompanionVoiceRuntime
    let codex: CodexCompanion
    lazy var alwaysOn = AlwaysOnLocalProbe(defaults: defaults,
        root: customRecordingRoot?.deletingLastPathComponent().appendingPathComponent("AlwaysOnLocalProbeV1")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("AlwaysOnLocalProbeV1"),
        device: { [weak self] in self?.voice.deviceID },
        available: { [weak self] in
            guard let self else { return false }
            return self.features.canControl && self.features.recordingID == nil && self.features.teleprompterID == nil
        }, suspendVoice: { [weak self] in self?.voice.stop() },
        send: { [weak self] business, packet in
            guard let self else { throw DeviceFeatureError.disconnected }
            try self.voice.sendBusiness(business, payload: packet)
        })
    lazy var codexPush = CodexPush(codex: codex, defaults: defaults,
        canDeliver: { [weak self] in
            guard let self else { return false }
            // User opted into Codex alerts; restore only their enabled master,
            // never overwrite the glasses' app-source filter configuration.
            if self.notifications.canTest && !self.notifications.masterApplied { self.notifications.applyMaster() }
            return self.notifications.canTest && self.notifications.masterApplied
        }, deliver: { [weak self] title, content in self?.notifications.send(title: title, content: content) })
    let recordingASR = ManualRecordingASR()
    lazy var qweather = QWeatherDashboard(defaults:defaults,
        device: { [weak self] in guard let self, self.voice.ready else { return nil }; return self.voice.deviceID },
        occupied: { [weak self] in
            guard let self else { return true }
            return !self.features.canControl || self.features.recordingID != nil || self.features.teleprompterID != nil
        }, send: { [weak self] data in
            guard let self else { throw DeviceFeatureError.disconnected }
            try self.voice.sendBusiness(15,payload:data)
        })
    lazy var automaticWeather = AutomaticWeather(defaults: defaults,
        device: { [weak self] in guard let self, self.voice.ready else { return nil }; return self.voice.deviceID },
        isBusy: { [weak self] in
            guard let self else { return true }
            return !self.features.canControl || self.features.recordingID != nil || self.features.teleprompterID != nil
        }, send: { [weak self] snapshot, icon in
            guard let self else { throw DeviceFeatureError.disconnected }
            try self.features.submitWeatherstack(snapshot, icon: icon)
        })
    lazy var notifications = CompanionNotifications(defaults: defaults,
        device: { [weak self] in guard let self, self.voice.ready else { return nil }; return self.voice.deviceID },
        isBusy: { [weak self] in
            guard let self else { return true }
            return !self.features.canControl || self.features.recordingID != nil || self.features.teleprompterID != nil
        }, transport: { [weak self] index, data in
            guard let self else { throw DeviceFeatureError.disconnected }
            try self.voice.sendBusiness(index, payload: data)
        })
    lazy var features = CompanionDeviceFeatures(voice: voice, store: self,
        root: customRecordingRoot?.deletingLastPathComponent().appendingPathComponent("GlassesRecordingInboxV1")
        ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("GlassesRecordingInboxV1"))
    private let defaults: UserDefaults
    private let customRecordingRoot: URL?
    private let prefix = "companion.v1."

    init(defaults: UserDefaults = .standard, recordingRoot: URL? = nil, archiveRoot: URL? = nil, allowsArchiveTestFixture: Bool = false, allowsBookTestFixture: Bool = false) {
        self.defaults = defaults
        #if COMPANION_DEVICE
        demoMode = false
        #endif
        self.customRecordingRoot = recordingRoot
        timeline = ConversationTimeline(root: archiveRoot?.deletingLastPathComponent().appendingPathComponent("ConversationTimelineV1"))
        voice = CompanionVoiceRuntime(timeline: timeline)
        codex = CodexCompanion(defaults: defaults)
        voice.codex = codex
        books = BookLibrary(root: archiveRoot?.deletingLastPathComponent().appendingPathComponent("ReadingLibraryV1"), allowsTestFixture: allowsBookTestFixture)
        archive = LocalArchiveController(rootDirectory: archiveRoot, allowsTestFixture: allowsArchiveTestFixture)
        todos = restore("todos") ?? []
        recordings = restore("recordings") ?? []
        configuration = restore("configuration") ?? ModelConfiguration()
        prompterText = defaults.string(forKey: prefix + "prompter") ?? ""
    }

    static func forCurrentLaunch() -> CompanionStore {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ui-test-scope"), arguments.indices.contains(index + 1),
           let scope = UUID(uuidString: arguments[index + 1]),
           let defaults = UserDefaults(suiteName: "companion.ui-tests.\(scope.uuidString)") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("CompanionUITests", isDirectory: true)
                .appendingPathComponent(scope.uuidString, isDirectory: true)
            let store = CompanionStore(defaults: defaults, recordingRoot: root.appendingPathComponent("ImportedRecordings"),
                                  archiveRoot: root.appendingPathComponent("VerifiedRecordingArchiveV1"),
                                  allowsArchiveTestFixture: arguments.contains("--ui-archive-fixture"), allowsBookTestFixture: arguments.contains("--ui-book-fixture"))
            #if !COMPANION_DEVICE
            if arguments.contains("--ui-todo-conflict-fixture"), store.todos.isEmpty {
                store.addTodo("合成冲突样本 · 非眼镜数据")
                let id = store.todos[0].id
                let wire = store.assignWireID(id, device: "synthetic-ui-device")
                store.toggleTodo(id)
                store.applyGlassesTodo(device: "synthetic-ui-device", id: wire, status: 0, important: true)
            }
            #endif
            return store
        }
        #endif
        return CompanionStore()
    }

    func addTodo(_ title: String) {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        todos.insert(LocalTodo(title: String(text.prefix(300))), at: 0)
        persist(todos, key: "todos")
    }

    @discardableResult func importSystemReminders(_ rows: [SystemReminderSnapshot], selectedIDs: Set<String>) throws -> ReminderImportReport {
        guard !selectedIDs.isEmpty, selectedIDs.count <= 100, rows.count <= 500 else { throw SystemReminderError.selection }
        guard Set(rows.map(\.id)).count == rows.count, selectedIDs.isSubset(of: Set(rows.map(\.id))) else { throw SystemReminderError.selection }
        var additions: [LocalTodo] = [], skipped = 0
        let known = Set(todos.compactMap(\.reminderSourceID))
        for row in rows where selectedIDs.contains(row.id) {
            guard !row.id.isEmpty, row.id.utf8.count <= 1024 else { throw SystemReminderError.selection }
            if known.contains(row.id) { skipped += 1; continue }
            let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { throw SystemReminderError.selection }
            additions.append(LocalTodo(title: String(title.prefix(300)), completed: row.completed, dueAt: row.dueAt,
                reminderSourceID: row.id, reminderImportedAt: Date(), reminderDueComponents: row.dueComponents))
        }
        todos.insert(contentsOf: additions, at: 0)
        persist(todos, key: "todos")
        // No features.localTodoChanged call: importing never sends to glasses or writes to EventKit.
        return ReminderImportReport(imported: additions.count, skipped: skipped)
    }

    func toggleTodo(_ id: UUID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].completed.toggle()
        todoEdited(at: index)
        persist(todos, key: "todos")
        features.localTodoChanged(todos[index])
    }

    func editTodo(_ id: UUID, title: String, dueAt: Date?) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let index = todos.firstIndex(where: { $0.id == id }) else { return }
        let nextTitle = String(clean.prefix(300))
        let wireChanged = todos[index].title != nextTitle
        if todos[index].dueAt != dueAt { todos[index].reminderDueComponents = nil }
        todos[index].title = nextTitle; todos[index].dueAt = dueAt
        if wireChanged { todoEdited(at: index) }
        persist(todos, key: "todos")
        if wireChanged { features.localTodoChanged(todos[index]) }
    }
    func archiveTodo(_ id: UUID, archived: Bool) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].archivedAt = archived ? Date() : nil
        persist(todos, key: "todos")
    }

    func assignWireID(_ id: UUID, device: String) -> Int64 {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return 0 }
        if let existing = todos[index].wireID, todos[index].wireDeviceID == device { return existing }
        guard todos[index].wireDeviceID == nil, todos[index].wireID == nil, !device.isEmpty else { return 0 }
        // Integer ID below JS's exact limit; persistent mapping, no reuse of official task IDs.
        var value: Int64
        repeat { value = Int64.random(in: 1_000_000_000_000...8_999_999_999_999) } while todos.contains(where: { $0.wireID == value })
        todos[index].wireID = value; todos[index].wireDeviceID = device
        persist(todos,key:"todos"); return value
    }
    @discardableResult func applyGlassesTodo(device: String, id: Int64, status: Int64, important: Bool?) -> Bool {
        guard [0,1].contains(status), let index = todos.firstIndex(where: { $0.wireID == id && $0.wireDeviceID == device && $0.archivedAt == nil }) else { return false }
        let next = status == 1
        if todos[index].delivery?.pending == true || todos[index].delivery?.conflict != nil {
            // A status message has no title revision or proven causal ACK. Never discard an offline edit.
            let differs = todos[index].completed != next || (important != nil && (todos[index].important ?? false) != important)
            if differs {
                let observed = TodoDelivery.Observation(completed: next, important: important)
                if todos[index].delivery?.conflict != observed {
                    todos[index].delivery?.conflict = observed
                    persist(todos, key: "todos")
                }
            }
            return false
        }
        guard todos[index].completed != next || (important != nil && todos[index].important != important) else { return false }
        todos[index].completed = next
        if let important { todos[index].important = important }
        persist(todos,key:"todos") // Do not call toggleTodo: suppress immediate echo.
        return true
    }

    private func todoEdited(at index: Int) {
        var delivery = todos[index].delivery ?? TodoDelivery()
        delivery.edited()
        todos[index].delivery = delivery
    }

    func todoCandidates(device: String, pendingOnly: Bool) throws -> [LocalTodo] {
        let rows = todos.filter { $0.archivedAt == nil && (!pendingOnly || ($0.wireID != nil && $0.delivery?.pending == true)) }
        guard !rows.contains(where: { $0.wireDeviceID != nil && $0.wireDeviceID != device }) else { throw TodoDeliveryError.differentDevice }
        guard !rows.contains(where: { $0.delivery?.conflict != nil }) else { throw TodoDeliveryError.conflict }
        return rows
    }

    /// Persist intent BEFORE calling the transport. A throw/crash leaves an explicit retry candidate.
    func prepareTodoSubmission(_ id: UUID, device: String) throws -> LocalTodo {
        guard let index = todos.firstIndex(where: { $0.id == id && $0.archivedAt == nil }) else { throw TodoDeliveryError.missing }
        guard todos[index].delivery?.conflict == nil else { throw TodoDeliveryError.conflict }
        guard assignWireID(id, device: device) > 0 else { throw TodoDeliveryError.differentDevice }
        var delivery = todos[index].delivery ?? TodoDelivery()
        delivery.pending = true
        todos[index].delivery = delivery
        persist(todos, key: "todos")
        return todos[index]
    }

    func markTodoSubmitted(_ id: UUID, device: String, revision: UUID, at date: Date = Date()) {
        guard let index = todos.firstIndex(where: { $0.id == id && $0.wireDeviceID == device && $0.archivedAt == nil }),
              todos[index].delivery?.revision == revision, todos[index].delivery?.conflict == nil else { return }
        todos[index].delivery?.pending = false
        todos[index].delivery?.submittedRevision = revision
        todos[index].delivery?.submittedAt = date
        persist(todos, key: "todos")
    }

    /// Choosing a side only resolves local state; a separate explicit send is still required.
    func resolveTodoConflict(_ id: UUID, useGlassesStatus: Bool) {
        guard let index = todos.firstIndex(where: { $0.id == id && $0.archivedAt == nil }),
              let observed = todos[index].delivery?.conflict else { return }
        if useGlassesStatus {
            todos[index].completed = observed.completed
            if let important = observed.important { todos[index].important = important }
        }
        todos[index].delivery?.conflict = nil
        todoEdited(at: index)
        persist(todos, key: "todos")
    }

    func savePrompter(_ text: String) {
        prompterText = text
        defaults.set(text, forKey: prefix + "prompter")
    }

    func saveConfiguration(_ value: ModelConfiguration, key: String) throws {
        let endpoint = try ModelEndpoint.canonicalize(value.endpoint)
        try CredentialVault.store(key.trimmingCharacters(in: .whitespacesAndNewlines), for: endpoint)
        configuration = value
        configuration.endpoint = endpoint
        persist(configuration, key: "configuration")
    }

    func importRecording(_ source: URL) async throws {
        guard !isImporting else { throw RecordingImportError.alreadyImporting }
        isImporting = true
        defer { isImporting = false }
        let granted = source.startAccessingSecurityScopedResource()
        defer { if granted { source.stopAccessingSecurityScopedResource() } }
        let directory = try recordingsDirectory()
        let recording = try await Task.detached(priority: .userInitiated) {
            try RecordingFileImporter.copy(source: source, to: directory)
        }.value
        recordings.insert(recording, at: 0)
        persist(recordings, key: "recordings")
    }

    func recordingURL(_ recording: LocalRecording) -> URL? {
        guard let directory = try? recordingsDirectory() else { return nil }
        let file = directory.appendingPathComponent(recording.storedFilename)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private func recordingsDirectory() throws -> URL {
        if let customRecordingRoot { return customRecordingRoot }
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = documents.appendingPathComponent("ImportedRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func restore<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: prefix + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    private func persist<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: prefix + key)
    }
}
