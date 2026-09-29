import SwiftUI
import WatchConnectivity

// Isolated receive-only probe. Never imports Bluetooth or the official addon.
final class PhoneProbe: NSObject, ObservableObject, WCSessionDelegate {
    @Published var enabled = false
    @Published var received = 0
    @Published var note = "等待 Watch；此 App 不连接眼镜"
    private var gate = RemoteGate()
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            guard self.enabled else { replyHandler(["result": "disabled"]); return }
            if message["kind"] as? String == "turbo.remote.hello",
               let text = message["session"] as? String, let sid = UUID(uuidString: text) {
                self.gate.begin(sid)
                self.note = "Watch 已连接；仅记录输入，不控制眼镜"
                replyHandler(["mode": "observe-only", "session": sid.uuidString]); return
            }
            guard message["kind"] as? String == "turbo.remote.command",
                  let data = message["data"] as? Data, data.count <= 512,
                  let command = try? JSONDecoder().decode(RemoteCommand.self, from: data),
                  self.gate.accept(command, now: Date().timeIntervalSince1970, enabled: self.enabled) else {
                replyHandler(["result": "rejected"]); return
            }
            self.received += 1
            self.note = "收到 \(command.action.title) #\(command.sequence)；眼镜未执行"
            replyHandler(["id": command.id.uuidString, "result": "observed"])
        }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

@main struct TurboWatchProbeApp: App {
    @StateObject private var probe = PhoneProbe()
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                Form {
                    Section("R0 · 只测试手表到手机") {
                        Toggle("允许本轮接收", isOn: $probe.enabled)
                        LabeledContent("接收次数", value: "\(probe.received)")
                        Text(probe.note)
                    }
                    Section("边界") {
                        Text("这不是雷鸟插件，没有蓝牙或固件发送能力。收到回执仅说明手机已接收，不能代表眼镜响应。")
                        Text("在 Watch 开启本轮测试；先用仅本机识别校准转腕，再连接手机测试器并关闭仅本机识别。")
                    }
                }.navigationTitle("Turbo Watch 测试")
            }
        }
    }
}
