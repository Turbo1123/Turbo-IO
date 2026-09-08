import SwiftUI

struct GlassesRecordingCard: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirmStart = false
    @State private var expanded = false
    var body: some View {
        Card {
            DisclosureGroup(isExpanded:$expanded) {
              VStack(alignment:.leading,spacing:12) {
                Text(features.recordingStatus).font(.caption).foregroundStyle(Palette.muted)
                if features.recordingBytes > 0 { Text("已接收 \(ByteCountFormatter.string(fromByteCount:Int64(features.recordingBytes),countStyle:.file))").font(.caption.monospacedDigit()) }
                Toggle("允许眼镜主动录音保存到本机",isOn:Binding(get:{features.acceptsEyeRecording},set:{features.enableEyeRecording($0)}))
                    .font(.caption).disabled(features.recordingID != nil || !voice.ready)
                if features.recordingID == nil {
                    Button("在眼镜开始录音") { confirmStart = true }.disabled(!voice.ready)
                } else {
                    HStack {
                        Button("暂停") { features.recordingControl(8) }
                        Button("恢复") { features.recordingControl(9) }
                        Button("标记") { features.recordingControl(11) }
                        Button("停止") { features.recordingControl(4) }
                    }.disabled(!voice.ready)
                }
                Text("录音期间暂停语音待命。仅保存音频，不自动 ASR、上传或删除眼镜文件；结束后可到会话页重新开启待命。离线积压导入另行验收。").font(.caption2).foregroundStyle(Palette.muted)
                if let file = features.completedRecording {
                    HStack { ShareLink(item:file) { Label("分享 WAV",systemImage:"square.and.arrow.up") }; Button("重试归档") { Task { await features.archiveReceivedRecording() } } }.font(.caption)
                } else if features.recordingID != nil {
                    Button("完成消息后重新校验") { features.retryRecordingFinish() }.font(.caption)
                }
                if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
              }.padding(.top,12)
            } label: {
                VStack(alignment:.leading,spacing:6) {
                    Label("眼镜录音",systemImage:"mic.badge.plus").font(.headline)
                    Text(features.recordingID == nil ? "展开录音控制 · 默认不采音" : features.recordingStatus).font(.caption2).foregroundStyle(Palette.muted)
                }
            }.accessibilityIdentifier("recording-controls").padding(18)
            NavigationLink("查找重启前的本机接收文件") { RecordingRecoveryView() }
                .font(.caption).padding(.horizontal,18).padding(.bottom,14).accessibilityIdentifier("recording-recovery")
        }
        .confirmationDialog("开始眼镜录音并保存到Turbo IO？会暂停 AI 语音待命，不自动上传。",isPresented:$confirmStart) {
            Button("开始录音") { features.startRecording() }
        }
        .onAppear { features.prepare() }
        .onChange(of:features.recordingID) { if $0 != nil { expanded = true } }
    }
}

struct GlassesTodoSyncCard: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirm = false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            Button("同步本机待办到眼镜") { confirm = true }.disabled(!voice.ready)
            Text(features.todoStatus).font(.caption).foregroundStyle(Palette.muted)
            Text("首次同步经确认；已关联条目在线编辑会尝试发送，离线修改保留待重试。状态冲突不会覆盖手机修改，请到待发送与冲突处理。移除仅本机生效，不删除眼镜旧条目。").font(.caption2).foregroundStyle(Palette.muted)
            if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
        }
        .confirmationDialog("将未移除的本机待办发送到当前眼镜？不覆盖官方其他任务。",isPresented:$confirm) {
            Button("发送本机待办") { features.syncTodos() }
        }.onAppear { features.prepare() }
    }
}

struct GlassesPrompterControls: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    let text: String
    @State private var speed = 120.0
    @State private var confirm = false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("眼镜提词 · 匀速模式").font(.headline)
            Text(features.teleprompterStatus).font(.caption).foregroundStyle(Palette.muted)
            HStack { Text("滚动速度"); Spacer(); Text("\(Int(speed)) 字/分钟候选").monospacedDigit() }.font(.caption)
            Slider(value:$speed,in:60...240,step:10)
            if features.teleprompterID == nil {
                Button("准备并传送当前稿件") { confirm = true }.disabled(!voice.ready || text.isEmpty)
            } else {
                HStack {
                    Button("开始") { features.teleprompterControl(3) }
                    Button("暂停") { features.teleprompterControl(4) }
                    Button("继续") { features.teleprompterControl(5) }
                    Button("退出") { features.teleprompterControl(6) }
                }.disabled(!voice.ready)
                Button("应用滚动速度") { features.teleprompterControl(7,speed:Int(speed)) }.disabled(!voice.ready)
            }
            Text("只发当前分段（最多 12,000 字），不发整本书。收到收稿回应后才允许开始；眼镜上报原始进度，不假装等于手机分页。未启用智能跟读。").font(.caption2).foregroundStyle(Palette.muted)
            if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
        }.padding(16).background(.white,in:RoundedRectangle(cornerRadius:16))
        .confirmationDialog("发送当前文字到眼镜？会暂停 AI 待命；文字只经本地连接传输。",isPresented:$confirm) {
            Button("准备当前稿件") { features.prepareTeleprompter(text,speed:Int(speed)) }
        }.onAppear { features.prepare() }
    }
}

struct GlassesSettingsView: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var location = "协议测试城市"
    @State private var temperature = 27
    @State private var icon = "100"
    @State private var description = "自定义测试天气"
    @State private var confirmWeather = false
    var body: some View {
        Form {
            Section("连接和真实状态") {
                Text(voice.ready ? "已认证连接" : "尚未连接（模拟器不发包）")
                LabeledContent("电量",value:features.battery.map { "\($0)%" } ?? "尚未读取")
                LabeledContent("亮度",value:features.brightness.map(String.init) ?? "尚未读取")
                Button("从眼镜读取状态和设置") { features.refreshSettings() }.disabled(!voice.ready)
                Text(features.status).font(.caption)
            }
            Section("天气服务") {
                NavigationLink("仪表盘实时天气 · 和风") { QWeatherDashboardView() }.accessibilityIdentifier("qweather-entry")
                NavigationLink("旧 Weatherstack 手动查询") { WeatherstackView() }.accessibilityIdentifier("weatherstack-entry")
                Text("专用 Key · 手动查询 · 预览后确认同步。无需定位权限。").font(.caption)
            }
            Section("已核实的设置入口") {
                HStack { Button("亮度 7") { features.setBrightness(7) }; Spacer(); Button("亮度 8") { features.setBrightness(8) } }
                HStack { Button("休眠 15 秒") { features.setSleep(15) }; Spacer(); Button("休眠 25 秒") { features.setSleep(25) } }
                Button("头控开启 · 模式 0") { features.setHeadControl(true,mode:0) }
                Button("头控关闭") { features.setHeadControl(false,mode:0) }
                Button("双击打开待办") { features.setDoubleTapTodo(true) }
                Button("双击恢复 AI") { features.setDoubleTapTodo(false) }
                Button("显示高度档 1") { features.setDisplay(height:1) }
                Button("显示高度档 3") { features.setDisplay(height:3) }
                Button("显示距离档 1") { features.setDisplay(distance:1) }
                Button("显示距离档 2") { features.setDisplay(distance:2) }
                Text("仅开放已有值域证据的子集；不修改未知隐私字段。按钮提交不等于眼镜物理效果已通过。").font(.caption)
            }.disabled(!voice.ready)
            Section("自定义天气 · 非实时气象服务") {
                TextField("城市标签",text:$location)
                Stepper("温度 \(temperature)",value:$temperature,in:-80...60)
                TextField("固件原始图标编号",text:$icon).keyboardType(.numberPad)
                TextField("天气文字",text:$description)
                Button("发送首页测试天气") { confirmWeather = true }.disabled(!voice.ready || Int(icon) == nil)
                Text("只发送内容，不替换已有看板布局。首页小天气与城市卡片是两个通道；图标编号和镜片效果需实机复验。当前没有自动获取位置、联网查天气或后台刷新。").font(.caption)
            }
            if let error = features.error { Section("操作提示") { Text(error).foregroundStyle(Palette.amber) } }
        }.navigationTitle("天气与设备设置")
        .confirmationDialog("把这组明确标记的测试天气发送到眼镜？",isPresented:$confirmWeather) {
            Button("发送自定义数据") { features.sendWeather(location:location,temperature:temperature,icon:Int(icon) ?? 100,description:description) }
        }.onAppear { features.prepare() }
    }
}
