import Foundation
import Combine
import UIKit
import SwiftUI

/// Experimental iOS 1.0.2 LifeLog commands. Not the ordinary recording protocol.
enum AlwaysOnWire {
    static func launcher(_ command: String, enabled: Bool) throws -> Data {
        guard ["life_log_guide", "life_log_switch"].contains(command) else { throw DeviceFeatureError.invalidPacket }
        return try DeviceBusinessWire.encode(type: 20, json: ["cmd": command,
            "payload": ["value": enabled ? 1 : 0, "mode": 0,
                        "data": command == "life_log_switch" && enabled ? "{\"delay\":2}" : ""]])
    }
    static func start(_ id: String) throws -> Data {
        guard DeviceBusinessWire.identifier(["taskId": id], "taskId") != nil else { throw DeviceFeatureError.invalidPacket }
        return try DeviceBusinessWire.encode(type: 162, json: ["taskId": id, "idleTimeoutSec": 30])
    }
    static func exit() throws -> Data { try DeviceBusinessWire.encode(type: 166, json: ["rc": 2]) }
    static func page(_ visible: Bool) throws -> Data { try DeviceBusinessWire.encode(type: 168, json: ["inRealtimePage": visible]) }
    static func batchSummary(_ wire: DeviceBusinessWire) -> (frames: Int, unusedBytes: Int) {
        let keys = ["frameCount", "mode", "vpuMask", "vadMask"]
        guard keys.contains(where: { wire.json[$0] != nil }) else { return (wire.bytes.isEmpty ? 0 : 1, 0) }
        let available = wire.bytes.count / 240
        let declared = DeviceBusinessWire.integer(wire.json, "frameCount") ?? Int64(available)
        let frames = Int(min(31, min(Int64(available), max(0, declared))))
        return (frames, wire.bytes.count - frames * 240)
    }
}

/// Small bounded diagnostic capture: original length-prefixed envelopes, not a playable .opus claim.
@MainActor final class AlwaysOnLocalProbe: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var pendingStop: Bool
    @Published private(set) var status = "尚未启动；不采音、不上传"
    @Published private(set) var packetCount = 0
    @Published private(set) var audioBytes = 0
    @Published private(set) var receivedPackets = 0
    @Published private(set) var receivedAudioBytes = 0
    @Published private(set) var droppedPackets = 0
    @Published private(set) var droppedAudioBytes = 0
    @Published private(set) var tailPackets = 0
    @Published private(set) var frameCount = 0
    @Published private(set) var unusedBytes = 0
    @Published private(set) var remaining = 0
    @Published private(set) var events: [String] = []
    @Published private(set) var directory: URL?
    @Published private(set) var error: String?
    @Published private(set) var stopResultAcknowledged = false
    private let defaults: UserDefaults
    private let root: URL
    private let device: () -> String?
    private let available: () -> Bool
    private let send: (UInt8, Data) throws -> Void
    private let suspendVoice: () -> Void
    private let now: () -> TimeInterval
    private let scheduleTimers: Bool
    private var target: String?
    private var taskID = ""
    private var a2Sent = false
    private var offObserved = false
    private var stopAt: TimeInterval?
    private var lastStopRequest: TimeInterval?
    private var deadline: TimeInterval = 0
    private var acceptingAudio = false
    private var dropReasons: [String: Int] = [:]
    private var saveDeadline: TimeInterval { min(deadline + 5, stopAt.map { $0 + 5 } ?? deadline + 5) }
    private var lastAudio: TimeInterval = 0
    private var file: FileHandle?
    private var storedBytes = 0
    private var timer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let pendingKey = "companion.alwaysOn.localProbe.pendingDevice"
    var occupied: Bool { active || pendingStop }
    var canStart: Bool { device() != nil && available() && !occupied }
    var canConfirmPhysicalStop: Bool {
        pendingStop && !active && stopResultAcknowledged && target != nil && device() == target
    }
    init(defaults: UserDefaults, root: URL, device: @escaping () -> String?, available: @escaping () -> Bool,
         suspendVoice: @escaping () -> Void, send: @escaping (UInt8, Data) throws -> Void,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, scheduleTimers: Bool = true) {
        self.defaults = defaults; self.root = root; self.device = device; self.available = available
        self.suspendVoice = suspendVoice; self.send = send
        self.now = now; self.scheduleTimers = scheduleTimers
        target = defaults.string(forKey: pendingKey); pendingStop = target != nil
        if pendingStop { status = "上次停止未确认；请恢复同一眼镜并点重发停止。不会自动开始。" }
    }
    private func note(_ text: String) {
        events.append("\(Date().formatted(date: .omitted, time: .standard)) \(text)")
        events = Array(events.suffix(80))
    }
    func start() {
        guard canStart, let id = device() else { error = "需要连接眼镜并结束语音、普通录音或提词器；先处理未确认停止。"; return }
        do {
            let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let path = dir.appendingPathComponent("envelopes.rnp")
            try Data().write(to: path, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            file = try FileHandle(forWritingTo: path); directory = dir
        } catch { self.error = "无法准备本机文件，没有启动。"; return }
        suspendVoice()
        target = id; taskID = UUID().uuidString; a2Sent = false; offObserved = false; stopAt = nil
        lastStopRequest = nil; stopResultAcknowledged = false
        packetCount = 0; audioBytes = 0; frameCount = 0; unusedBytes = 0; storedBytes = 0; events = []; error = nil
        receivedPackets = 0; receivedAudioBytes = 0; droppedPackets = 0; droppedAudioBytes = 0; tailPackets = 0
        dropReasons = [:]; acceptingAudio = true
        active = true; pendingStop = true; defaults.set(id, forKey: pendingKey)
        deadline = now() + 25; lastAudio = 0; remaining = 25
        if scheduleTimers {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "LifeLogBoundedStop") { [weak self] in
            Task { @MainActor in self?.stop(reason: "后台运行时间到期"); self?.finishCapture() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        }
        do {
            try send(15, AlwaysOnWire.launcher("life_log_guide", enabled: true)); note("下发设置就绪（非开录回执）")
            try send(15, AlwaysOnWire.launcher("life_log_switch", enabled: true)); note("下发全天开关 ON")
            status = "等待眼镜开关回报 / A1；25秒请求停止，30秒内收取本轮尾包"
        } catch { acceptingAudio = false; self.error = "启动提交失败，仍会尝试关闭。"; stop(reason: "启动失败") }
    }
    func stop(reason: String = "手动停止") {
        guard pendingStop || active else { return }
        if stopAt == nil { stopAt = now(); note("停止：\(reason)") }
        remaining = active ? max(0, Int(ceil(saveDeadline - now()))) : 0
        status = "已请求停止；限时接收本轮尾包并等待关闭回报"
        stopResultAcknowledged = false; lastStopRequest = nil
        guard let target, device() == target else { status = "连接中断，停止未确认；恢复同一眼镜后重发停止"; return }
        lastStopRequest = now()
        // Attempt each stop independently: an A6 failure must not suppress switch OFF.
        for (business, packet) in [(UInt8(13), try? AlwaysOnWire.exit()), (15, try? AlwaysOnWire.launcher("life_log_switch", enabled: false)),
                                   (15, try? AlwaysOnWire.launcher("life_log_guide", enabled: false))] {
            do { if let packet { try send(business, packet) } } catch { self.error = "部分停止指令未提交，不能认定眼镜已停止。" }
        }
        if !active { status = "已重发停止，等待眼镜关闭状态；未重新采音" }
    }
    func connectionChanged() {
        if device() != target { acceptingAudio = false; stopResultAcknowledged = false; lastStopRequest = nil }
        if active, device() != target { stop(reason: "连接改变") }
    }
    /// Explicit lens inspection, not a protocol-confirmed OFF claim. No recording or packet send.
    func confirmPhysicalStop() {
        guard canConfirmPhysicalStop else { return }
        let report: [String: Any] = ["confirmedAt": ISO8601DateFormatter().string(from: Date()),
            "source": "user-observed-glasses-off-after-stop-result", "protocolOffObserved": offObserved,
            "stopResultAcknowledged": true, "events": events]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: root.appendingPathComponent("stop-confirmation-\(UUID().uuidString).json"),
                           options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { self.error = "无法保存人工停止确认，仍保留待处理状态。"; return }
        pendingStop = false; defaults.removeObject(forKey: pendingKey)
        status = "用户已确认眼镜关闭；本轮结束（未收到协议 OFF 状态）"
        note(status)
    }
    func lostMessages() {
        guard active else { return }; acceptingAudio = false
        error = "接收队列丢包，原包保留但不能标记完整。"; stop(reason: "接收不完整")
    }
    func receive(device id: String, business: UInt8, packet: Data) {
        guard target == id, device() == id, active || pendingStop else { return }
        do {
            let wire = try DeviceBusinessWire(packet)
            if business == 15 {
                guard let cmd = wire.json["cmd"] as? String, cmd.hasPrefix("life_log_"),
                      let p = wire.json["payload"] as? [String: Any] else { return }
                let value = DeviceBusinessWire.integer(p, "value")
                note("\(cmd) value=\(value.map(String.init) ?? "缺省") mode=\(DeviceBusinessWire.integer(p, "mode").map(String.init) ?? "缺省")")
                if cmd == "life_log_switch_result", value == 0,
                   let request = lastStopRequest, now() - request >= 0, now() - request <= 10 {
                    stopResultAcknowledged = true
                    if !active { status = "收到开关成功回执；请目视确认眼镜已关闭，再确认收尾" }
                }
                if cmd == "life_log_switch", value == 0, stopAt != nil {
                    offObserved = true
                    if !active { pendingStop = false; defaults.removeObject(forKey: pendingKey); status = "收到关闭状态；未重新采音" }
                }
                if cmd == "life_log_switch_result", let value, value != 0, stopAt == nil {
                    error = [1: "眼镜报告无麦克风权限", 2: "请展开镜腿", 3: "眼镜电量低"][Int(value)] ?? "眼镜拒绝全天开关，结果码 \(value)"
                    stop(reason: "眼镜拒绝")
                }
                return
            }
            guard business == 13, (161...168).contains(wire.type) else { return }
            if wire.type == 161 {
                note("收到 A1 唤醒")
                guard active, stopAt == nil, !a2Sent, now() < deadline else { return }
                a2Sent = true
                try send(13, AlwaysOnWire.start(taskID)); try send(13, AlwaysOnWire.page(false))
                note("下发 A2 收音 / A8 非实时页面"); status = "已应答眼镜唤醒，等待本地音频"
            } else if wire.type == 163 || wire.type == 164 {
                let now = now()
                receivedPackets += 1; receivedAudioBytes += wire.bytes.count
                var saved = false
                var dropReason = "保存失败"
                defer {
                    if !saved {
                        droppedPackets += 1; droppedAudioBytes += wire.bytes.count
                        dropReasons[dropReason, default: 0] += 1
                        if droppedPackets <= 3 || droppedPackets % 50 == 0 {
                            note("未保存音频：\(dropReason)，本包\(wire.bytes.count)字节，累计丢弃\(droppedPackets)包")
                        }
                    }
                }
                lastAudio = now
                if stopAt != nil { stopResultAcknowledged = false }
                guard active, acceptingAudio else { dropReason = "接收已结束或异常中止"; return }
                guard now < saveDeadline else { dropReason = "超过接收截止"; return }
                guard a2Sent else { dropReason = "未应答A2"; return }
                guard let incoming = DeviceBusinessWire.identifier(wire.json, "taskId") else {
                    dropReason = "缺少有效taskId"; return
                }
                guard incoming == taskID else { dropReason = "其他taskId"; return }
                guard storedBytes + packet.count + 4 <= 8 * 1_024 * 1_024, packetCount < 4096 else { throw DeviceFeatureError.storageLimit }
                var length = UInt32(packet.count).littleEndian
                let prefix = withUnsafeBytes(of: &length) { Data($0) }
                guard let file else { throw DeviceFeatureError.invalidPacket }
                try file.write(contentsOf: prefix + packet)
                storedBytes += packet.count + 4; packetCount += 1; audioBytes += wire.bytes.count
                saved = true
                if stopAt != nil || now >= deadline { tailPackets += 1 }
                let summary = AlwaysOnWire.batchSummary(wire)
                frameCount += summary.frames; unusedBytes += summary.unusedBytes
                if packetCount == 1 || packetCount % 50 == 0 { note("A\(wire.type - 160) 包 \(packetCount)，音频累计 \(audioBytes) 字节") }
                status = stopAt == nil ? "本机已保存音频；尚未验证可解码或完整性" : "停止已请求，本轮尾包已保存；等待收尾"
            } else if wire.type == 165 { note("收到 A5 退出 rc=\(DeviceBusinessWire.integer(wire.json, "rc").map(String.init) ?? "缺省")"); if stopAt == nil { stop(reason: "眼镜退出") } }
        } catch { acceptingAudio = false; self.error = "全天协议或写盘异常，保留已收原包并停止。"; stop(reason: "接收错误") }
    }
    func tick() {
        guard active else { return }
        let now = now()
        if stopAt == nil { remaining = max(0, Int(ceil(deadline - now))); if now >= deadline { stop(reason: "25秒上限") } }
        if stopAt != nil { remaining = max(0, Int(ceil(saveDeadline - now))) }
        if now >= saveDeadline { finishCapture() }
    }
    private func finishCapture() {
        guard active else { return }
        timer?.invalidate(); timer = nil; active = false; acceptingAudio = false; remaining = 0
        let quiet = lastAudio == 0 || now() - lastAudio >= 3
        if offObserved && quiet { pendingStop = false; defaults.removeObject(forKey: pendingKey) }
        status = pendingStop ? "本机已停止保存；眼镜停止尚未充分确认，请重发停止并查看眼镜" : "收到关闭状态，尾窗无新音频；本地测试结束"
        if pendingStop && stopResultAcknowledged { status = "收到开关成功回执；请目视确认眼镜已关闭，再确认收尾" }
        note(status)
        do {
            try file?.synchronize(); try file?.close(); file = nil
            if let directory {
                let data = try JSONSerialization.data(withJSONObject: ["createdAt": ISO8601DateFormatter().string(from: Date()),
                    "taskId": taskID, "packets": packetCount, "audioBytes": audioBytes, "frames": frameCount,
                    "unusedBytes": unusedBytes, "offObserved": offObserved, "quietTail": quiet, "stopPending": pendingStop,
                    "stopResultAcknowledged": stopResultAcknowledged,
                    "receivedPackets": receivedPackets, "receivedAudioBytes": receivedAudioBytes,
                    "droppedPackets": droppedPackets, "droppedAudioBytes": droppedAudioBytes,
                    "savedTailPackets": tailPackets, "dropReasons": dropReasons,
                    "stopRequestLimitSeconds": 25, "receiveLimitSeconds": 30,
                    "format": "uint32le length + original business envelope; NOT verified opus/wav", "events": events], options: [.prettyPrinted, .sortedKeys])
                try data.write(to: directory.appendingPathComponent("manifest.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        } catch { self.error = "本地文件收尾失败，保留已有原包；不可标完整。" }
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
}

struct AlwaysOnLocalProbeView: View {
    @ObservedObject var probe: AlwaysOnLocalProbe
    @State private var consent = false
    @State private var confirmPhysicalStop = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    Text("全天智记 · 本地短测").font(.headline)
                    Text("独立 A1–A8 协议验证，不是已完成的全天录音。第25秒请求停止，最迟第30秒结束本轮尾包接收。位置、日历、云转写均不启用。")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text(probe.status).accessibilityIdentifier("always-on-status")
                    Text("当前阶段剩余 \(probe.remaining) 秒\n收到 \(probe.receivedPackets) 包 / \(probe.receivedAudioBytes) 字节\n保存 \(probe.packetCount) 包 / \(probe.audioBytes) 字节（尾包 \(probe.tailPackets)）\n丢弃 \(probe.droppedPackets) 包 / \(probe.droppedAudioBytes) 字节")
                        .font(.caption).accessibilityIdentifier("always-on-counters")
                    if let error = probe.error { Text(error).foregroundStyle(Palette.amber) }
                    Toggle("同意本次仅音频保存到本机", isOn: $consent).disabled(probe.occupied).accessibilityIdentifier("always-on-consent")
                    Button("开始 30 秒本地测试") { probe.start(); consent = false }
                        .disabled(!consent || !probe.canStart).accessibilityIdentifier("always-on-start")
                    Button("停止 / 重发关闭", role: .destructive) { probe.stop() }
                        .disabled(!probe.occupied).accessibilityIdentifier("always-on-stop")
                    if probe.canConfirmPhysicalStop {
                        Button("我已确认眼镜关闭") { confirmPhysicalStop = true }
                            .accessibilityIdentifier("always-on-confirm-off")
                        Text("只在目视确认眼镜全天智记已关闭后使用；开关成功回执不等于 OFF 状态，人工确认单独记录。")
                            .font(.caption).foregroundStyle(Palette.amber)
                    }
                    Text("开始前请告知周围人并使用测试语句。会暂停 AI 语音待命；结束后不会自动恢复云收音。断连或强退不能保证远端立即停止，请保持眼镜与手机连接并观察。")
                        .font(.caption).foregroundStyle(Palette.muted)
                }
                if let path = probe.directory { Text("本机原包：\(path.lastPathComponent)\n未验证格式前不伪装为可播放录音；不查询或删除眼镜旧缓存。").font(.caption) }
                Card {
                    Text("协议事件（无音频正文）").font(.headline)
                    ForEach(Array(probe.events.enumerated()), id: \.offset) { _, event in Text(event).font(.system(.caption, design: .monospaced)) }
                }
            }.padding(22)
        }.background(Palette.background).navigationTitle("全天智记").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .confirmationDialog("确认已查看眼镜，全天智记已关闭？这会记录人工确认，不标记为协议验证通过。", isPresented: $confirmPhysicalStop) {
                Button("确认眼镜已关闭") { probe.confirmPhysicalStop() }
                Button("取消", role: .cancel) {}
            }
    }
}
