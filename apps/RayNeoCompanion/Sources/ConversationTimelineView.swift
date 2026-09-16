import SwiftUI

struct ConversationTimelineView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var timeline: ConversationTimeline
    @State private var exportURL: URL?
    @State private var error: String?
    @State private var exporting = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text(L10n.text("Records only real AI conversations in Turbo IO, including recognized text, responses, and timestamps. Does not read other apps' chats or treat workflow demos as conversation history.", locale: locale))
                    .font(.caption).foregroundStyle(Palette.muted)
                if let error = timeline.storageError { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                PrimaryButton(title: exporting ? L10n.text("Preparing Export…", locale: locale) : L10n.text("Export Full Timeline", locale: locale), icon: "square.and.arrow.up", enabled: !timeline.turns.isEmpty && !exporting) {
                    exporting = true
                    Task { defer { exporting = false }; do { exportURL = try await timeline.export() } catch { self.error = L10n.text("Export failed. History was not deleted.", locale: locale) } }
                }.accessibilityIdentifier("timeline-export")
                if let exportURL {
                    ShareLink(item: exportURL) { Label(L10n.text("Share / Save to Files (Markdown)", locale: locale), systemImage: "doc") }
                    Text(L10n.text("This is a snapshot taken when you tap Export. Export again to include later conversations. Use system sharing to save to Files, a NAS file provider, or Obsidian.", locale: locale))
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
                if timeline.turns.isEmpty {
                    Card { EmptyState(icon: "clock", title: L10n.text("No Conversations Yet", locale: locale), detail: L10n.text("Real conversations are automatically saved locally in chronological order.\nClosing the live page does not delete history.", locale: locale)) }
                }
                ForEach(timeline.turns.reversed()) { turn in
                    Card {
                        HStack { Text(turn.startedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale))).font(.caption); Spacer(); Badge(text: turn.outcome) }
                        Label(L10n.text("Me", locale: locale), systemImage: "person").font(.caption.bold()).foregroundStyle(Palette.green)
                        Text(turn.question.isEmpty ? L10n.text("No Valid Recognized Text Received", locale: locale) : turn.question).font(.subheadline).textSelection(.enabled)
                        Divider().overlay(Palette.line)
                        Label("AI", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Palette.green)
                        Text(turn.answer.isEmpty ? L10n.text("No Response Generated", locale: locale) : turn.answer).font(.subheadline).textSelection(.enabled)
                    }.privacySensitive()
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle(L10n.text("Conversation Timeline", locale: locale)).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .alert(L10n.text("Export", locale: locale), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button(L10n.text("Got It", locale: locale)) {} } message: { Text(error ?? "") }
    }
}
