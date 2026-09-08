import SwiftUI
import UniformTypeIdentifiers
import UIKit
import RayNeoArchive

struct ArchiveView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var showImporter = false
    @State private var showWorkflow = false
    @State private var filter = "全部"
    private var visibleRecordings: [ArchivedRecording] {
        archive.recordings.filter { filter == "全部" || (filter == "待文字" ? $0.transcripts.isEmpty : !$0.transcripts.isEmpty) }
    }
    var body: some View {
        Screen(title: "录音归档", eyebrow: "本地录音管理", headerIcon: "square.and.arrow.up", headerAction: { showWorkflow = true }) {
            GlassesRecordingCard()
            NavigationLink("ZIP 导出副本与可恢复暂存箱") { PortableExportCopiesView() }
                .accessibilityIdentifier("export-copies-open")
            HStack(spacing: 0) {
                ForEach(["全部", "待文字", "有笔记"], id: \.self) { value in
                    Button { filter = value } label: {
                        Text(value).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(filter == value ? .white : Palette.ink)
                            .background(filter == value ? Palette.ink : .clear, in: Capsule())
                    }
                }
            }.padding(3).background(Palette.line.opacity(0.35), in: Capsule())
            ArchiveFeedbackView()
            if archive.recordings.isEmpty {
                Card {
                    EmptyState(icon: "waveform.badge.magnifyingglass", title: "还没有录音", detail: "可手动导入本地音频\n眼镜录音需先开启本机接收")
                        .padding(.top, 25).padding(.bottom, 10)
                    importButton("导入本地音频").padding(.horizontal, 20).padding(.bottom, 20)
                }
            } else {
                SectionLabel(title: "校验归档", trailing: "\(archive.recordings.count) 个本机副本")
                if visibleRecordings.isEmpty {
                    Card { EmptyState(icon: "line.3.horizontal.decrease.circle", title: "此分类没有记录", detail: "文字必须由你手工提供；这里不会自动转写。") }
                }
                ForEach(visibleRecordings) { recording in
                    NavigationLink { ArchiveDetailView(original: recording) } label: {
                        Card {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: "waveform").foregroundStyle(Palette.green).frame(width: 38, height: 44).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(recording.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                                    Text("\(recording.importedAt.formatted(date: .abbreviated, time: .shortened)) 导入 · \(ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file))")
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    Badge(text: archive.verificationIssues[recording.id] != nil ? "校验异常 · 需复核" : (recording.transcripts.isEmpty ? "曾校验副本 · 待提供文字" : "\(recording.transcripts.count) 版本地 Markdown"), active: archive.verificationIssues[recording.id] == nil)
                                    if archive.verificationIssues[recording.id] != nil {
                                        Label("归档校验异常，查看详情", systemImage: "exclamationmark.triangle")
                                            .font(.caption2).foregroundStyle(Palette.amber)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                            }.contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("archive-row-\(recording.id.uuidString)")
                }
                importButton("继续导入")
            }
            if archive.allowsTestFixture {
                Button { Task { await archive.importTestFixture() } } label: {
                    Label("导入合成测试样本", systemImage: "testtube.2").font(.footnote)
                }.disabled(archive.isBusy).accessibilityIdentifier("archive-import-fixture")
                Text("隔离的 Debug 验收入口；非有效音频，点击后才创建。")
                    .font(.caption2).foregroundStyle(Palette.amber)
                #if DEBUG
                Menu {
                    ForEach(ContainerSyntheticFixture.allCases) { fixture in
                        Button(fixture.title) { Task { await archive.importContainerFixture(fixture) } }
                            .accessibilityIdentifier("container-fixture-\(fixture.rawValue)")
                    }
                } label: {
                    Label("选择合成容器样本", systemImage: "testtube.2").font(.footnote)
                }.disabled(archive.isBusy).accessibilityIdentifier("container-fixture-menu")
                #endif
            }
            if !store.recordings.isEmpty {
                NavigationLink { LegacyRecordingsView() } label: {
                    Card { FeatureRow(icon: "folder", title: "旧版导入副本", subtitle: "\(store.recordings.count) 个文件保留原位，不自动迁移", status: "查看") }
                }.buttonStyle(.plain).accessibilityIdentifier("legacy-recordings")
            }
            Button { showWorkflow = true } label: {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("导出目的地").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Text("NAS / Obsidian").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.ink)
                        Label("本地 Markdown 可分享 · 上传待接入", systemImage: "clock").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 5)
                    }
                    Spacer(); Image(systemName: "server.rack").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.green)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
            Button("刷新与恢复本地归档") { Task { await archive.load() } }.font(.caption).disabled(archive.isBusy)
            Text("手动导入 · 不自动转写 · 不自动上传").font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
        }
        .task { await archive.load() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, UTType(filenameExtension: "ogg") ?? .audio]) { result in
            switch result {
            case .success(let url): Task { await archive.importFile(url) }
            case .failure(let error): archive.errorMessage = "文件选择失败：\(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $showWorkflow) { ArchiveWorkflowView() }
    }
    private func importButton(_ title: String) -> some View {
        PrimaryButton(title: archive.isBusy ? "归档处理中…" : title, icon: "square.and.arrow.down", enabled: !archive.isBusy) { showImporter = true }
            .accessibilityIdentifier("archive-import-file")
    }
}

struct ArchiveDetailView: View {
    @EnvironmentObject private var archive: LocalArchiveController
    let original: ArchivedRecording
    @State private var mode = "归档证据"
    @State private var title = ""
    @State private var transcript = ""
    @State private var share: ArchiveShareItem?
    @State private var confirmBundle = false
    @State private var bundleTask: Task<Void,Never>?
    @FocusState private var editing: Bool
    private var recording: ArchivedRecording { archive.recordings.first { $0.id == original.id } ?? original }
    private var integrityIssue: String? { archive.verificationIssues[original.id] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("本机校验归档", systemImage: "checkmark.shield").font(.caption).foregroundStyle(Palette.mint)
                    Text(recording.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text("没有执行音频解码、识别或远端上传").font(.system(size: 11)).foregroundStyle(Palette.mint.opacity(0.8))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                Picker("归档详情", selection: $mode) {
                    Text("归档证据").tag("归档证据"); Text("文字与修订").tag("文字与修订")
                }.pickerStyle(.segmented)
                ArchiveFeedbackView()
                if let integrityIssue {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("此条归档存在校验异常", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.medium))
                        Text(integrityIssue).font(.caption)
                        Text("刷新或收起错误不会清除这条异常；完整复核通过后才恢复。历史校验记录仍保留。")
                            .font(.caption2)
                    }.foregroundStyle(Palette.amber).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("archive-persistent-integrity-issue")
                }
                if mode == "归档证据" { evidenceContent } else { transcriptContent }
            }.padding(24)
        }.background(Palette.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle("录音详情").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { if title.isEmpty { title = recording.title } }
            .sheet(item: $share) { item in ArchiveShareView(item: item) }
            .onDisappear { bundleTask?.cancel() }
            .confirmationDialog("导出这一条录音及选定修订，不含其他资料；会生成额外本地副本。",isPresented:$confirmBundle) {
                if let latest = recording.transcripts.last {
                    Button("音频 + 最新笔记") { exportBundle(.selected([latest.id])) }
                    Button("音频 + 全部笔记修订") { exportBundle(.all) }
                }
                Button("仅音频与校验清单") { exportBundle(.selected([])) }.accessibilityIdentifier("archive-bundle-audio-only")
            }
    }
    private var evidenceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                evidenceRow("1", title: "来源副本已复制", detail: "来源未移动；不代表眼镜无线传输完整", complete: recording.evidence.sourceCopied, id: "evidence-copy")
                Divider().overlay(Palette.line)
                evidenceRow("2", title: integrityIssue == nil ? "归档字节曾通过校验" : "归档内容需要检查", detail: "历史 SHA-256 与长度记录，不代表音频可解码", complete: recording.evidence.checksumVerified && integrityIssue == nil, id: "evidence-checksum")
                Divider().overlay(Palette.line)
                evidenceRow("3", title: recording.evidence.transcriptProvided ? "用户文字已入档" : "待用户提供文字", detail: "本 App 没有执行语音识别", complete: recording.evidence.transcriptProvided, id: "evidence-transcript")
                Divider().overlay(Palette.line)
                evidenceRow("4", title: recording.evidence.noteExported ? "本地 Markdown 已生成" : "待生成 Markdown", detail: "不代表 NAS 已接收或 Obsidian 已索引", complete: recording.evidence.noteExported, id: "evidence-note")
            }
            Card {
                Text("校验记录").font(.headline).foregroundStyle(Palette.ink)
                Text("入档校验：\(recording.checksumVerifiedAt.formatted(date: .abbreviated, time: .standard))")
                if let date = archive.latestVerifications[recording.id] {
                    Text("本次运行复核：\(date.formatted(date: .abbreviated, time: .standard))")
                } else { Text("列表显示历史记录；刷新列表不会重读全部音频。") }
                Text("录音时间：\(recording.recordedAt?.formatted(date: .abbreviated, time: .shortened) ?? "未知，不以导入时间替代")")
                Text("SHA-256\n\(recording.sha256)").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            }.font(.caption).foregroundStyle(Palette.muted)
            NavigationLink { AudioContainerInspectionView(recordingID: recording.id) } label: {
                Card { FeatureRow(icon: "waveform.path.ecg", title: "音频容器检查", subtitle: "手动检查 Ogg / Opus 结构，不解码或识别", status: "本地工具", active: true) }
            }.buttonStyle(.plain).accessibilityIdentifier("archive-open-container-check")
            PrimaryButton(title: "重新校验音频与笔记", icon: "checkmark.shield", enabled: !archive.isBusy) {
                Task { _ = await archive.verify(recording.id) }
            }.accessibilityIdentifier("archive-verify")
            Button("校验并分享音频副本") {
                Task { if let url = await archive.verify(recording.id) { share = ArchiveShareItem(url: url, isMarkdown: false) } }
            }.disabled(archive.isBusy).font(.subheadline).accessibilityIdentifier("archive-share-audio")
            Button("导出 Obsidian / NAS 便携 ZIP") { confirmBundle = true }
                .disabled(archive.isBusy).font(.subheadline).accessibilityIdentifier("archive-export-bundle")
            Text("解压后保留 notes/ 与 audio/ 的相对目录；不包含 API Key 或其他会话。导出不是上传或索引成功。").font(.caption).foregroundStyle(Palette.muted)
        }
    }
    private func exportBundle(_ selection: SnapshotRevisionSelection) {
        bundleTask = Task {
            if let url = await archive.preparePortableShare(recordingID:recording.id,revisions:selection), !Task.isCancelled {
                share = ArchiveShareItem(url:url,isMarkdown:false,isBundle:true)
            }
        }
    }
    private var transcriptContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("手工提供文字 · 不启动 ASR", systemImage: "pencil.line").font(.caption).foregroundStyle(Palette.green)
            Card { ManualRecordingASRView(id: recording.id, title: recording.title) }
            Card {
                Text("笔记标题").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                TextField("单行标题，最多 256 UTF-8 字节", text: $title).textInputAutocapitalization(.never)
                    .padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("archive-note-title").focused($editing)
                Text("你提供的文字").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                TextEditor(text: $transcript).frame(minHeight: 170).scrollContentBackground(.hidden)
                    .padding(8).background(Palette.background, in: RoundedRectangle(cornerRadius: 12)).focused($editing).accessibilityIdentifier("archive-transcript")
                Text("当前 \(transcript.utf8.count) 字节 / 1 MiB。未保存文字离开此页会丢失。")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
            PrimaryButton(title: "保存为本地 Markdown 修订", icon: "doc.badge.plus", enabled: !archive.isBusy && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                editing = false
                Task { _ = await archive.saveTranscript(recordingID: recording.id, text: transcript, title: title) }
            }.accessibilityIdentifier("archive-save-note")
            Text("改文字或标题会新建修订；相同输入复用旧版，不覆盖旧稿。")
                .font(.caption).foregroundStyle(Palette.muted)
            SectionLabel(title: "本地修订", trailing: "\(recording.transcripts.count) 版")
            if recording.transcripts.isEmpty {
                Text("还没有 Markdown 修订").font(.subheadline).foregroundStyle(Palette.muted).accessibilityIdentifier("archive-no-revisions")
            }
            ForEach(recording.transcripts.reversed()) { revision in
                Card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("第 \(revision.number) 版 · \(revision.title)").font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink).accessibilityIdentifier("archive-revision-\(revision.number)")
                            Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button {
                            Task { if let url = await archive.prepareNoteShare(recordingID: recording.id, revisionID: revision.id) { share = ArchiveShareItem(url: url, isMarkdown: true) } }
                        } label: { Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36) }
                            .disabled(archive.isBusy).accessibilityLabel("核对并分享第 \(revision.number) 版 Markdown").accessibilityIdentifier("archive-share-note-\(revision.number)")
                    }
                }
            }
        }
    }
    private func evidenceRow(_ number: String, title: String, detail: String, complete: Bool, id: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: complete ? "checkmark.circle.fill" : "\(number).circle").foregroundStyle(complete ? Palette.green : Palette.muted)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink).accessibilityIdentifier(id)
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ArchiveFeedbackView: View {
    @EnvironmentObject private var archive: LocalArchiveController
    var body: some View {
        if archive.isBusy { ProgressView(archive.activity).font(.caption).frame(maxWidth: .infinity).padding(8) }
        if let error = archive.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label("本地操作未完成", systemImage: "exclamationmark.triangle").font(.subheadline.weight(.medium))
                Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button("收起错误说明") { archive.errorMessage = nil }.font(.caption)
            }.foregroundStyle(Palette.amber).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("archive-error")
        } else if let message = archive.statusMessage {
            Text(message).font(.caption).foregroundStyle(Palette.green).padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("archive-status")
        }
    }
}

struct LegacyRecordingsView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var selected: LocalRecording?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("旧副本保留原目录。没有自动迁移、删除或追加 SHA-256 成功标记；明确选择一条后，才复制到新的校验归档。")
                    .font(.subheadline).foregroundStyle(Palette.muted)
                ArchiveFeedbackView()
                ForEach(store.recordings) { recording in
                    Card {
                        Text(recording.name).font(.headline).foregroundStyle(Palette.ink)
                        Badge(text: "旧版副本 · 未经新归档校验")
                        if let url = store.recordingURL(recording) {
                            Button("复制到校验归档（保留旧副本）") { selected = recording }.disabled(archive.isBusy)
                            ShareLink(item: url) { Label("分享旧音频副本", systemImage: "square.and.arrow.up") }.font(.caption)
                        } else { Text("旧副本当前不可读取，元数据仍保留。").font(.caption).foregroundStyle(Palette.amber) }
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("旧版导入副本").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .confirmationDialog("仅复制这一条到新校验归档；不删除或移动旧副本。", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                Button("确认复制，保留旧副本") {
                    if let recording = selected, let url = store.recordingURL(recording) { Task { await archive.importFile(url, title: recording.name) } }
                    selected = nil
                }
                Button("取消", role: .cancel) { selected = nil }
            }
    }
}

struct ArchiveShareItem: Identifiable {
    let id = UUID()
    let url: URL
    let isMarkdown: Bool
    var isBundle = false
}

struct ArchiveShareView: View {
    @Environment(\.dismiss) private var dismiss
    let item: ArchiveShareItem
    @State private var presentation: ArchiveExportKind?
    @State private var exportError: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Label("仅分享本地文件", systemImage: "square.and.arrow.up").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(item.isBundle
                     ? "ZIP 已逐项解包核对长度、CRC 与 SHA-256。包含所选音频、笔记和校验清单；解压后将整个文件夹放入 Obsidian，保留 notes/ 与 audio/ 同级。没有上传到 NAS 或验证索引。"
                     : item.isMarkdown
                     ? "Markdown 已在分享前核对摘要。单独分享笔记不包含音频附件；若放入 Obsidian，请同时保存对应音频，并保持 notes/ 与 audio/ 的相对目录。"
                     : "这个文件是经过字节复核的本机副本；没有验证可解码性，也没有后台上传。")
                    .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                Text("打开系统分享面板不代表远端收到；请在目标应用确认保存结果。")
                    .font(.caption).foregroundStyle(Palette.amber)
                Button { open(.share) } label: {
                    Label("打开系统分享", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(17).background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("archive-system-share")
                Button { open(.files) } label: {
                    Label("存储到文件", systemImage: "folder").frame(maxWidth: .infinity).padding(15)
                }.accessibilityIdentifier("archive-save-files")
                Spacer()
            }.padding(24).background(Palette.background).navigationTitle("本地文件分享").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .sheet(item: $presentation) { kind in
            NativeArchiveExportSheet(url: item.url, kind: kind) { error in
                presentation = nil
                if let error { exportError = error }
            }
        }
        .alert("无法打开文件分享", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("知道了", role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }
    private func open(_ kind: ArchiveExportKind) {
        guard item.url.isFileURL, FileManager.default.isReadableFile(atPath: item.url.path) else {
            exportError = "文件当前不可读取，请返回录音详情重新校验后再试。原录音未修改。"; return
        }
        presentation = kind
    }
}

enum ArchiveExportKind: String, Identifiable {
    case share, files
    var id: String { rawValue }
}

/// Present from SwiftUI's actual sheet host, not a guessed root controller.
/// UIKit directly receives the verified local URL; no Transferable metadata hop.
struct NativeArchiveExportSheet: UIViewControllerRepresentable {
    let url: URL
    let kind: ArchiveExportKind
    let completion: (String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    func makeUIViewController(context: Context) -> UIViewController {
        let coordinator = context.coordinator
        if kind == .files {
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            picker.delegate = coordinator
            return picker
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { [weak coordinator] _, _, _, error in
            DispatchQueue.main.async {
                coordinator?.completion(error == nil ? nil : "系统分享未完成，请重试或使用存储到文件。原件保留。")
            }
        }
        return activity
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: (String?) -> Void
        init(completion: @escaping (String?) -> Void) { self.completion = completion }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(nil) // Destination provider owns the copy; never delete source.
        }
    }
}

struct ArchiveWorkflowView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("从声音，到自己的知识。").font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text("用户选择来源，先复制到稳定的本机专用目录，再独立核对字节。文字由你手工提供；每次修改生成新笔记，不覆盖旧稿。")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                    Card {
                        FeatureRow(icon: "1.circle", title: "眼镜到手机", subtitle: "录音同步、完整性和断点续传需另行接入")
                        FeatureRow(icon: "2.circle", title: "本机校验归档", subtitle: "明确选择文件、源保留、SHA-256 去重", status: "本地可用", active: true)
                        FeatureRow(icon: "3.circle", title: "手工文字与 Markdown", subtitle: "本地修订与系统分享，不自动识别", status: "本地可用", active: true)
                        FeatureRow(icon: "4.circle", title: "NAS 与 Obsidian", subtitle: "远端传输、附件映射和实际索引尚未验收")
                    }
                    Text("校验只针对复制后的字节，不证明音频解码、原始无线覆盖或文字准确。没有预设 NAS 地址，没有读取官方凭证。")
                        .font(.footnote).foregroundStyle(Palette.green)
                }.padding(24)
            }.background(Palette.background).navigationTitle("归档链路").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}
