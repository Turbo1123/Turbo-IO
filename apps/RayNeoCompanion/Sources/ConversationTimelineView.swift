import SwiftUI

struct ConversationTimelineView: View {
    @EnvironmentObject private var timeline: ConversationTimeline
    @State private var exportURL: URL?
    @State private var error: String?
    @State private var exporting = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                Text("只记录Turbo IO里的真实 AI 对话，包含识别文字、回答和时间。不读取其他 App 的聊天；不把流程演示当成聊天记录。")
                    .font(.caption).foregroundStyle(Palette.muted)
                if let error = timeline.storageError { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                PrimaryButton(title: exporting ? "准备导出…" : "导出完整时间轴", icon: "square.and.arrow.up", enabled: !timeline.turns.isEmpty && !exporting) {
                    exporting = true
                    Task { defer { exporting = false }; do { exportURL = try await timeline.export() } catch { self.error = "导出失败，历史记录没有删除。" } }
                }.accessibilityIdentifier("timeline-export")
                if let exportURL {
                    ShareLink(item: exportURL) { Label("分享 / 存储到文件（Markdown）", systemImage: "doc") }
                    Text("这是点击导出时的快照；之后的新对话需重新导出。可通过系统分享保存到文件、NAS 文件提供器或 Obsidian。")
                        .font(.caption2).foregroundStyle(Palette.muted)
                }
                if timeline.turns.isEmpty {
                    Card { EmptyState(icon: "clock", title: "还没有对话", detail: "真实对话会按时间自动记录在本机。\n关闭实时页不会删除历史。") }
                }
                ForEach(timeline.turns.reversed()) { turn in
                    Card {
                        HStack { Text(turn.startedAt.formatted(date: .abbreviated, time: .standard)).font(.caption); Spacer(); Badge(text: turn.outcome) }
                        Label("我", systemImage: "person").font(.caption.bold()).foregroundStyle(Palette.green)
                        Text(turn.question.isEmpty ? "未收到有效识别文字" : turn.question).font(.subheadline).textSelection(.enabled)
                        Divider().overlay(Palette.line)
                        Label("AI", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(Palette.green)
                        Text(turn.answer.isEmpty ? "没有生成回答" : turn.answer).font(.subheadline).textSelection(.enabled)
                    }.privacySensitive()
                }
            }.padding(24)
        }.background(Palette.background).navigationTitle("对话时间轴").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar).preference(key: CompanionTabBarHiddenPreference.self, value: true)
            .alert("导出", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("知道了") {} } message: { Text(error ?? "") }
    }
}
