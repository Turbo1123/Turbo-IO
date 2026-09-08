import SwiftUI

struct QWeatherDashboardView: View {
    @EnvironmentObject private var weather: QWeatherDashboard
    @State private var draft = QWeatherConfiguration()
    @State private var key = ""
    @State private var test = false
    @State private var confirmIcon = false
    var body: some View {
        Form {
            Section("仪表盘首页 · 实时天气") {
                Text("这里更新首页的小天气，不更新自选城市天气卡片，也不修改看板布局。")
                    .font(.caption)
                Text(weather.status).accessibilityIdentifier("qweather-status")
                Text(weather.reply).font(.caption).accessibilityIdentifier("qweather-reply")
            }
            Section("和风服务 · 配置保存在本机") {
                TextField("专属 API Host（不含 https://）",text:$draft.host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("qweather-host")
                SecureField("API Key（留空保留该 Host 的 Key）",text:$key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("qweather-key")
                TextField("地点名称",text:$draft.location).accessibilityIdentifier("qweather-location")
                HStack {
                    TextField("纬度",text:$draft.latitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("qweather-latitude")
                    TextField("经度",text:$draft.longitude).keyboardType(.numbersAndPunctuation).accessibilityIdentifier("qweather-longitude")
                }
                Toggle("认证连接后自动更新仪表盘",isOn:$draft.enabled).accessibilityIdentifier("qweather-enabled")
                Button("保存并应用") {
                    draft.host = draft.host.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
                    weather.save(draft,key:key.trimmingCharacters(in:.whitespacesAndNewlines)); key = ""
                }.disabled(weather.busy).accessibilityIdentifier("qweather-save")
                Text("保存后连接状态下会查询所填坐标，可能消耗额度；不获取手机定位。Key 按 Host 隔离存入本机钥匙串，首次解锁后可供后台读取。不发送录音或聊天。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("查询与下发") {
                Button("重新获取 / 重试首页下发") { weather.retry() }.disabled(weather.busy).accessibilityIdentifier("qweather-refresh")
                if let s = weather.snapshot {
                    Text("\(weather.configuration.location) · \(s.condition) · \(String(format:"%.2f",s.temperature))°C → 镜片 \(s.lensTemperature)°C")
                        .accessibilityIdentifier("qweather-preview")
                    Text("获取：\(s.fetchedAt.formatted(date:.omitted,time:.standard))；本机缓存最多 10 分钟。接口没有观测时间，获取时间不代表观测时间。")
                        .font(.caption)
                    Text("来源：和风天气 QWeather").font(.caption)
                    ForEach(s.attributions,id:\.self) { Text($0).font(.caption2).textSelection(.enabled) }
                    Text("天气码 \(s.code) 不自动等于固件图标；先发送同号候选测试，目视核对后才能启用该类型自动下发。")
                        .font(.caption)
                    Button("发送仪表盘候选测试") { test = true }.disabled(weather.busy).accessibilityIdentifier("qweather-test-dashboard")
                    Button("镜片图标已核对，保存映射") { confirmIcon = true }.disabled(weather.busy).accessibilityIdentifier("qweather-confirm-icon")
                }
            }
        }
        .navigationTitle("仪表盘天气")
        .preference(key:CompanionTabBarHiddenPreference.self,value:true)
        .onAppear { draft = weather.configuration }
        .onDisappear { key = "" }
        .confirmationDialog("向仪表盘首页发送真实温度和待验的同号图标？不会修改天气卡片。",isPresented:$test) {
            Button("发送一次首页测试") { weather.testCandidate() }
        }
        .confirmationDialog("仅在已看到眼镜首页温度与正确天气图标后确认。协议回执不能代替目视验收。",isPresented:$confirmIcon) {
            Button("已目视确认图标正确") { weather.confirmDisplayedIcon(); draft = weather.configuration }
        }
    }
}
