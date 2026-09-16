import SwiftUI
import RayNeoArchive
import RayNeoAudioContainer

struct AudioContainerInspectionView: View {
    @Environment(\.locale) private var locale
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
                    Label(L10n.text("Local Structure Inspection", locale: locale), systemImage: "waveform.path.ecg").font(.caption).foregroundStyle(Palette.mint)
                    Text(L10n.text("A valid container does not prove usable sound.", locale: locale)).font(.title3.weight(.semibold)).foregroundStyle(.white)
                    Text(L10n.text("Checks only a subset of Ogg / Opus declarations. Does not play, decode, or run speech recognition.", locale: locale))
                        .font(.caption).foregroundStyle(Palette.mint.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.ink, in: RoundedRectangle(cornerRadius: 20))
                if let recording {
                    Card {
                        Text(recording.title).font(.subheadline.weight(.medium)).foregroundStyle(Palette.ink)
                        Text(L10n.format("File %@ · Inspection limit 64 MiB", locale: locale, String(describing: ByteCountFormatter.string(fromByteCount: recording.byteCount, countStyle: .file))))
                            .font(.caption).foregroundStyle(Palette.muted)
                        Text(L10n.format("Archive record SHA-256\n%@", locale: locale, String(describing: recording.sha256))).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    }
                    if let issue {
                        Label(L10n.format("Archive verification found an issue. Return to Details and complete a full recheck first.\n%@", locale: locale, String(describing: issue)), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Palette.amber)
                    }
                    operationControls(recording)
                } else { Text(L10n.text("This recording is not in the current archive. Go back and refresh.", locale: locale)).foregroundStyle(Palette.amber) }

                if let message = inspection.message, inspection.identity?.recordingID == recordingID {
                    Text(message).font(.caption).foregroundStyle(Palette.amber).padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.99, green: 0.95, blue: 0.85), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("container-check-message")
                }
                if let result = ownResult { resultView(result) }
                Card {
                    Text(L10n.text("Inspection Scope and Resources", locale: locale)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(L10n.text("Single stream, non-chained, Opus v1, mapping 0, one or two channels. CRC, page sequence, packet boundaries, and granule positions provide structural evidence only. They do not prove the original wireless transfer had no packet loss.", locale: locale))
                    Text(L10n.text("Reads in 64 KiB chunks. Input limit: 64 MiB; packet limit: 1 MiB. Stops at the budget without automatically increasing it. Only one inspection can run, with no waiting queue.", locale: locale))
                    Text(L10n.text("Leaving this page cancels inspection and clears results. Reopening does not automatically inspect. File changes or archive issues invalidate old results. After cancellation, wait for resources to be released before restarting.", locale: locale))
                }.font(.caption).foregroundStyle(Palette.muted)
            }.padding(24)
        }.background(Palette.background).navigationTitle(L10n.text("Audio Container Inspection", locale: locale)).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onDisappear { inspection.leave(recordingID: recordingID) }
    }

    @ViewBuilder private func operationControls(_ recording: ArchivedRecording) -> some View {
        if ownResult != nil {
            PrimaryButton(title: L10n.text("Clear Results to Inspect Again", locale: locale), icon: "arrow.counterclockwise") { inspection.clear() }
                .accessibilityIdentifier("container-clear")
            Text(L10n.text("Clears only the displayed results. Audio and notes are not deleted.", locale: locale)).font(.caption2).foregroundStyle(Palette.muted)
        } else if !inspection.canStart {
            ProgressView(value: inspection.progress?.fraction ?? 0) {
                Text(inspection.phase == .preparing ? L10n.text("Verifying the local archive copy…", locale: locale) : (inspection.phase == .reading ? L10n.text("Inspecting in chunks…", locale: locale) : L10n.text("Waiting for previous work and monitor to stop…", locale: locale)))
            }.font(.caption).accessibilityIdentifier("container-progress")
            if let progress = inspection.progress {
                Text("\(ByteCountFormatter.string(fromByteCount: progress.bytesRead, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))")
                    .font(.caption2).foregroundStyle(Palette.muted)
            }
            Button(L10n.text("Cancel Inspection", locale: locale)) { inspection.cancel() }.font(.subheadline).accessibilityIdentifier("container-cancel")
        } else {
            PrimaryButton(title: L10n.text("Inspect Audio Container", locale: locale), icon: "waveform.path.ecg", enabled: issue == nil && !archive.isBusy) {
                inspection.start(AudioInspectionIdentity(recording))
            }.accessibilityIdentifier("container-start")
            if inspection.phase == .idle { Text(L10n.text("Not inspected yet. Opening this page does not read audio.", locale: locale)).font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("container-idle") }
        }
    }

    private func resultView(_ result: AudioContainerCheckResult) -> some View {
        Card {
            Text(L10n.audioContainerOutcome(result.outcome, locale: locale)).font(.headline).foregroundStyle(resultColor(result.outcome)).accessibilityIdentifier("container-outcome")
            Text(L10n.format("Inspection time: %@", locale: locale, String(describing: result.checkedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale)))))
                .font(.caption).foregroundStyle(Palette.muted)
            Text(L10n.text("The inspected stream's SHA-256 matches the archive record above. It applies only to these local bytes from this run.", locale: locale)).font(.caption2).foregroundStyle(Palette.muted)
            switch result.outcome {
            case .supported(let report):
                VStack(spacing: 10) {
                    metric(L10n.text("Ogg Pages / CRC-Verified Pages", locale: locale), "\(report.pageCount) / \(report.crcCheckedPages)")
                    metric(L10n.text("Audio Packets / Total Packets Including Headers", locale: locale), "\(report.audioPacketCount) / \(report.packetCountIncludingHeaders)")
                    metric("BOS / EOS", (report.bosPresent ? L10n.text("Present", locale: locale) : L10n.text("Missing", locale: locale)) + " / " + (report.eosPresent ? L10n.text("Present", locale: locale) : L10n.text("Missing", locale: locale)))
                    metric(L10n.text("Channels / Pre-Skip", locale: locale), "\(report.opusHeader.channels) / \(report.opusHeader.preSkip)")
                    metric(L10n.text("First / Last Granule", locale: locale), "\(report.firstAudioGranule) / \(report.finalGranule)")
                    metric(L10n.text("Final PCM Position", locale: locale), "\(report.finalPCMPosition)")
                    metric(L10n.text("Time Position at 48 kHz", locale: locale), L10n.format("%.4f seconds", locale: locale, report.finalPCMPositionSeconds))
                    metric(L10n.text("Peak Parsed Page Buffer", locale: locale), L10n.format("%@ bytes", locale: locale, result.peakParserPageBytes.formatted(.number.locale(locale))))
                }
                Text(L10n.text("The time position is not a measured recording or decoding duration. Peak page buffer is not total app memory. TOC, actual packet duration, and consistency with granule increments have not been checked.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.amber)
            case .unsupported(let reason), .invalid(let reason), .limited(let reason):
                Text(reason).font(.subheadline).foregroundStyle(Palette.muted)
            }
            Text(L10n.text("Not Decoded · No ASR · Not Uploaded", locale: locale)).font(.caption.weight(.medium)).foregroundStyle(Palette.muted)
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
