import Foundation
import Network
import SwiftUI

/// Loopback only, intended for a trusted USB usbmux tunnel, not a LAN service.
@MainActor final class DisplayObserverServer: ObservableObject {
    static let shared = DisplayObserverServer()
    @Published private(set) var running = false
    @Published private(set) var status = "已关闭；不会导出观察数据"
    @Published private(set) var token = ""
    private var listener: NWListener?
    private var clients: [UUID:NWConnection] = [:]
    private var expiry: Timer?
    let observation = DisplayObservation.shared
    func start() {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: 18765)
        do {
            let value = try NWListener(using: parameters)
            listener = value; token = UUID().uuidString.replacingOccurrences(of:"-",with:"")
            observation.reset(); observation.enabled = true; status = "启动中"
            value.stateUpdateHandler = { [weak self, weak value] state in
                Task { @MainActor in
                guard let self, self.listener === value else { return }
                switch state {
                case .ready: self.running = true; self.status = "USB 观察接口已开启 · 30分钟后自动关闭"
                case .failed: self.stop(); self.status = "接口启动失败；未暴露局域网端口"
                default: break
                }
                }
            }
            value.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    guard let self, self.listener != nil else { connection.cancel(); return }
                    self.accept(connection)
                }
            }
            value.start(queue:.main)
            expiry = Timer.scheduledTimer(withTimeInterval:1800,repeats:false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        } catch { stop(); status = "观察接口不可用" }
    }
    func stop() {
        expiry?.invalidate(); expiry = nil
        listener?.cancel(); listener = nil
        for c in clients.values { c.cancel() }; clients.removeAll()
        observation.enabled = false; observation.includesText = false; observation.reset()
        token = ""; running = false; status = "已关闭并清空本轮观察数据"
    }
    private func accept(_ connection: NWConnection) {
        guard clients.count < 8 else { connection.cancel(); return }
        let id = UUID(); clients[id] = connection
        connection.start(queue:.main)
        DispatchQueue.main.asyncAfter(deadline:.now()+4) { [weak self] in self?.close(id) }
        read(connection,id:id,buffer:Data())
    }
    private func close(_ id: UUID) { clients.removeValue(forKey:id)?.cancel() }
    private func read(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength:1,maximumLength:4096) { [weak self] data, _, done, error in
            Task { @MainActor in
            guard let self, self.clients[id] != nil else { return }
            var all = buffer; if let data { all.append(data) }
            guard all.count <= 8192, error == nil else { self.close(id); return }
            if all.range(of:Data("\r\n\r\n".utf8)) != nil {
                let authorized = Self.authorized(all,token:self.token)
                let body = authorized ? (try? JSONSerialization.data(withJSONObject:self.observation.snapshot())) ?? Data("{}".utf8) : Data("{\"error\":\"unauthorized\"}".utf8)
                var response = Data("HTTP/1.1 \(authorized ? "200 OK" : "403 Forbidden")\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8)
                response.append(body)
                connection.send(content:response,completion:.contentProcessed { [weak self] _ in
                    Task { @MainActor in self?.close(id) }
                })
            } else if done { self.close(id) }
            else { self.read(connection,id:id,buffer:all) }
            }
        }
    }
    static func authorized(_ data: Data, token: String) -> Bool {
        guard token.count == 32, data.count <= 8192, let text = String(data:data,encoding:.utf8) else { return false }
        let lines = text.components(separatedBy:"\r\n")
        guard lines.first == "GET /snapshot HTTP/1.1", lines.last == "" else { return false }
        let headers = lines.dropFirst().filter { !$0.isEmpty }
        guard !headers.contains(where: { $0.lowercased().hasPrefix("origin:") || $0.lowercased().hasPrefix("transfer-encoding:") }) else { return false }
        let auth = headers.filter { $0.lowercased().hasPrefix("authorization:") }
        return auth.count == 1 && auth[0].dropFirst("authorization:".count).trimmingCharacters(in:.whitespaces) == "Bearer \(token)"
    }
}

struct DisplayObserverView: View {
    @ObservedObject private var server = DisplayObserverServer.shared
    @ObservedObject private var observation = DisplayObservation.shared
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                Text("显示观察 · USB").font(.title2.bold())
                Text("只读回传页面状态；模拟预览不是镜片截图。不会开启录音、调用模型或改变眼镜页面。")
                Text(server.status).accessibilityIdentifier("display-observer-status")
                Toggle("包含本轮发送文字",isOn:$observation.includesText).accessibilityIdentifier("display-observer-text")
                Text("仅在开启期间收集，最多80条事件；文字不写入日志或磁盘。关闭会清空缓存与令牌。若 App 被挂起，电脑会显示数据失联。")
                    .font(.caption).foregroundStyle(.secondary)
                Button(server.running ? "关闭观察接口" : "开启 USB 观察接口") { server.running ? server.stop() : server.start() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("display-observer-toggle")
                if server.running {
                    Text("在电脑观察页输入一次性令牌：").font(.caption)
                    Text(server.token).font(.system(.caption,design:.monospaced)).textSelection(.enabled)
                        .accessibilityIdentifier("display-observer-token")
                    Button("复制令牌") { UIPasteboard.general.setItems([["public.utf8-plain-text":server.token]],options:[.localOnly:true,.expirationDate:Date().addingTimeInterval(120)]) }
                    Text("USB 转发端口 18765 · 仅本机回环地址可访问 · 不依赖越狱")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.navigationTitle("显示观察").navigationBarTitleDisplayMode(.inline)
    }
}
