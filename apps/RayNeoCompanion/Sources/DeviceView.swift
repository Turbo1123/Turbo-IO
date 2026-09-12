import SwiftUI

struct DeviceView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var runtime: CompanionVoiceRuntime
    @EnvironmentObject private var automaticWeather: AutomaticWeather
    @EnvironmentObject private var qweather: QWeatherDashboard
    @State private var showSettings = false
    @State private var showConnection = false

    var body: some View {
        Screen(title: "我的眼镜", eyebrow: "Norman IO · 你的本地智能眼镜助手", headerIcon: "gearshape", headerAction: { showSettings = true }) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image("NormanIOMark").resizable().scaledToFit()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityHidden(true)
                    Text("RayNeo iO").font(.system(size: 25, weight: .semibold))
                    Spacer()
                    if store.demoMode { Badge(text: "演示界面", active: true) }
                }
                Text(runtime.ready ? "已认证连接" : "尚未连接").font(.system(size: 15, weight: .medium))
                GlassesIllustration().padding(.horizontal, 15).padding(.vertical, 28)
                Text("眼镜轮廓示意 · 非设备实时状态").font(.system(size: 9)).foregroundStyle(Palette.mint.opacity(0.5))
            }
            .padding(22).foregroundStyle(.white)
            .background(LinearGradient(colors: [Palette.ink, Color(red: 0.10, green: 0.24, blue: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

            if runtime.supportsDevice {
                PrimaryButton(title: "发现配对中的眼镜", icon: "antenna.radiowaves.left.and.right", enabled: !runtime.enabled) { runtime.discover() }
                Button("连接唯一发现的眼镜") { runtime.connect() }.disabled(runtime.enabled)
                Button("重连本 App 已绑定眼镜") { runtime.reconnectBonded() }
                    .accessibilityIdentifier("reconnect-bonded")
                Text(runtime.latestEvent).font(.caption).foregroundStyle(Palette.muted)
            } else {
                PrimaryButton(title: "模拟器不连接眼镜", icon: "link", enabled: false) {}
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                Button { store.selectedTab = 1 } label: { shortcut("mic", title: "语音助手", subtitle: "语音识别与对话") }.buttonStyle(.plain)
                Button { store.selectedTab = 2 } label: { shortcut("folder", title: "录音归档", subtitle: "管理本地音频") }.buttonStyle(.plain)
                NavigationLink { PrompterView() } label: { shortcut("text.alignleft", title: "提词器", subtitle: "编辑与手机预览") }.buttonStyle(.plain)
                NavigationLink { TodoView() } label: { shortcut("checkmark.circle", title: "待办清单", subtitle: "记录与管理任务") }.buttonStyle(.plain)
            }
            NavigationLink { QWeatherDashboardView() } label: {
                Label(qweather.status, systemImage: "cloud.sun")
                    .font(.caption).foregroundStyle(Palette.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityIdentifier("device-weather-status")
            Button { showConnection = true } label: {
                Label("本地功能可用，眼镜控制待验证", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Palette.green).padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 15))
            }.buttonStyle(.plain)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { runtime.prepare() }
        .sheet(isPresented: $showConnection) { ConnectionBoundaryView() }
    }

    private func shortcut(_ icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 25, weight: .light)).foregroundStyle(Palette.ink)
                .frame(width: 34, height: 38).background(Palette.mint.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }.padding(14).frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(Palette.line.opacity(0.6), lineWidth: 0.75))
    }
}

struct ConnectionBoundaryView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "link.badge.plus").font(.system(size: 35, weight: .light)).foregroundStyle(Palette.green)
                    Text("连接，有清晰的边界。").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("Turbo IO使用独立 Bundle 与沙盒。真机构建已接入原型通信核心与语音链路；模拟器构建不加载厂商库或发蓝牙指令。新 App 的配对、后台与镜片效果还需真机复验。")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                    Card {
                        FeatureRow(icon: "iphone", title: "手机侧本地功能", subtitle: "草稿、导入、配置与状态演示", status: "可使用", active: true)
                        FeatureRow(icon: "link", title: "连接、认证与解绑", subtitle: "真机复用原型核心；不自动解绑或重置")
                        FeatureRow(icon: "eyeglasses", title: "镜片显示与反向事件", subtitle: "必须在实际眼镜上逐项验收")
                        FeatureRow(icon: "signature", title: "非越狱签名设备", subtitle: "模拟器构建不代表非越狱通道已验证", status: "待实机")
                    }
                    Text("不会操作固件、解绑官方账号、自动打开麦克风或上传录音。")
                        .font(.footnote).foregroundStyle(Palette.green)
                }.padding(24)
            }.background(Palette.background).navigationTitle("连接进度").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
