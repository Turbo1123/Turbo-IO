import SwiftUI
import CoreMotion
import WatchConnectivity
import WatchKit

#if TIO_RAYNEO_HOST
private let hostName = "雷鸟插件"
private let hostMode = "rayneo-plugin-v1"
private let remoteTitle = "Turbo 遥控"
private let remoteSummary = "表冠翻项 · 屏幕确认 · 需 TGR1 固件"
#else
private let hostName = "手机测试器"
private let hostMode = "observe-only"
private let remoteTitle = "Turbo 遥控 · R0"
private let remoteSummary = "手势 / 通信测试，尚不控制眼镜"
#endif

final class WatchRemote: NSObject, ObservableObject, WCSessionDelegate {
    @Published var enabled = false
    @Published var reverse = false
    @Published var localOnly = true
    @Published var note = "手势测试 · 尚未连接眼镜"
    @Published var linked = false
    @Published var crownValue = 0.0
    @Published var reverseCrown = false
    @Published var mapping: RemoteInputMapping = .doubleTapBrowses {
        didSet { UserDefaults.standard.set(mapping.rawValue, forKey: "remote.inputMapping"); detector.reset() }
    }
    private let motion = CMMotionManager()
    private var detector = WristDetector()
    private var crown = CrownDetector()
    private var sequence: UInt64 = 0
    private var sessionID = UUID()
    private var pending: UUID?
    private var lastSent = Date.distantPast

    override init() {
        super.init()
        if let raw = UserDefaults.standard.string(forKey: "remote.inputMapping"), let saved = RemoteInputMapping(rawValue: raw) {
            mapping = saved
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func arm(_ value: Bool) {
        enabled = value
        detector.reset()
        crown.reset(at: crownValue)
        motion.stopDeviceMotionUpdates()
        guard value else { pending = nil; note = "遥控已关闭"; return }
        guard motion.isDeviceMotionAvailable else {
            note = "运动数据不可用；可使用屏幕按钮"; return
        }
        note = "保持手腕自然姿势，再左右转动并回正"
        motion.deviceMotionUpdateInterval = 1.0 / 25.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            guard let self, self.enabled else { return }
            guard error == nil, let data else { self.arm(false); self.note = "运动采样失败"; return }
            let a = data.userAcceleration
            let length = sqrt(a.x*a.x + a.y*a.y + a.z*a.z)
            if let direction = self.detector.sample(roll: data.attitude.roll,
                                                    acceleration: length, time: data.timestamp) {
                let step = self.reverse ? -direction : direction
                self.send(self.mapping.wristAction(direction: step))
            }
        }
    }

    func connectProbe() {
        linked = false
        pending = nil
        sessionID = UUID()
        sequence = 0
        let sid = sessionID
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            note = "\(hostName)不可达；请先在手机开启本轮遥控"; return
        }
        note = "连接\(hostName)…"
        WCSession.default.sendMessage(["kind": "turbo.remote.hello", "session": sid.uuidString], replyHandler: { reply in
            DispatchQueue.main.async {
                guard self.sessionID == sid else { return }
                self.linked = reply["session"] as? String == sid.uuidString && reply["mode"] as? String == hostMode
                self.note = self.linked ? "\(hostName)已连接；目标：\(reply["target"] as? String ?? "手势验证")" : (reply["note"] as? String ?? "伴侣不支持当前协议")
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async { if self.sessionID == sid { self.note = "连接失败；不重试旧命令" } }
        })
    }

    func crownChanged(_ value: Double) {
        guard enabled else { crown.reset(at: value); return }
        if let action = crown.sample(value) {
            send(reverseCrown ? (action == .next ? .previous : .next) : action)
        }
    }

    func send(_ action: RemoteAction) {
        guard enabled else { note = "请先开启遥控"; return }
        guard Date().timeIntervalSince(lastSent) >= 0.45, pending == nil else { return }
        lastSent = Date()
        if localOnly {
            note = "本机识别：\(action.title) · 未发送"
            WKInterfaceDevice.current().play(.click)
            return
        }
        guard linked, WCSession.default.activationState == .activated, WCSession.default.isReachable else {
            linked = false; note = "连接不可用，本次已丢弃"; return
        }
        sequence += 1
        let command = RemoteCommand(version: 1, id: UUID(), session: sessionID,
                                    sequence: sequence, sentAt: Date().timeIntervalSince1970, action: action)
        guard let bytes = try? JSONEncoder().encode(command) else { return }
        pending = command.id
        note = "发送：\(action.title)"
        WCSession.default.sendMessage(["kind": "turbo.remote.command", "data": bytes], replyHandler: { reply in
            DispatchQueue.main.async {
                guard self.pending == command.id else { return }
                self.pending = nil
                let result = reply["result"] as? String ?? ""
                if reply["id"] as? String == command.id.uuidString && ["observed", "phone-applied", "submitted", "dispatched", "wake-only"].contains(result) {
                    self.note = String((reply["note"] as? String ?? "手机收到，眼镜未确认").prefix(160))
                    WKInterfaceDevice.current().play(.click)
                } else { self.note = String((reply["note"] as? String ?? "手机拒绝：过期、未授权或不匹配").prefix(160)) }
            }
        }, errorHandler: { _ in
            DispatchQueue.main.async {
                guard self.pending == command.id else { return }
                self.pending = nil; self.note = "发送失败，不补发"
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard self.pending == command.id else { return }
            self.pending = nil; self.note = "回执超时，不补发"
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.note = error == nil ? "手势测试就绪 · 未连接眼镜" : "手表通信初始化失败" }
    }
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            if !session.isReachable { self.linked = false; self.pending = nil; self.note = "手机不可达；不缓存按键" }
        }
    }
}

@main struct TurboWatchRemoteApp: App {
    @StateObject private var remote = WatchRemote()
    @Environment(\.scenePhase) private var phase
    @State private var settings = false
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(spacing: 6) {
                    Toggle("遥控", isOn: Binding(get: { remote.enabled }, set: { remote.arm($0) }))
                        .font(.caption)
                    HStack {
                        Button { remote.send(.previous) } label: { Label("上一项", systemImage: "chevron.left").labelStyle(.iconOnly).frame(maxWidth: .infinity) }
                            .accessibilityLabel("上一项")
                        Button { remote.send(.next) } label: { Label("下一项", systemImage: "chevron.right").labelStyle(.iconOnly).frame(maxWidth: .infinity) }
                            .accessibilityLabel("下一项")
                            .handGestureShortcut(.primaryAction, isEnabled: remote.mapping == .doubleTapBrowses && !settings)
                    }
                    HStack {
                        Button("确认") { remote.send(.press) }.tint(.green)
                            .handGestureShortcut(.primaryAction, isEnabled: remote.mapping == .doubleTapConfirms && !settings)
                        Button("返回") { remote.send(.back) }
                    }
                    Text(remote.note).font(.caption2).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                    if !remote.linked { Button("连接\(hostName)") { remote.connectProbe() }.font(.caption2) }
                }
                .focusable(!settings)
                .digitalCrownRotation($remote.crownValue, from: -1000, through: 1000, by: 1,
                                      sensitivity: .low, isContinuous: true, isHapticFeedbackEnabled: true)
                .onChange(of: remote.crownValue) { _, value in if !settings { remote.crownChanged(value) } }
                .navigationTitle(remoteTitle)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { remote.arm(false); settings = true } label: { Image(systemName: "gearshape") } } }
                .sheet(isPresented: $settings) {
                    NavigationStack {
                        Form {
                            Text(remoteSummary).font(.caption)
                            Toggle("仅本机识别", isOn: $remote.localOnly)
                            Toggle("反转表冠方向", isOn: $remote.reverseCrown)
                            Picker("手势映射", selection: $remote.mapping) {
                                ForEach(RemoteInputMapping.allCases, id: \.self) { Text($0.title).tag($0) }
                            }
                            if remote.mapping == .doubleTapConfirms { Toggle("反转转腕方向", isOn: $remote.reverse) }
                            Button("重新连接") { remote.connectProbe() }
                            Text("表冠仅在遥控页控制眼镜；设置页用于滚动。设置或退出页面会停止遥控，返回后请重新开启。表冠按压仍为系统功能，确认请点屏幕或用手势。")
                                .font(.caption2)
                        }.navigationTitle("遥控设置")
                    }
                }
            }
            .onChange(of: phase) { _, value in if value != .active { remote.arm(false) } }
        }
    }
}
