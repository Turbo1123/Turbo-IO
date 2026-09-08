import Foundation
import Combine

/// One delivery per authenticated connection, never a discovery/BLE-only event.
@MainActor final class AutomaticWeather: ObservableObject {
    struct Configuration: Codable, Equatable {
        var city = "Beijing, China"
        var enabled = true
        // Explicitly verified provider-code → firmware-code pairs, not numeric equivalence.
        var icons: [String: Int] = [:]
    }
    @Published private(set) var configuration: Configuration
    @Published private(set) var status = "北京天气：等待认证连接；需配置天气 Key 与已验证图标。"
    @Published private(set) var snapshot: WeatherstackSnapshot?
    @Published private(set) var busy = false
    private let defaults: UserDefaults
    private let device: () -> String?
    private let isBusy: () -> Bool
    private let readKey: () -> String?
    private let fetch: WeatherstackController.Fetch
    private let send: (WeatherstackSnapshot, Int) throws -> Void
    private let now: () -> Date
    private let storageKey = "companion.v1.automaticWeather"
    private var connectedDevice: String?
    private var generation = UUID()
    private var pending = false
    private var worker: Task<Void, Never>?
    private var cachedCity: String?
    private var lastFetch: Date?

    init(defaults: UserDefaults, device: @escaping () -> String?, isBusy: @escaping () -> Bool,
         readKey: @escaping () -> String? = WeatherstackVault.read,
         fetch: @escaping WeatherstackController.Fetch = WeatherstackClient.fetch,
         now: @escaping () -> Date = Date.init,
         send: @escaping (WeatherstackSnapshot, Int) throws -> Void) {
        self.defaults = defaults; self.device = device; self.isBusy = isBusy
        self.readKey = readKey; self.fetch = fetch; self.now = now; self.send = send
        if let data = defaults.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode(Configuration.self, from: data),
           (try? WeatherstackRequest.make(city: saved.city, key: "validation-only")) != nil,
           saved.icons.count <= 100, saved.icons.allSatisfy({ Int($0.key) != nil && (0...999).contains($0.value) }) {
            configuration = saved
        } else { configuration = Configuration() }
    }
    func configure(city: String, enabled: Bool) {
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (try? WeatherstackRequest.make(city: city, key: "validation-only")) != nil else {
            status = WeatherstackError.city.localizedDescription; return
        }
        configuration.city = city; configuration.enabled = enabled
        persist(); retry()
    }
    func confirmIcon(providerCode: Int, firmwareCode: Int) {
        guard (0...999).contains(firmwareCode), configuration.icons.count < 100 || configuration.icons[String(providerCode)] != nil else {
            status = WeatherstackError.icon.localizedDescription; return
        }
        configuration.icons[String(providerCode)] = firmwareCode
        persist(); retry()
    }
    private func persist() { if let data = try? JSONEncoder().encode(configuration) { defaults.set(data, forKey: storageKey) } }
    /// Handles credentials added while the connection was already ready.
    func retry() { invalidate(); pending = true; tick() }
    private func invalidate() { generation = UUID(); worker?.cancel(); worker = nil; busy = false }

    /// Reuses the runtime poll; does not start another Bluetooth connection or timer.
    func tick() {
        let current = device()
        if current != connectedDevice { invalidate(); connectedDevice = current; pending = current != nil }
        guard configuration.enabled else { status = "连接自动同步已关闭。"; return }
        guard let current else { status = "天气等待眼镜认证连接。"; return }
        guard pending, worker == nil else { return }
        guard !isBusy() else { status = "天气等待当前语音、录音或提词结束后下发。"; return }
        guard let key = readKey(), !key.isEmpty else {
            pending = false
            status = "\(configuration.city)：未下发，缺少 Weatherstack Key 或钥匙串尚未解锁；配置后点重试。"
            return
        }
        let cached = cachedCity == configuration.city && snapshot?.canSend(at: now()) == true ? snapshot : nil
        // Reconnect storms must not turn into a paid request loop, including failed requests.
        if cached == nil, let lastFetch, now().timeIntervalSince(lastFetch) < 60 {
            status = "天气查询间隔保护：等待满 60 秒后重试，不重复消耗查询额度。"; return
        }
        let token = generation, city = configuration.city
        busy = true; pending = false
        if cached == nil { lastFetch = now() }
        status = cached == nil ? "正在获取 \(city) 实时天气…" : "正在重发本次会话的新鲜天气…"
        worker = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.worker = nil; self.busy = false } }
            do {
                let result: WeatherstackSnapshot
                if let cached { result = cached } else { result = try await self.fetch(city, key) }
                guard !Task.isCancelled, self.generation == token, self.device() == current,
                      self.configuration.enabled, self.configuration.city == city else { return }
                guard result.canSend(at: self.now()) else { throw WeatherstackError.stale }
                self.snapshot = result; self.cachedCity = city
                guard let icon = self.configuration.icons[String(result.providerCode)] else {
                    self.status = "\(result.city) \(result.lensTemperature)°C 已获取，未下发：天气码 \(result.providerCode) 的固件图标尚未核对。"
                    return
                }
                guard !self.isBusy() else { self.pending = true; self.status = "天气已获取，等待眼镜空闲后下发。"; return }
                try self.send(result, icon)
                self.status = "\(result.city) \(result.lensTemperature)°C 已提交到首页天气；回执见设备状态，镜片仍需确认。"
            } catch {
                guard self.generation == token, !Task.isCancelled else { return }
                self.status = (error as? WeatherstackError)?.localizedDescription ?? "天气下发失败；未确认眼镜收到，可手动重试。"
            }
        }
    }
}
