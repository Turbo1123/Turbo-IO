import SwiftUI
import RayNeoArchive
import RayNeoAudioContainer

struct AudioContainerInspectionView: View {
    @EnvironmentObject private var archive: LocalArchiveController
    @EnvironmentObject private var inspection: AudioContainerInspectionController
    let recordingID: UUID
    private var recording: ArchivedRecording? { archive.recordings.first { $0.id == recordingID } }
    private var issue: String? { archive.verificationIssues[recordingID] }
    private var ownResult: AudioContainerCheckResult? { inspection.result?.identity.recordingID == recordingID ? inspection.result : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("本机结构检查", systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(Palette.mint)
                    Text("容器通过，不等于声音可用。").font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("只检查一个 Ogg / Opus 声明子集，不播放、不解码、不运行语音识别。")
                        .font(.caption).foregroundStyle(Palette.mint.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                if let recording {
                    Card {
                        Text(recording.title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                        Text("文件 \(ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file)) · 检查上限 64 MiB")
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text("归档记录 SHA-256\n\(recording.sha256)").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    }
                    if let issue {
                        Label("归档校验存在异常，请返回详情先完整复核。\n\(issue)", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Palette.amber)
                    }
                    operationControls(recording)
                } else { Text("此录音不在当前归档中，请返回刷新。").foregroundStyle(Palette.amber) }

                if let message = inspection.message, inspection.identity?.recordingID == recordingID {
                    Text(message).font(.caption).foregroundStyle(Palette.amber).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("container-check-message")
                }
                if let result = ownResult { resultView(result) }
                Card {
                    Text("检查范围与资源").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text("单流、非串接、Opus v1、mapping 0、1 或 2 声道。CRC、页序、包边界和 granule 只提供结构证据，不证明原始无线无丢包。")
                    Text("64 KiB 分块读；输入上限 64 MiB、包上限 1 MiB。超过预算停止，不自动加大。仅一个检查任务，不建立等待队列。")
                    Text("离开此页会取消并清除结果；重新进入不自动检查。文件变化或归档异常使旧结果失效。取消后须等资源释放才能重新开始。")
                }.font(.caption).foregroundStyle(Palette.muted)
            }.padding(24)
        }.background(Palette.background).navigationTitle("音频容器检查").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onDisappear { inspection.leave(recordingID: recordingID) }
    }

    @ViewBuilder private func operationControls(_ recording: ArchivedRecording) -> some View {
        if ownResult != nil {
            PrimaryButton(title: "清除结果以重新检查", icon: "arrow.counterclockwise") { inspection.clear() }
                .accessibilityIdentifier("container-clear")
            Text("仅清除界面结果，不删除音频或笔记。").font(.caption2).foregroundStyle(Palette.muted)
        } else if !inspection.canStart {
            ProgressView(value: inspection.progress?.fraction ?? 0) {
                Text(inspection.phase == .preparing ? "正在核验本机归档副本…" : (inspection.phase == .reading ? "正在分块检查…" : "等待旧工作与监视器退出…"))
            }.font(.caption).accessibilityIdentifier("container-progress")
            if let progress = inspection.progress {
                Text("\(ByteCountFormatter.string(fromByteCount: progress.bytesRead, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
            Button("取消检查") { inspection.cancel() }.font(.subheadline).accessibilityIdentifier("container-cancel")
        } else {
            PrimaryButton(title: "检查音频容器", icon: "waveform.path.ecg", enabled: issue == nil && !archive.isBusy) {
                inspection.start(AudioInspectionIdentity(recording))
            }.accessibilityIdentifier("container-start")
            if inspection.phase == .idle { Text("尚未检查；打开页面不会读取音频。").font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("container-idle") }
        }
    }

    private func resultView(_ result: AudioContainerCheckResult) -> some View {
        Card {
            Text(result.outcome.title).font(.headline).foregroundStyle(resultColor(result.outcome)).accessibilityIdentifier("container-outcome")
            Text("检查时间：\(result.checkedAt.formatted(date: .abbreviated, time: .standard))")
                .font(.caption).foregroundStyle(Palette.muted)
            Text("检查流 SHA-256 已与以上归档记录核对；只对应这一次本机字节。").font(.caption2).foregroundStyle(Palette.muted)
            switch result.outcome {
            case .supported(let report):
                VStack(spacing: 10) {
                    metric("Ogg 页 / CRC 通过页", "\(report.pageCount) / \(report.crcCheckedPages)")
                    metric("音频包 / 含头总包", "\(report.audioPacketCount) / \(report.packetCountIncludingHeaders)")
                    metric("BOS / EOS", "\(report.bosPresent ? "存在" : "缺失") / \(report.eosPresent ? "存在" : "缺失")")
                    metric("声道 / pre-skip", "\(report.opusHeader.channels) / \(report.opusHeader.preSkip)")
                    metric("首 / 末 granule", "\(report.firstAudioGranule) / \(report.finalGranule)")
                    metric("末 PCM 位置", "\(report.finalPCMPosition)")
                    metric("48 kHz 时间位置", String(format: "%.4f 秒", report.finalPCMPositionSeconds))
                    metric("解析页缓冲峰值", "\(result.peakParserPageBytes) 字节")
                }
                Text("时间位置不是测得录音或解码时长；页缓冲峰值不是整个 App 内存。TOC、实际包时长与 granule 增量一致性尚未检查。")
                    .font(.caption).foregroundStyle(Palette.amber)
            case .unsupported(let reason), .invalid(let reason), .limited(let reason):
                Text(reason).font(.subheadline).foregroundStyle(Palette.muted)
            }
            Text("未解码 · 未执行 ASR · 未上传").font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
                .accessibilityIdentifier("container-no-asr")
        }
    }
    private func metric(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(Palette.muted); Spacer(minLength: 12)
            Text(value).foregroundStyle(Palette.ink).monospacedDigit()
        }.font(.caption)
    }
    private func resultColor(_ outcome: AudioContainerOutcome) -> Color {
        if case .supported = outcome { return Palette.green }
        return Palette.amber
    }
}
