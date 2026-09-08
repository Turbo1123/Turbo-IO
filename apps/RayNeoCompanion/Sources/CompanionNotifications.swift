import Foundation
import Combine

/// Ordinary notifications, pinned to the official iOS 1.0.2 business 21 contract.
/// Separate from ANCS payload collection, voice text, and suggestion/approval cards.
enum GlassesNotificationProtocol {
    static let business: UInt8 = 21
    static let companionAppID = "io.turboio.companion"
    static let phoneAppID = "com.apple.mobilephone"

    static func validAppID(_ id: String) -> Bool {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        return id.utf8.count <= 128 && parts.count >= 2 && parts.allSatisfy { !$0.isEmpty } &&
            id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0) }
    }

    static func settings(_ draft: NotificationPreferences) throws -> Data {
        guard [5,10,15,20,30].contains(draft.displayTime), draft.sources.count <= 100, draft.sources.contains(where: { $0.id == phoneAppID }),
              Set(draft.sources.map(\.id)).count == draft.sources.count,
              draft.sources.allSatisfy({ validAppID($0.id) }) else { throw DeviceFeatureError.invalidPacket }
        // Official 0x4c57c8 branches past enabled entries; disabled app IDs form filterUID.
        // Incoming calls are additionally controlled by the phone row's enabled flag.
        return try DeviceBusinessWire.encode(type: 17, json: [
            "notification": draft.enabled,
            "callNotification": draft.sources.first(where: { $0.id == phoneAppID })?.allowed ?? true,
            "avoidDuplicate": false, "displayTime": draft.displayTime, "intervalTime": 2,
            "filterUID": draft.sources.filter { !$0.allowed }.map(\.id).sorted()
        ])
    }

    static func notification(uid: String, title: String, content: String, date: Date = Date()) throws -> Data {
        guard let value = Int64(uid), value > 0, value <= Int32.max, String(value) == uid,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 80, content.count <= 500,
              [title, content].allSatisfy({ !$0.unicodeScalars.contains { CharacterSet.controlCharacters.subtracting(.newlines).contains($0) } }),
              date.timeIntervalSince1970.isFinite else { throw DeviceFeatureError.invalidPacket }
        // Official dev button uses decimal-string UID, category 0, reply false,
        // added=1, and local DateTime.toIso8601String(), NOT epoch milliseconds.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return try DeviceBusinessWire.encode(type: 2, json: [
            "notificationUID": uid, "appId": companionAppID, "appName": "Turbo IO",
            "title": title, "subtitle": "", "content": content,
            "timestamp": formatter.string(from: date), "category": 0, "reply": false, "type": 1
        ])
    }

    static func stateLabel(_ raw: Int64) -> String {
        switch raw {
        case 0: return "空闲（不代表已读）"
        case 1: return "显示中或间隔期（请核对镜片）"
        case 2: return "未佩戴"
        case 3: return "免打扰"
        case 4: return "其他眼镜功能占用"
        default: return "未知状态 \(raw)（不作为成功）"
        }
    }
}

struct NotificationSource: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var allowed: Bool
}

struct NotificationPreferences: Codable, Equatable {
    var enabled = false
    var displayTime = 5
    // This is a starter catalog, not an installed-app inventory or a deny-unknown policy.
    var sources: [NotificationSource] = [
        .init(id: GlassesNotificationProtocol.companionAppID, name: "Turbo IO", allowed: true),
        .init(id: GlassesNotificationProtocol.phoneAppID, name: "电话（含来电）", allowed: true),
        .init(id: "com.apple.MobileSMS", name: "信息", allowed: true),
        .init(id: "com.apple.mobilemail", name: "邮件", allowed: true),
        .init(id: "com.tencent.xin", name: "微信", allowed: true)
    ]
    init() {}
    private enum CodingKeys: String, CodingKey { case enabled, sources, displayTime }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        sources = try c.decode([NotificationSource].self, forKey: .sources)
        // The built-in source keeps its wire ID and user choice across a display-name change.
        for index in sources.indices where sources[index].id == GlassesNotificationProtocol.companionAppID {
            sources[index].name = "Turbo IO"
        }
        // Preserve existing source choices when loading pre-duration preferences.
        displayTime = try c.decodeIfPresent(Int.self, forKey: .displayTime) ?? 5
    }
}

@MainActor final class CompanionNotifications: ObservableObject {
    @Published private(set) var preferences: NotificationPreferences
    @Published private(set) var configurationStatus = "本机草稿；未读取或修改眼镜设置"
    @Published private(set) var sourcesNeedApply = true
    @Published private(set) var reportedEnabled: Bool?
    @Published private(set) var ancsAvailable: Bool?
    @Published private(set) var availabilityStatus = "共享通知状态未知"
    @Published private(set) var testStatus = "尚未发送；业务通知不经过 iOS 通知中心"
    @Published private(set) var lastUID: String?
    @Published private(set) var operationStatus: String?
    @Published private(set) var awaitingState = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let key = "companion.v1.notificationPreferences"
    private let device: () -> String?
    private let isBusy: () -> Bool
    private let transport: (UInt8, Data) throws -> Void
    private let timeout: UInt64
    private var currentDevice: String?
    private var submittedEnabled: Bool?
    private var lastDevice: String?
    private var stateWait: Task<Void, Never>?
    private var availabilityWait: Task<Void, Never>?
    private var availabilityGeneration = UUID()
    private var nextUID = Int64.random(in: 1...Int64(Int32.max - 1))

    init(defaults: UserDefaults, device: @escaping () -> String?, isBusy: @escaping () -> Bool,
         timeoutNanoseconds: UInt64 = 8_000_000_000,
         transport: @escaping (UInt8, Data) throws -> Void) {
        self.defaults = defaults; self.device = device; self.isBusy = isBusy
        self.transport = transport; timeout = timeoutNanoseconds
        if let data = defaults.data(forKey: key), data.count <= 65_536,
           let saved = try? JSONDecoder().decode(NotificationPreferences.self, from: data),
           (try? GlassesNotificationProtocol.settings(saved)) != nil,
           saved.sources.contains(where: { $0.id == GlassesNotificationProtocol.companionAppID }),
           saved.sources.contains(where: { $0.id == GlassesNotificationProtocol.phoneAppID }),
           saved.sources.allSatisfy({ !$0.name.isEmpty && $0.name.count <= 40 && $0.name.rangeOfCharacter(from: .controlCharacters) == nil }) {
            preferences = saved
        } else { preferences = NotificationPreferences() }
        currentDevice = device()
    }
    deinit { stateWait?.cancel(); availabilityWait?.cancel() }
    var connected: Bool { device() != nil }
    var masterApplied: Bool { (reportedEnabled ?? submittedEnabled) == true }
    var canSend: Bool { connected && !isBusy() }
    var canTest: Bool {
        canSend && !awaitingState && preferences.enabled &&
            preferences.sources.first(where: { $0.id == GlassesNotificationProtocol.companionAppID })?.allowed == true
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) }
    }
    func setEnabled(_ enabled: Bool) {
        preferences.enabled = enabled; persist()
        configurationStatus = "总开关草稿已保存，尚未提交"
        if canSend { applyMaster() }
    }
    func setDisplayTime(_ seconds: Int) {
        guard [5,10,15,20,30].contains(seconds) else { error = "显示时长不在本版测试范围内。"; return }
        preferences.displayTime = seconds; persist(); sourcesNeedApply = true
        configurationStatus = "显示时长草稿已保存，未下发；需确认全量通知配置"
    }
    func setAllowed(_ id: String, _ allowed: Bool) {
        guard let index = preferences.sources.firstIndex(where: { $0.id == id }) else { return }
        preferences.sources[index].allowed = allowed; persist()
        sourcesNeedApply = true
        configurationStatus = "来源草稿已修改；请点应用来源配置"
    }
    @discardableResult func addSource(name: String, id: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GlassesNotificationProtocol.validAppID(id), !name.isEmpty, name.count <= 40,
              name.rangeOfCharacter(from: .controlCharacters) == nil,
              preferences.sources.count < 100, !preferences.sources.contains(where: { $0.id == id }) else {
            error = "请输入不重复的 Bundle ID 和 1–40 字名称；来源最多 100 项。"; return false
        }
        preferences.sources.append(.init(id: id, name: name, allowed: true)); persist()
        sourcesNeedApply = true
        configurationStatus = "新来源已存为草稿；请点应用来源配置"; error = nil; return true
    }
    func connectionChanged() {
        let next = device()
        guard next != currentDevice else { return }
        currentDevice = next; invalidateConnectionEvidence("连接已变化；需手动应用，不自动覆盖眼镜配置")
    }
    func lostMessages() { invalidateConnectionEvidence("回调发生丢失；状态不再可信，请重新查询或测试") }
    private func invalidateConnectionEvidence(_ reason: String) {
        stateWait?.cancel(); availabilityWait?.cancel(); availabilityGeneration = UUID()
        if lastUID != nil { testStatus = "\(reason)；上一条结果未确认" }
        awaitingState = false; lastDevice = nil; operationStatus = nil
        submittedEnabled = nil; reportedEnabled = nil; ancsAvailable = nil
        sourcesNeedApply = true
        configurationStatus = reason; availabilityStatus = "共享通知状态未知"
    }
    private func check() throws -> String {
        connectionChanged()
        guard let id = device() else { throw DeviceFeatureError.disconnected }
        guard !isBusy() else { throw DeviceFeatureError.busy }
        return id
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation(); error = nil }
        catch { self.error = (error as? LocalizedError)?.errorDescription ?? "提交失败，未确认眼镜收到。" }
    }
    func applyMaster() {
        perform {
            _ = try check()
            submittedEnabled = nil; reportedEnabled = nil
            try transport(21, DeviceBusinessWire.encode(type: 18, json: ["notification": preferences.enabled]))
            submittedEnabled = preferences.enabled
            configurationStatus = "总开关已提交（\(preferences.enabled ? "开" : "关")）；来源配置未在这一步发送，未确认镜片"
        }
    }
    /// Full replacement, explicitly confirmed in UI. No merge/readback contract is known.
    func applySources() {
        perform {
            _ = try check()
            submittedEnabled = nil; reportedEnabled = nil
            sourcesNeedApply = true
            try transport(21, GlassesNotificationProtocol.settings(preferences))
            submittedEnabled = preferences.enabled
            sourcesNeedApply = false
            configurationStatus = "来源及总开关已提交；无逐项回执，需真机验证过滤效果"
        }
    }
    func queryAvailability() {
        perform {
            let id = try check()
            let packet = try DeviceBusinessWire.encode(type: 20, json: [:])
            availabilityWait?.cancel(); availabilityGeneration = UUID()
            let generation = availabilityGeneration
            ancsAvailable = nil; availabilityStatus = "查询已提交，等待眼镜报告"
            do { try transport(21, packet) }
            catch { availabilityStatus = "查询提交失败；状态未知"; throw error }
            availabilityWait = Task { [weak self, timeout] in
                do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                guard let self, self.availabilityGeneration == generation, self.device() == id, self.ancsAvailable == nil else { return }
                self.availabilityStatus = "查询超时；没有当前共享通知状态，不自动重试"
            }
        }
    }
    /// Reusable future API entry; callers still obey connection, master and source policy.
    @discardableResult func send(title: String, content: String) -> String? {
        var sent: String?
        perform {
            let id = try check()
            guard preferences.enabled else { throw NotificationControlError.disabled }
            guard preferences.sources.first(where: { $0.id == GlassesNotificationProtocol.companionAppID })?.allowed == true else { throw NotificationControlError.sourceDenied }
            guard !awaitingState else { throw NotificationControlError.pending }
            guard (reportedEnabled ?? submittedEnabled) == true else {
                throw NotificationControlError.masterNotApplied
            }
            nextUID = nextUID >= Int32.max ? 1 : nextUID + 1
            let uid = String(nextUID)
            let packet = try GlassesNotificationProtocol.notification(uid: uid, title: title, content: content)
            // Register before transport so an immediate same-UID callback cannot be lost.
            lastUID = uid; lastDevice = id; awaitingState = true; operationStatus = nil
            testStatus = "SDK 调用已提交，等待同 UID 眼镜状态（最多 8 秒）"
            do { try transport(21, packet) }
            catch { awaitingState = false; lastDevice = nil; testStatus = "发送调用失败；不算成功"; throw error }
            sent = uid
            stateWait?.cancel()
            stateWait = Task { [weak self, timeout] in
                do { try await Task.sleep(nanoseconds: timeout) } catch { return }
                guard let self, self.device() == id, self.lastDevice == id, self.lastUID == uid, self.awaitingState else { return }
                self.awaitingState = false
                self.testStatus = "等待眼镜状态超时；未确认显示，不自动重发"
            }
        }
        return sent
    }
    func receive(device id: String, wire: DeviceBusinessWire) {
        connectionChanged()
        guard id == device(), wire.bytes.isEmpty else { return }
        let json = wire.json
        if wire.type == 18, let value = DeviceBusinessWire.boolean(json, "notification") {
            reportedEnabled = value // Report only: no request ID, no source-filter ACK.
        } else if wire.type == 21, let available = DeviceBusinessWire.boolean(json, "available") {
            ancsAvailable = available; availabilityWait?.cancel()
            availabilityStatus = available ? "眼镜报告 ANCS 可用（不代表每条通知都会显示）" : "眼镜报告 ANCS 不可用；请检查蓝牙共享系统通知"
        } else if [3, 4].contains(wire.type), id == lastDevice,
                  DeviceBusinessWire.identifier(json, "notificationUID") == lastUID {
            if wire.type == 3, let raw = DeviceBusinessWire.integer(json, "state") {
                awaitingState = false; stateWait?.cancel()
                testStatus = "同 UID 眼镜回报：" + GlassesNotificationProtocol.stateLabel(raw)
            } else if wire.type == 4, let raw = DeviceBusinessWire.integer(json, "cmd") {
                operationStatus = "同 UID 操作 cmd=\(raw)；语义未验，不执行任何工具"
            }
        }
        // Type 1 ANCS may contain other apps' private text. Do not persist/log/forward it.
        // Type 19 is an app-category catalog, not a whitelist. Do not substitute it for 17.
    }
}

enum NotificationControlError: LocalizedError {
    case masterNotApplied, disabled, sourceDenied, pending
    var errorDescription: String? {
        switch self {
        case .masterNotApplied: return "请先向当前眼镜应用通知总开关。"
        case .disabled: return "通知总开关已关闭；没有发送。"
        case .sourceDenied: return "Turbo IO来源被关闭；没有发送。"
        case .pending: return "上一条仍在等待眼镜状态，请稍后再试。"
        }
    }
}
