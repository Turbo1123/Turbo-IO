import SwiftUI

struct RecordingRecoveryView: View {
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @State private var selected: String?
    @State private var raw: URL?
    var body: some View {
        List {
            Section("只处理Turbo IO本机文件") {
                Text("用于 App 重启后的接收文件找回。不会连接眼镜、开录、申请离线补传或删除原件。已封装的旧任务，或保留结束记录且覆盖无空洞的任务，才可尝试恢复。")
                    .font(.caption)
                Button("扫描本机接收目录") { Task { await features.loadRecoveryEntries() } }
                    .disabled(features.recoveryBusy || features.recordingID != nil).accessibilityIdentifier("recovery-scan")
                Text(features.recoveryStatus).font(.caption).accessibilityIdentifier("recovery-status")
                if features.recoveryBusy { ProgressView() }
            }
            if features.recoveryEntries.isEmpty {
                Text("没有可列出的本机接收记录").foregroundStyle(.secondary).accessibilityIdentifier("recovery-empty")
            }
            ForEach(features.recoveryEntries) { entry in
                Section("本机接收：" + entry.createdAt.formatted(date:.abbreviated,time:.shortened)) {
                    Text(entry.status).font(.subheadline)
                    Text("已记录 \(ByteCountFormatter.string(fromByteCount:Int64(entry.receivedBytes),countStyle:.file)) · 本机编号 \(entry.id.prefix(8))").font(.caption)
                    Button("重新校验、解码并归档") { selected = entry.id }
                        .disabled(!entry.mayRecover || features.recoveryBusy || features.recordingID != nil)
                    Button("准备分享原始 rawopus（未验完整）") {
                        Task { raw = await features.recoveryRawFile(entry.id) }
                    }.disabled(features.recoveryBusy || features.recordingID != nil)
                }
            }
            if let raw {
                Section("原始数据，不是可播放录音证明") {
                    Text("该 rawopus 可能不完整，仅用于备份/研究。没有音频修复或 ASR。打开分享面板不代表远端收到。").font(.caption)
                    ShareLink(item:raw) { Label("分享选中的原始文件",systemImage:"square.and.arrow.up") }
                }
            }
        }.navigationTitle("本机接收恢复")
        .task { await features.loadRecoveryEntries() }
        .onDisappear { raw = nil }
        .confirmationDialog("仅恢复这一条本机文件：重新校验、解码并归档，不上传或删除。",isPresented:Binding(get:{ selected != nil },set:{ if !$0 { selected = nil } })) {
            Button("尝试本地恢复") {
                if let id = selected { Task { await features.recoverRecording(id) } }
                selected = nil
            }
        }
    }
}
