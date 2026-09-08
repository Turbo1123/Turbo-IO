import SwiftUI

struct WeatherstackView: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @EnvironmentObject private var automatic: AutomaticWeather
    @StateObject private var weather = WeatherstackController()
    @State private var city = "Beijing, China"
    @State private var key = ""
    @State private var rawIcon = ""
    @State private var acknowledgedIcon = false
    @State private var confirmQuery = false
    @State private var confirmSend = false
    @State private var lookup: Task<Void,Never>?

    var body: some View {
        Form {
            Section("认证连接后自动同步") {
                Text("旧版配置已由和风仪表盘天气接管，不再由连接事件自动触发此服务。此页查询和重试为手动操作。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("连接 / 重连后同步首页天气", isOn: Binding(
                    get: { automatic.configuration.enabled },
                    set: { automatic.configure(city: automatic.configuration.city, enabled: $0) }))
                    .accessibilityIdentifier("weather-auto-enabled")
                Text("已选城市：\(automatic.configuration.city)").font(.caption)
                Text(automatic.status).font(.caption).accessibilityIdentifier("weather-auto-status")
                Text("只在认证连接后获取并下发；新鲜结果可用于重连。不会改看板布局；录音、对话或提词中会延后。需天气专用 Key 和已核对的图标映射。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重试自动同步") { automatic.retry() }.disabled(automatic.busy)
                    .accessibilityIdentifier("weather-auto-retry")
                if let result = automatic.snapshot {
                    Text("自动查询：\(result.city) \(result.lensTemperature)°C · \(result.description) · 天气码 \(result.providerCode)").font(.caption)
                }
            }
            Section("Weatherstack · 实时天气") {
                Text("查询仅发送你填写的城市给 Weatherstack，可能消耗额度。不获取手机定位，不传聊天、录音或眼镜身份。")
                    .font(.caption).foregroundStyle(.secondary)
                SecureField(weather.hasKey ? "新 Key（留空保留原 Key）" : "Weatherstack API Key",text:$key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("weather-key")
                HStack {
                    Button("安全保存 Key") { weather.saveKey(key); key = ""; automatic.retry() }.disabled(key.isEmpty || weather.busy)
                    Spacer()
                    Button("移除 Key",role:.destructive) { weather.removeKey(); automatic.retry() }.disabled(!weather.hasKey || weather.busy)
                }
                TextField("城市及国家",text:$city).autocorrectionDisabled().accessibilityIdentifier("weather-city")
                Button("保存为自动同步城市") {
                    automatic.configure(city:city, enabled:automatic.configuration.enabled)
                }.accessibilityIdentifier("weather-auto-city-save")
                Button(weather.busy ? "查询中…" : "查询并预览（不发送）") { confirmQuery = true }
                    .disabled(weather.busy || !weather.hasKey || city.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("weather-query")
                Button("查看你提供的 2019 示例") { weather.previewSample() }
                    .disabled(weather.busy).accessibilityIdentifier("weather-sample")
                Text(weather.message).font(.caption).accessibilityIdentifier("weather-status")
            }
            if let result = automatic.snapshot, !result.isSample {
                Section("核对自动天气图标") {
                    Text("为 Weatherstack 天气码 \(result.providerCode) 保存已验证的固件图标；天气类型变化后，未核对的新代码会暂停下发。")
                        .font(.caption)
                    TextField("固件图标编号", text:$rawIcon).keyboardType(.numberPad)
                    Toggle("已核对该图标映射", isOn:$acknowledgedIcon)
                    Button("保存图标映射并重试") {
                        guard acknowledgedIcon, let icon = validIcon else { return }
                        automatic.confirmIcon(providerCode:result.providerCode, firmwareCode:icon)
                    }.disabled(!acknowledgedIcon || validIcon == nil || automatic.busy)
                }
            }
            if let snapshot = weather.snapshot {
                Section(snapshot.isSample ? "历史示例 · 不可发送" : "查询结果 · 尚未同步") {
                    LabeledContent(snapshot.city,value:String(format:"%g °C",snapshot.celsius))
                        .accessibilityIdentifier("weather-preview")
                    Text(snapshot.description)
                    Text("当地时间：\(snapshot.sourceLocalTime.isEmpty ? "缺失" : snapshot.sourceLocalTime)").font(.caption)
                    Text("Weatherstack 代码：\(snapshot.providerCode)（不是眼镜图标编号）").font(.caption)
                    if snapshot.usedLegacyTemperatureKey {
                        Text("兼容样本的 temparature 拼写，正式 temperature 字段优先。").font(.caption2)
                    }
                    Text("首页协议只承载地点、整数温度和固件图标；风速、空气质量、月相等字段暂不下发。").font(.caption)
                }
                Section("同步首页天气") {
                    TextField("已验证的固件原始图标编号",text:$rawIcon).keyboardType(.numberPad)
                    Toggle("我已核对这个固件图标码",isOn:$acknowledgedIcon)
                    Text("供应商代码没有已验证的自动映射，不用 122 猜眼镜图标。温度四舍五入为整数；不会替换现有看板布局。").font(.caption)
                    Button("同步查询结果到眼镜") { confirmSend = true }
                        .disabled(!voice.ready || !snapshot.canSend(at:Date()) || !acknowledgedIcon || validIcon == nil || weather.busy)
                        .accessibilityIdentifier("weather-send")
                    Text(features.status).font(.caption)
                    if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                }
            }
        }.navigationTitle("Weatherstack 天气")
        .confirmationDialog("将填写的城市发送到 Weatherstack 查询一次？可能消耗套餐额度。",isPresented:$confirmQuery) {
            Button("查询一次") { lookup = Task { await weather.refresh(city:city) } }
        }
        .confirmationDialog("将预览中的温度和指定固件图标发送到眼镜首页？",isPresented:$confirmSend) {
            Button("确认同步") {
                guard let snapshot = weather.snapshot, acknowledgedIcon, let icon = validIcon else { return }
                features.sendWeatherstack(snapshot,icon:icon)
            }
        }
        .onChange(of:rawIcon) { _ in acknowledgedIcon = false }
        .onAppear { city = automatic.configuration.city }
        .onDisappear { lookup?.cancel(); key = "" }
    }
    private var validIcon: Int? { guard let n = Int(rawIcon), (0...999).contains(n) else { return nil }; return n }
}
