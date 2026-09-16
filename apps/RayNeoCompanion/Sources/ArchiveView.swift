import SwiftUI
import UniformTypeIdentifiers
import UIKit
import RayNeoArchive

struct ArchiveView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var showImporter = false
    @State private var showWorkflow = false
    @State private var filter = "全部"
    private var visibleRecordings: [ArchivedRecording] {
        archive.recordings.filter { filter == "全部" || (filter == "待文字" ? $0.transcripts.isEmpty : !$0.transcripts.isEmpty) }
    }
    var body: some View {
        Screen(title: L10n.text("Recording Archive", locale: locale), eyebrow: L10n.text("Local Recording Manager", locale: locale), headerIcon: "square.and.arrow.up", headerAction: { showWorkflow = true }) {
            GlassesRecordingCard()
            NavigationLink(L10n.text("ZIP export copies and recoverable holding area", locale: locale)) { PortableExportCopiesView() }
                .accessibilityIdentifier("export-copies-open")
            HStack(spacing: 0) {
                ForEach(["全部", "待文字", "有笔记"], id: \.self) { value in
                    Button { filter = value } label: {
                        Text(L10n.text(["全部": "All", "待文字": "Needs text", "有笔记": "Has notes"][value] ?? value, locale: locale)).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .foregroundStyle(filter == value ? .white : Palette.ink)
                            .background(filter == value ? Palette.ink : .clear, in: Capsule())
                    }
                }
            }.padding(3).background(Palette.line.opacity(0.35), in: Capsule())
            ArchiveFeedbackView()
            if archive.recordings.isEmpty {
                Card {
                    EmptyState(icon: "waveform.badge.magnifyingglass", title: L10n.text("No Recordings Yet", locale: locale), detail: L10n.text("Import local audio manually\nEnable local reception first for glasses recordings", locale: locale))
                        .padding(.top, 25).padding(.bottom, 10)
                    importButton(L10n.text("Import Local Audio", locale: locale)).padding(.horizontal, 20).padding(.bottom, 20)
                }
            } else {
                SectionLabel(title: L10n.text("Verify Archive", locale: locale), trailing: L10n.format("%@ local copies", locale: locale, String(describing: archive.recordings.count)))
                if visibleRecordings.isEmpty {
                    Card { EmptyState(icon: "line.3.horizontal.decrease.circle", title: L10n.text("No Records in This Category", locale: locale), detail: L10n.text("You must provide text manually. This page does not transcribe automatically.", locale: locale)) }
                }
                ForEach(visibleRecordings) { recording in
                    NavigationLink { ArchiveDetailView(original: recording) } label: {
                        Card {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: "waveform").foregroundStyle(Palette.green).frame(width: 38, height: 44).background(Palette.background, in: RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(recording.title).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                                    Text(L10n.format("Imported %@ · %@", locale: locale, String(describing: recording.importedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))), String(describing: ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file))))
                                        .font(.system(size: 10)).foregroundStyle(Palette.muted)
                                    Badge(text: archive.verificationIssues[recording.id] != nil ? L10n.text("Verification Issue · Review Needed", locale: locale) : (recording.transcripts.isEmpty ? L10n.text("Previously Verified Copy · Awaiting Text", locale: locale) : L10n.format("%@ local Markdown revisions", locale: locale, String(describing: recording.transcripts.count))), active: archive.verificationIssues[recording.id] == nil)
                                    if archive.verificationIssues[recording.id] != nil {
                                        Label(L10n.text("Archive Verification Issue; View Details", locale: locale), systemImage: "exclamationmark.triangle")
                                            .font(.caption2).foregroundStyle(Palette.amber)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Palette.muted)
                            }.contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("archive-row-\(recording.id.uuidString)")
                }
                importButton(L10n.text("Continue Import", locale: locale))
            }
            if archive.allowsTestFixture {
                Button { Task { await archive.importTestFixture() } } label: {
                    Label(L10n.text("Import Synthetic Test Sample", locale: locale), systemImage: "testtube.2").font(.footnote)
                }.disabled(archive.isBusy).accessibilityIdentifier("archive-import-fixture")
                Text(L10n.text("Isolated Debug verification entry. Creates a non-playable audio fixture only when tapped.", locale: locale))
                    .font(.caption2).foregroundStyle(Palette.amber)
                #if DEBUG
                Menu {
                    ForEach(ContainerSyntheticFixture.allCases) { fixture in
                        Button(fixture.title) { Task { await archive.importContainerFixture(fixture) } }
                            .accessibilityIdentifier("container-fixture-\(fixture.rawValue)")
                    }
                } label: {
                    Label(L10n.text("Choose Synthetic Container Sample", locale: locale), systemImage: "testtube.2").font(.footnote)
                }.disabled(archive.isBusy).accessibilityIdentifier("container-fixture-menu")
                #endif
            }
            if !store.recordings.isEmpty {
                NavigationLink { LegacyRecordingsView() } label: {
                    Card { FeatureRow(icon: "folder", title: L10n.text("Legacy Imported Copies", locale: locale), subtitle: L10n.format("%@ files kept in place; no automatic migration", locale: locale, String(describing: store.recordings.count)), status: L10n.text("View", locale: locale)) }
                }.buttonStyle(.plain).accessibilityIdentifier("legacy-recordings")
            }
            Button { showWorkflow = true } label: {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.text("Export Destination", locale: locale)).font(.system(size: 12)).foregroundStyle(Palette.muted)
                        Text("NAS / Obsidian").font(.system(size: 20, weight: .semibold)).foregroundStyle(Palette.ink)
                        Label(L10n.text("Local Markdown sharing available · Uploads not integrated yet", locale: locale), systemImage: "clock").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 5)
                    }
                    Spacer(); Image(systemName: "server.rack").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.green)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
            Button(L10n.text("Refresh and Recover Local Archive", locale: locale)) { Task { await archive.load() } }.font(.caption).disabled(archive.isBusy)
            Text(L10n.text("Manual import · No automatic transcription or uploads", locale: locale)).font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
        }
        .task { await archive.load() }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio, UTType(filenameExtension: "ogg") ?? .audio]) { result in
            switch result {
            case .success(let url): Task { await archive.importFile(url) }
            case .failure(let error): archive.errorMessage = L10n.format("File selection failed: %@", locale: locale, String(describing: error.localizedDescription))
            }
        }
        .sheet(isPresented: $showWorkflow) { ArchiveWorkflowView() }
    }
    private func importButton(_ title: String) -> some View {
        PrimaryButton(title: archive.isBusy ? L10n.text("Processing Archive…", locale: locale) : title, icon: "square.and.arrow.down", enabled: !archive.isBusy) { showImporter = true }
            .accessibilityIdentifier("archive-import-file")
    }
}

struct ArchiveDetailView: View {
    @Environment(\.locale) private var locale
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
                    Label(L10n.text("Locally Verified Archive", locale: locale), systemImage: "checkmark.shield").font(.caption).foregroundStyle(Palette.mint)
                    Text(recording.title).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text(L10n.text("No audio decoding, recognition, or remote uploads performed", locale: locale)).font(.system(size: 11)).foregroundStyle(Palette.mint.opacity(0.8))
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                Picker(L10n.text("Archive Details", locale: locale), selection: $mode) {
                    Text(L10n.text("Archive Evidence", locale: locale)).tag("归档证据"); Text(L10n.text("Text and Revisions", locale: locale)).tag("文字与修订")
                }.pickerStyle(.segmented)
                ArchiveFeedbackView()
                if let integrityIssue {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(L10n.text("This Archive Has a Verification Issue", locale: locale), systemImage: "exclamationmark.triangle").font(.subheadline.weight(.medium))
                        Text(integrityIssue).font(.caption)
                        Text(L10n.text("Refreshing or dismissing the error does not clear this issue. It clears only after a full recheck passes. Historical verification records are retained.", locale: locale))
                            .font(.caption2)
                    }.foregroundStyle(Palette.amber).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("archive-persistent-integrity-issue")
                }
                if mode == "归档证据" { evidenceContent } else { transcriptContent }
            }.padding(24)
        }.background(Palette.background).scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.text("Recording Details", locale: locale)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .onAppear { if title.isEmpty { title = recording.title } }
            .sheet(item: $share) { item in ArchiveShareView(item: item) }
            .onDisappear { bundleTask?.cancel() }
            .confirmationDialog(L10n.text("Exports only this recording and the selected revisions, without other data. Creates an additional local copy.", locale: locale),isPresented:$confirmBundle) {
                if let latest = recording.transcripts.last {
                    Button(L10n.text("Audio + Latest Note", locale: locale)) { exportBundle(.selected([latest.id])) }
                    Button(L10n.text("Audio + All Note Revisions", locale: locale)) { exportBundle(.all) }
                }
                Button(L10n.text("Audio and Verification Manifest Only", locale: locale)) { exportBundle(.selected([])) }.accessibilityIdentifier("archive-bundle-audio-only")
            }
    }
    private var evidenceContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                evidenceRow("1", title: L10n.text("Source Copy Created", locale: locale), detail: L10n.text("Source not moved; does not prove complete wireless transfer from the glasses", locale: locale), complete: recording.evidence.sourceCopied, id: "evidence-copy")
                Divider().overlay(Palette.line)
                evidenceRow("2", title: integrityIssue == nil ? L10n.text("Archive Bytes Previously Verified", locale: locale) : L10n.text("Archive Content Needs Review", locale: locale), detail: L10n.text("Historical SHA-256 and length records do not prove the audio can be decoded", locale: locale), complete: recording.evidence.checksumVerified && integrityIssue == nil, id: "evidence-checksum")
                Divider().overlay(Palette.line)
                evidenceRow("3", title: recording.evidence.transcriptProvided ? L10n.text("User Text Archived", locale: locale) : L10n.text("Awaiting User-Provided Text", locale: locale), detail: L10n.text("This app did not perform speech recognition", locale: locale), complete: recording.evidence.transcriptProvided, id: "evidence-transcript")
                Divider().overlay(Palette.line)
                evidenceRow("4", title: recording.evidence.noteExported ? L10n.text("Local Markdown Created", locale: locale) : L10n.text("Markdown Not Created Yet", locale: locale), detail: L10n.text("Does not prove receipt by NAS or indexing by Obsidian", locale: locale), complete: recording.evidence.noteExported, id: "evidence-note")
            }
            Card {
                Text(L10n.text("Verification History", locale: locale)).font(.headline).foregroundStyle(Palette.ink)
                Text(L10n.format("Verified on import: %@", locale: locale, String(describing: recording.checksumVerifiedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale)))))
                if let date = archive.latestVerifications[recording.id] {
                    Text(L10n.format("Verified this session: %@", locale: locale, String(describing: date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale)))))
                } else { Text(L10n.text("The list shows historical records. Refreshing it does not reread all audio.", locale: locale)) }
                Text(L10n.format("Recorded: %@", locale: locale, String(describing: recording.recordedAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)) ?? L10n.text("Unknown; import time is not recording time", locale: locale))))
                Text("SHA-256\n\(recording.sha256)").font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            }.font(.caption).foregroundStyle(Palette.muted)
            NavigationLink { AudioContainerInspectionView(recordingID: recording.id) } label: {
                Card { FeatureRow(icon: "waveform.path.ecg", title: L10n.text("Audio Container Inspection", locale: locale), subtitle: L10n.text("Manually inspect Ogg / Opus structure without decoding or recognition", locale: locale), status: L10n.text("Local Tools", locale: locale), active: true) }
            }.buttonStyle(.plain).accessibilityIdentifier("archive-open-container-check")
            PrimaryButton(title: L10n.text("Reverify Audio and Notes", locale: locale), icon: "checkmark.shield", enabled: !archive.isBusy) {
                Task { _ = await archive.verify(recording.id) }
            }.accessibilityIdentifier("archive-verify")
            Button(L10n.text("Verify and Share Audio Copy", locale: locale)) {
                Task { if let url = await archive.verify(recording.id) { share = ArchiveShareItem(url: url, isMarkdown: false) } }
            }.disabled(archive.isBusy).font(.subheadline).accessibilityIdentifier("archive-share-audio")
            Button(L10n.text("Export Portable ZIP for Obsidian / NAS", locale: locale)) { confirmBundle = true }
                .disabled(archive.isBusy).font(.subheadline).accessibilityIdentifier("archive-export-bundle")
            Text(L10n.text("Keep the relative notes/ and audio/ directories after extracting. Contains no API keys or other conversations. Exporting does not prove uploading or indexing succeeded.", locale: locale)).font(.caption).foregroundStyle(Palette.muted)
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
            Label(L10n.text("Provide Text Manually · Does Not Start ASR", locale: locale), systemImage: "pencil.line").font(.caption).foregroundStyle(Palette.green)
            Card { ManualRecordingASRView(id: recording.id, title: recording.title) }
            Card {
                Text(L10n.text("Note Title", locale: locale)).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                TextField(L10n.text("Single-line title, up to 256 UTF-8 bytes", locale: locale), text: $title).textInputAutocapitalization(.never)
                    .padding(12).background(Palette.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityIdentifier("archive-note-title").focused($editing)
                Text(L10n.text("Your Text", locale: locale)).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                TextEditor(text: $transcript).frame(minHeight: 170).scrollContentBackground(.hidden)
                    .padding(8).background(Palette.background, in: RoundedRectangle(cornerRadius: 12)).focused($editing).accessibilityIdentifier("archive-transcript")
                Text(L10n.format("%@ bytes / 1 MiB. Unsaved text is lost when you leave this page.", locale: locale, String(describing: transcript.utf8.count)))
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
            PrimaryButton(title: L10n.text("Save as Local Markdown Revision", locale: locale), icon: "doc.badge.plus", enabled: !archive.isBusy && !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                editing = false
                Task { _ = await archive.saveTranscript(recordingID: recording.id, text: transcript, title: title) }
            }.accessibilityIdentifier("archive-save-note")
            Text(L10n.text("Changing the text or title creates a new revision. Identical input reuses the existing revision without overwriting earlier drafts.", locale: locale))
                .font(.caption).foregroundStyle(Palette.muted)
            SectionLabel(title: L10n.text("Local Revisions", locale: locale), trailing: L10n.format("%@ revisions", locale: locale, String(describing: recording.transcripts.count)))
            if recording.transcripts.isEmpty {
                Text(L10n.text("No Markdown Revisions Yet", locale: locale)).font(.subheadline).foregroundStyle(Palette.muted).accessibilityIdentifier("archive-no-revisions")
            }
            ForEach(recording.transcripts.reversed()) { revision in
                Card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.format("Revision %@ · %@", locale: locale, String(describing: revision.number), String(describing: revision.title))).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink).accessibilityIdentifier("archive-revision-\(revision.number)")
                            Text(revision.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))).font(.caption2).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Button {
                            Task { if let url = await archive.prepareNoteShare(recordingID: recording.id, revisionID: revision.id) { share = ArchiveShareItem(url: url, isMarkdown: true) } }
                        } label: { Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36) }
                            .disabled(archive.isBusy).accessibilityLabel(L10n.format("Verify and share Markdown revision %@", locale: locale, String(describing: revision.number))).accessibilityIdentifier("archive-share-note-\(revision.number)")
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
    @Environment(\.locale) private var locale
    @EnvironmentObject private var archive: LocalArchiveController
    var body: some View {
        if archive.isBusy { ProgressView(archive.activity).font(.caption).frame(maxWidth: .infinity).padding(8) }
        if let error = archive.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.text("Local Operation Incomplete", locale: locale), systemImage: "exclamationmark.triangle").font(.subheadline.weight(.medium))
                Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("Dismiss Error Details", locale: locale)) { archive.errorMessage = nil }.font(.caption)
            }.foregroundStyle(Palette.amber).padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("archive-error")
        } else if let message = archive.statusMessage {
            Text(message).font(.caption).foregroundStyle(Palette.green).padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.mint.opacity(0.18), in: RoundedRectangle(cornerRadius: 14)).accessibilityIdentifier("archive-status")
        }
    }
}

struct LegacyRecordingsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var selected: LocalRecording?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("Legacy copies stay in their original directory. There is no automatic migration, deletion, or added SHA-256 success marker. A copy is added to the new verified archive only after you explicitly select it.", locale: locale))
                    .font(.subheadline).foregroundStyle(Palette.muted)
                ArchiveFeedbackView()
                ForEach(store.recordings) { recording in
                    Card {
                        Text(recording.name).font(.headline).foregroundStyle(Palette.ink)
                        Badge(text: L10n.text("Legacy Copy · Not Verified by the New Archive", locale: locale))
                        if let url = store.recordingURL(recording) {
                            Button(L10n.text("Copy to Verified Archive and Keep Legacy Copy", locale: locale)) { selected = recording }.disabled(archive.isBusy)
                            ShareLink(item: url) { Label(L10n.text("Share Legacy Audio Copy", locale: locale), systemImage: "square.and.arrow.up") }.font(.caption)
                        } else { Text(L10n.text("The legacy copy is currently unreadable. Its metadata is retained.", locale: locale)).font(.caption).foregroundStyle(Palette.amber) }
                    }
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle(L10n.text("Legacy Imported Copies", locale: locale)).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
            .preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .confirmationDialog(L10n.text("Copies only this item into the new verified archive. Does not delete or move the legacy copy.", locale: locale), isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                Button(L10n.text("Confirm Copy and Keep Legacy Copy", locale: locale)) {
                    if let recording = selected, let url = store.recordingURL(recording) { Task { await archive.importFile(url, title: recording.name) } }
                    selected = nil
                }
                Button(L10n.text("Cancel", locale: locale), role: .cancel) { selected = nil }
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
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    let item: ArchiveShareItem
    @State private var presentation: ArchiveExportKind?
    @State private var exportError: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                Label(L10n.text("Share Local Files Only", locale: locale), systemImage: "square.and.arrow.up").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(item.isBundle
                     ? L10n.text("Each ZIP entry has been extracted and checked for length, CRC, and SHA-256. Contains the selected audio, notes, and verification manifest. After extracting, place the whole folder in Obsidian and keep notes/ and audio/ at the same level. Nothing has been uploaded to NAS, and indexing has not been verified.", locale: locale)
                     : item.isMarkdown
                     ? L10n.text("The Markdown digest was checked before sharing. Sharing a note alone does not include audio attachments. For Obsidian, also save the corresponding audio and preserve the relative notes/ and audio/ directories.", locale: locale)
                     : L10n.text("This is a local copy with verified bytes. Decodability has not been checked, and there is no background upload.", locale: locale))
                    .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                Text(L10n.text("Opening the system share sheet does not prove remote receipt. Confirm the saved result in the destination app.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.amber)
                Button { open(.share) } label: {
                    Label(L10n.text("Open System Share Sheet", locale: locale), systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(17).background(Palette.ink, in: RoundedRectangle(cornerRadius: 14))
                }.accessibilityIdentifier("archive-system-share")
                Button { open(.files) } label: {
                    Label(L10n.text("Save to Files", locale: locale), systemImage: "folder").frame(maxWidth: .infinity).padding(15)
                }.accessibilityIdentifier("archive-save-files")
                Spacer()
            }.padding(24).background(Palette.background).navigationTitle(L10n.text("Local File Sharing", locale: locale)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { dismiss() } } }
        }
        .sheet(item: $presentation) { kind in
            NativeArchiveExportSheet(url: item.url, kind: kind) { error in
                presentation = nil
                if let error { exportError = error }
            }
        }
        .alert(L10n.text("Unable to Open File Sharing", locale: locale), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(L10n.text("Got It", locale: locale), role: .cancel) {}
        } message: { Text(exportError ?? "") }
    }
    private func open(_ kind: ArchiveExportKind) {
        guard item.url.isFileURL, FileManager.default.isReadableFile(atPath: item.url.path) else {
            exportError = L10n.text("The file is currently unreadable. Return to Recording Details, reverify, and try again. The original recording is unchanged.", locale: locale); return
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
    @Environment(\.locale) private var locale
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
                coordinator?.completion(error == nil ? nil : L10n.text("System sharing did not complete. Try again or use Save to Files. The original is retained.", locale: locale))
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
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(L10n.text("From Sound to Your Own Knowledge.", locale: locale)).font(.title2.bold()).foregroundStyle(Palette.ink)
                    Text(L10n.text("You choose the source. It is copied into a stable local app directory before its bytes are independently verified. You provide the text manually; each edit creates a new note without overwriting earlier drafts.", locale: locale))
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(5)
                    Card {
                        FeatureRow(icon: "1.circle", title: L10n.text("Glasses to Phone", locale: locale), subtitle: L10n.text("Recording sync, integrity checks, and resumable transfers need separate integration", locale: locale))
                        FeatureRow(icon: "2.circle", title: L10n.text("Locally Verified Archive", locale: locale), subtitle: L10n.text("Explicit file selection, original sources retained, SHA-256 deduplication", locale: locale), status: L10n.text("Available Locally", locale: locale), active: true)
                        FeatureRow(icon: "3.circle", title: L10n.text("Manual Text and Markdown", locale: locale), subtitle: L10n.text("Local revisions and system sharing, without automatic recognition", locale: locale), status: L10n.text("Available Locally", locale: locale), active: true)
                        FeatureRow(icon: "4.circle", title: L10n.text("NAS and Obsidian", locale: locale), subtitle: L10n.text("Remote transfer, attachment mapping, and actual indexing are not yet verified", locale: locale))
                    }
                    Text(L10n.text("Verification covers copied bytes only. It does not prove audio decodability, complete original wireless transfer, or text accuracy. No NAS address is preset, and no official credentials are read.", locale: locale))
                        .font(.footnote).foregroundStyle(Palette.green)
                }.padding(24)
            }.background(Palette.background).navigationTitle(L10n.text("Archive Workflow", locale: locale)).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done", locale: locale)) { dismiss() } } }
        }
    }
}
