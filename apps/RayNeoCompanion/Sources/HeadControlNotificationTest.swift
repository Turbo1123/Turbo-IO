import Foundation
import SwiftUI
import RayNeoDisplay

/// A deliberately isolated, on-device test for the observed suggestion-card
/// lifecycle. It does not call a network service, execute a tool, or turn a
/// head gesture into an approval outside this test page.
@MainActor
final class HeadControlNotificationTest: ObservableObject {
    @Published private(set) var status = "尚未发送测试卡"
    @Published private(set) var lastDecision: String?
    @Published private(set) var error: String?
    @Published private(set) var pendingID: String?
    @Published private(set) var expiresAt: Date?

    private let device: () -> String?
    private let available: () -> Bool
    private let transport: (UInt8, Data) throws -> Void
    private let now: () -> Date
    private let timeout: TimeInterval
    private let scheduleTimers: Bool
    private var pendingDevice: String?
    private var expiryTask: Task<Void, Never>?
    private let cardCodec = SuggestionCardJSONCodec()
    private let operationCodec = SuggestionJSONCodec()

    init(device: @escaping () -> String?, available: @escaping () -> Bool,
         transport: @escaping (UInt8, Data) throws -> Void,
         now: @escaping () -> Date = Date.init, timeout: TimeInterval = 30,
         scheduleTimers: Bool = true) {
        self.device = device
        self.available = available
        self.transport = transport
        self.now = now
        self.timeout = timeout
        self.scheduleTimers = scheduleTimers
    }

    deinit { expiryTask?.cancel() }

    var canSend: Bool { pendingID == nil && device() != nil && available() }
    var hasPendingCard: Bool { pendingID != nil }

    func send(title: String, source: String, content: String) {
        guard canSend, let connectedDevice = device() else {
            error = "需要唯一已连接、空闲的眼镜；未发送测试卡。"
            return
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty, !cleanSource.isEmpty, !cleanContent.isEmpty else {
            error = "标题、来源和内容都不能为空。"
            return
        }

        let id = UUID().uuidString.lowercased()
        do {
            try sendMessage(cardCodec.encodeAppRequest(.add(
                suggestUID: id, suggestType: .todo,
                title: cleanTitle, source: cleanSource, content: cleanContent,
                timeRange: nil)))
            pendingID = id
            pendingDevice = connectedDevice
            expiresAt = now().addingTimeInterval(timeout)
            lastDecision = nil
            error = nil
            status = "测试卡已发送；等待点头或摇头（(Int(timeout)) 秒）"
            scheduleExpiry(for: id)
        } catch {
            self.error = "测试卡未发送：\(error.localizedDescription)"
        }
    }

    /// Explicitly removes only the card created by this page. No acknowledgement
    /// or external action is emitted for a locally cancelled test.
    func cancel() {
        guard let id = pendingID else { return }
        do {
            try sendMessage(cardCodec.encodeAppRequest(.delete(suggestUID: id, suggestType: .todo)))
            clearPending(status: "已请求移除测试卡", decision: nil)
        } catch {
            self.error = "无法移除测试卡：\(error.localizedDescription)"
        }
    }

    func connectionChanged() {
        guard pendingID != nil else { return }
        clearPending(status: "连接变化；已停止等待这张测试卡", decision: nil)
    }

    func receive(device incomingDevice: String, wire: DeviceBusinessWire) {
        guard wire.type == 34, let id = pendingID, incomingDevice == pendingDevice else { return }
        do {
            let payload = try JSONSerialization.data(withJSONObject: wire.json, options: [.sortedKeys])
            guard case let .operation(operation) = try operationCodec.decodeGlassesOperation(type: 34, payload: payload),
                  operation.suggestUID == id, operation.suggestType == SuggestionCardCategory.todo.rawValue else { return }
            switch operation.command {
            case .accept: complete(id: id, decision: "已收到点头确认（仅测试回调）")
            case .reject: complete(id: id, decision: "已收到摇头取消（仅测试回调）")
            case .unknown: return
            }
        } catch {
            self.error = "忽略不匹配的头控回传。"
        }
    }

    private func complete(id: String, decision: String) {
        // Consume locally before outbound cleanup so duplicate BLE delivery can
        // never turn into a second decision or second acknowledgement.
        clearPending(status: decision, decision: decision)
        do {
            try sendMessage(cardCodec.encodeAppRequest(.delete(suggestUID: id, suggestType: .todo)))
            try sendMessage(operationCodec.encodeAppAcknowledgement(
                suggestUID: id, suggestType: SuggestionCardCategory.todo.rawValue, code: .success))
            error = nil
        } catch {
            self.error = "已记录头控结果，但清理/回执未发送：\(error.localizedDescription)"
        }
    }

    private func scheduleExpiry(for id: String) {
        expiryTask?.cancel()
        guard scheduleTimers else { return }
        let nanoseconds = UInt64(max(timeout, 0) * 1_000_000_000)
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire(id: id)
        }
    }

    private func expire(id: String) {
        guard pendingID == id else { return }
        do { try sendMessage(cardCodec.encodeAppRequest(.delete(suggestUID: id, suggestType: .todo))) }
        catch let caught { self.error = "测试已超时，但移除请求未发送：\(caught.localizedDescription)" }
        clearPending(status: "测试已超时；不执行任何操作", decision: nil)
    }

    private func clearPending(status: String, decision: String?) {
        expiryTask?.cancel(); expiryTask = nil
        pendingID = nil; pendingDevice = nil; expiresAt = nil
        self.status = status
        if let decision { lastDecision = decision }
    }

    private func sendMessage(_ message: DisplayJSONMessage) throws {
        guard let json = try JSONSerialization.jsonObject(with: message.payload) as? [String: Any] else {
            throw DeviceFeatureError.invalidPacket
        }
        try transport(21, DeviceBusinessWire.encode(type: UInt32(message.type), json: json))
    }
}

struct HeadControlNotificationTestView: View {
    @EnvironmentObject private var test: HeadControlNotificationTest
    @State private var title = "头控测试"
    @State private var source = "Turbo IO"
    @State private var content = "点头确认，摇头取消。"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Label("本机头控测试", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.headline)
                    Text("仅发送一张待办建议卡。点头/摇头只在本页显示结果，绝不会调用网络、Core 或自动化。")
                        .font(.caption).foregroundStyle(Palette.muted)
                    TextField("标题", text: $title).textInputAutocapitalization(.never)
                    TextField("来源", text: $source).textInputAutocapitalization(.never)
                    TextField("内容", text: $content, axis: .vertical).lineLimit(2...4)
                    Button("发送 30 秒头控测试卡") { test.send(title: title, source: source, content: content) }
                        .disabled(!test.canSend).accessibilityIdentifier("head-control-test-send")
                    if test.hasPendingCard {
                        Button("立即移除测试卡", role: .destructive) { test.cancel() }
                            .accessibilityIdentifier("head-control-test-cancel")
                    }
                }
                Card {
                    Text(test.status).font(.subheadline).accessibilityIdentifier("head-control-test-status")
                    if let decision = test.lastDecision { Text(decision).font(.caption).foregroundStyle(Palette.green) }
                    if let error = test.error { Text(error).font(.caption).foregroundStyle(.red) }
                    Text("协议范围：业务 21；下发 type 33，匹配 type 34 回传后删除并发送 type 35 回执。未验证的回传会被忽略。")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
            }.padding(22)
        }
        .background(Palette.background)
        .navigationTitle("头控通知测试")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .preference(key: CompanionTabBarHiddenPreference.self, value: true)
    }
}
