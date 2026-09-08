import Foundation
import Security
import Combine

enum WeatherstackError: LocalizedError, Equatable {
    case key, city, invalid, unit, remote(Int?), network, oversized, stale, icon
    var errorDescription: String? {
        switch self {
        case .key: return "请先保存 Weatherstack 专用 Key；不会复用语音或模型密钥。"
        case .city: return "请输入城市及国家（最多 160 字节），不支持批量或自动 IP 定位。"
        case .invalid: return "天气响应缺少有效字段，未生成可发送的天气。"
        case .unit: return "天气响应不是摄氏单位 m，已拒绝发送，避免温标混淆。"
        case .remote(let code): return "Weatherstack 未返回成功数据" + (code.map { "（代码 \($0)）" } ?? "") + "。请检查 Key、城市与套餐额度；不自动重试或降级 HTTP。"
        case .network: return "天气请求失败或超时；没有发送到眼镜。请检查网络后手动重试。"
        case .oversized: return "天气响应超过本机 256 KiB 上限，已停止读取。"
        case .stale: return "这份天气日期过旧、时间缺失或不是本次实时查询，不能作为当前天气发送。"
        case .icon: return "请填写已确认的固件原始图标编号；不能直接使用 Weatherstack 的 weather_code。"
        }
    }
}

struct WeatherstackSnapshot: Equatable {
    let city: String
    let country: String
    let celsius: Double
    let description: String
    let providerCode: Int
    let sourceLocalTime: String
    let sourceDate: Date?
    let observedAt: Date?
    let fetchedAt: Date
    let usedLegacyTemperatureKey: Bool
    let isSample: Bool
    var lensTemperature: Int { Int(celsius.rounded()) }

    // App freshness policy, not a claim about provider/firmware TTL. No timestamp rebasing.
    func canSend(at now: Date) -> Bool {
        guard !isSample, let sourceDate, let observedAt else { return false }
        return [sourceDate, observedAt].allSatisfy { (-600...10_800).contains(now.timeIntervalSince($0)) }
            && (0...1_800).contains(now.timeIntervalSince(fetchedAt))
    }
}

enum WeatherstackCodec {
    static let limit = 256 * 1_024
    private struct Envelope: Decodable {
        struct Request: Decodable { let unit: String }
        struct Location: Decodable {
            let name: String, country: String
            let timezone_id: String?, localtime: String?
        }
        struct Current: Decodable {
            let temperature: Double?, temparature: Double?
            let weather_code: Int
            let weather_descriptions: [String]
            let observation_time: String?
        }
        let request: Request, location: Location, current: Current
    }

    static func decode(_ data: Data, fetchedAt: Date = Date(), sample: Bool = false) throws -> WeatherstackSnapshot {
        guard data.count <= limit else { throw WeatherstackError.oversized }
        guard let root = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw WeatherstackError.invalid }
        if root["error"] != nil || (root["success"] as? Bool) == false {
            let code = (root["error"] as? [String:Any]).flatMap { DeviceBusinessWire.integer($0,"code") }.flatMap(Int.init(exactly:))
            // Never expose remote info/type: it may contain the request URL or credential.
            throw WeatherstackError.remote(code)
        }
        guard let value = try? JSONDecoder().decode(Envelope.self,from:data) else { throw WeatherstackError.invalid }
        guard value.request.unit == "m" else { throw WeatherstackError.unit }
        let city = value.location.name.trimmingCharacters(in:.whitespacesAndNewlines)
        let temperature = value.current.temperature ?? value.current.temparature
        guard !city.isEmpty, city.utf8.count <= 80, !city.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains),
              value.location.country.utf8.count <= 160,
              let temperature, temperature.isFinite, (-80...60).contains(temperature),
              (0...9_999).contains(value.current.weather_code),
              let description = value.current.weather_descriptions.first, !description.isEmpty, description.utf8.count <= 512 else {
            throw WeatherstackError.invalid
        }
        let localText = value.location.localtime ?? ""
        let localDate = sourceDate(localText,zone:value.location.timezone_id)
        return WeatherstackSnapshot(city:city,country:value.location.country,celsius:temperature,description:description,
            providerCode:value.current.weather_code,sourceLocalTime:localText,sourceDate:localDate,
            observedAt:observation(value.current.observation_time,localDate:localDate),fetchedAt:fetchedAt,
            usedLegacyTemperatureKey:value.current.temperature == nil,isSample:sample)
    }
    private static func sourceDate(_ text: String, zone: String?) -> Date? {
        guard text.count == 16, let zone, let timeZone = TimeZone(identifier:zone) else { return nil }
        let parser = DateFormatter(); parser.locale = Locale(identifier:"en_US_POSIX")
        parser.calendar = Calendar(identifier:.gregorian); parser.timeZone = timeZone
        parser.dateFormat = "yyyy-MM-dd HH:mm"; parser.isLenient = false
        guard let date = parser.date(from:text), parser.string(from:date) == text else { return nil }
        return date
    }
    private static func observation(_ text: String?, localDate: Date?) -> Date? {
        guard let text, let localDate, text.count <= 8 else { return nil }
        let parser = DateFormatter(); parser.locale = Locale(identifier:"en_US_POSIX")
        parser.calendar = Calendar(identifier:.gregorian); parser.timeZone = TimeZone(secondsFromGMT:0)
        parser.dateFormat = "hh:mm a"; parser.isLenient = false
        guard let time = parser.date(from:text) else { return nil }
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
        let parts = calendar.dateComponents([.hour,.minute],from:time)
        let start = calendar.startOfDay(for:localDate)
        var date = start.addingTimeInterval(Double((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60))
        // observation_time is UTC without a date; nearest non-future UTC day, including midnight.
        if date.timeIntervalSince(localDate) > 600 { date = date.addingTimeInterval(-86_400) }
        return date
    }

    // User-provided 2019 sample, deliberately misspelled legacy key. Never sent as live data.
    static let historicalSample = Data(#"{"request":{"unit":"m"},"location":{"name":"San Francisco","country":"United States of America","timezone_id":"America/Los_Angeles","localtime":"2019-09-03 05:35"},"current":{"observation_time":"12:35 PM","temparature":16,"weather_code":122,"weather_descriptions":["Overcast"]}}"#.utf8)
}

enum WeatherstackVault {
    private static let service = "io.turboio.companion.weatherstack"
    private static var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword,
        kSecAttrService as String:service,kSecAttrAccount as String:"api.weatherstack.com"] }
    static func read() -> String? {
        var item: CFTypeRef?
        let request = query.merging([kSecReturnData as String:true,kSecMatchLimit as String:kSecMatchLimitOne]) { _,new in new }
        guard SecItemCopyMatching(request as CFDictionary,&item) == errSecSuccess, let bytes = item as? Data else { return nil }
        return String(data:bytes,encoding:.utf8)
    }
    static func save(_ input: String) throws {
        let key = try WeatherstackRequest.validatedKey(input)
        let attributes: [String:Any] = [kSecValueData as String:Data(key.utf8),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary,attributes as CFDictionary)
        if result == errSecItemNotFound {
            let inserted = SecItemAdd(query.merging(attributes) { _,new in new } as CFDictionary,nil)
            guard inserted == errSecSuccess else { throw ConfigurationError.keychain(inserted) }
        } else if result != errSecSuccess { throw ConfigurationError.keychain(result) }
    }
    static func remove() throws {
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw ConfigurationError.keychain(result) }
    }
}

enum WeatherstackRequest {
    static func validatedKey(_ input: String) throws -> String {
        let key = input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (8...256).contains(key.utf8.count), key.utf8.allSatisfy({ (33...126).contains($0) }) else { throw WeatherstackError.key }
        return key
    }
    static func make(city: String, key: String) throws -> URLRequest {
        let query = city.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty, query.utf8.count <= 160, !query.contains(";"), query.lowercased() != "fetch:ip",
              !query.unicodeScalars.contains(where:CharacterSet.controlCharacters.contains) else { throw WeatherstackError.city }
        var components = URLComponents(string:"https://api.weatherstack.com/current")!
        components.queryItems = [URLQueryItem(name:"access_key",value:try validatedKey(key)),
            URLQueryItem(name:"query",value:query), URLQueryItem(name:"units",value:"m")]
        guard let url = components.url else { throw WeatherstackError.city }
        var request = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        return request // This URL contains a secret. Never log the request or underlying URL errors.
    }
}

private final class WeatherstackNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

enum WeatherstackClient {
    static func fetch(city: String, key: String) async throws -> WeatherstackSnapshot {
        let request = try WeatherstackRequest.make(city:city,key:key)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration:config,delegate:WeatherstackNoRedirect(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        do {
            let (stream,response) = try await session.bytes(for:request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw WeatherstackError.remote((response as? HTTPURLResponse)?.statusCode)
            }
            guard response.expectedContentLength <= WeatherstackCodec.limit else { throw WeatherstackError.oversized }
            var data = Data()
            for try await byte in stream {
                try Task.checkCancellation()
                guard data.count < WeatherstackCodec.limit else { throw WeatherstackError.oversized }
                data.append(byte)
            }
            return try WeatherstackCodec.decode(data)
        } catch let error as WeatherstackError { throw error }
        catch { throw WeatherstackError.network } // No URL/Key in displayed/logged error descriptions.
    }
}

@MainActor final class WeatherstackController: ObservableObject {
    typealias Fetch = (String,String) async throws -> WeatherstackSnapshot
    @Published private(set) var snapshot: WeatherstackSnapshot?
    @Published private(set) var busy = false
    @Published private(set) var message = "手动查询后预览，不自动发送、不后台刷新。"
    @Published private(set) var hasKey = false
    private let fetch: Fetch
    private let readKey: () -> String?
    init(fetch: @escaping Fetch = WeatherstackClient.fetch, readKey: @escaping () -> String? = WeatherstackVault.read) {
        self.fetch = fetch; self.readKey = readKey; hasKey = readKey() != nil
    }
    func saveKey(_ key: String) {
        do { try WeatherstackVault.save(key); hasKey = true; message = "天气 Key 已存到本机钥匙串，尚未联网。" }
        catch { message = error.localizedDescription }
    }
    func removeKey() {
        do { try WeatherstackVault.remove(); hasKey = false; snapshot = nil; message = "天气 Key 已从本机钥匙串移除。" }
        catch { message = error.localizedDescription }
    }
    func previewSample() {
        guard !busy else { return }
        snapshot = try? WeatherstackCodec.decode(WeatherstackCodec.historicalSample,sample:true)
        message = "2019 年离线示例，未联网；仅预览，禁止作为当前天气发送。"
    }
    func refresh(city: String) async {
        guard !busy else { return }
        guard let key = readKey() else { message = WeatherstackError.key.localizedDescription; return }
        busy = true; snapshot = nil; message = "正在查询 Weatherstack…"
        defer { busy = false }
        do {
            let result = try await fetch(city,key)
            guard !Task.isCancelled else { message = "查询已取消。"; return }
            snapshot = result
            message = result.canSend(at:Date()) ? "已获取，尚未发送到眼镜。" : WeatherstackError.stale.localizedDescription
        } catch { message = (error as? WeatherstackError ?? .network).localizedDescription }
    }
}
