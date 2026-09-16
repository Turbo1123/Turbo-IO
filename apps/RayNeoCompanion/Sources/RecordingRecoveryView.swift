import SwiftUI

struct RecordingRecoveryView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @State private var selected: String?
    @State private var raw: URL?
    var body: some View {
        List {
            Section(L10n.text("Only Handles Turbo IO's Local Files", locale: locale)) {
                Text(L10n.text("Finds received files after an app restart. Does not connect to the glasses, start recording, request offline retransmission, or delete originals. Recovery can be attempted only for older packaged tasks or tasks with a retained end record and no gaps in received coverage.", locale: locale))
                    .font(.caption)
                Button(L10n.text("Scan Local Reception Directory", locale: locale)) { Task { await features.loadRecoveryEntries() } }
                    .disabled(features.recoveryBusy || features.recordingID != nil).accessibilityIdentifier("recovery-scan")
                Text(features.recoveryStatus).font(.caption).accessibilityIdentifier("recovery-status")
                if features.recoveryBusy { ProgressView() }
            }
            if features.recoveryEntries.isEmpty {
                Text(L10n.text("No Local Reception Records to List", locale: locale)).foregroundStyle(.secondary).accessibilityIdentifier("recovery-empty")
            }
            ForEach(features.recoveryEntries) { entry in
                Section(L10n.text("Received locally: ", locale: locale) + entry.createdAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))) {
                    Text(entry.status).font(.subheadline)
                    Text(L10n.format("Recorded %@ · Local ID %@", locale: locale, String(describing: ByteCountFormatter.string(fromByteCount:Int64(entry.receivedBytes),countStyle:.file)), String(describing: entry.id.prefix(8)))).font(.caption)
                    Button(L10n.text("Reverify, Decode, and Archive", locale: locale)) { selected = entry.id }
                        .disabled(!entry.mayRecover || features.recoveryBusy || features.recordingID != nil)
                    Button(L10n.text("Prepare to Share Raw rawopus (Completeness Unverified)", locale: locale)) {
                        Task { raw = await features.recoveryRawFile(entry.id) }
                    }.disabled(features.recoveryBusy || features.recordingID != nil)
                }
            }
            if let raw {
                Section(L10n.text("Raw Data; Does Not Prove Playable Audio", locale: locale)) {
                    Text(L10n.text("This rawopus file may be incomplete and is for backup or research only. No audio repair or ASR is performed. Opening the share sheet does not prove remote receipt.", locale: locale)).font(.caption)
                    ShareLink(item:raw) { Label(L10n.text("Share Selected Raw File", locale: locale),systemImage:"square.and.arrow.up") }
                }
            }
        }.navigationTitle(L10n.text("Local Reception Recovery", locale: locale))
        .task { await features.loadRecoveryEntries() }
        .onDisappear { raw = nil }
        .confirmationDialog(L10n.text("Recover only this local file by reverifying, decoding, and archiving it. Nothing is uploaded or deleted.", locale: locale),isPresented:Binding(get:{ selected != nil },set:{ if !$0 { selected = nil } })) {
            Button(L10n.text("Attempt Local Recovery", locale: locale)) {
                if let id = selected { Task { await features.recoverRecording(id) } }
                selected = nil
            }
        }
    }
}
