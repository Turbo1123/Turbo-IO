import SwiftUI

struct TodoDeliveryView: View {
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirmRetry = false
    private var rows: [LocalTodo] { store.todos.filter { $0.archivedAt == nil } }
    var body: some View {
        List {
            Section {
                Text("本机编辑会保留到下次发送。重连不自动批量重发；首次发送新条目仍需在待办首页确认。")
                Text("已提交不是眼镜逐项确认。完成状态回传无法证明标题版本送达；计划时间不发送。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("重试已关联条目的待发送修改") { confirmRetry = true }
                    .disabled(!voice.ready || !rows.contains { $0.wireID != nil && $0.delivery?.pending == true })
                    .accessibilityIdentifier("todo-retry-pending")
                Text(features.todoStatus).font(.caption)
                if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
            }
            Section("本机发送记录") {
                if rows.isEmpty { Text("暂无待办发送记录").accessibilityIdentifier("todo-delivery-empty") }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.title).font(.headline)
                        Text(row.deliveryDescription).font(.caption)
                        if let date = row.delivery?.submittedAt {
                            Text("上次提交：" + date.formatted(date: .abbreviated, time: .standard)).font(.caption2)
                        }
                        if let observed = row.delivery?.conflict {
                            Text("手机：\(row.completed ? "已完成" : "未完成") · 眼镜回报：\(observed.completed ? "已完成" : "未完成")")
                                .font(.caption)
                            Text("重要标记：手机 \((row.important ?? false) ? "是" : "否") · 眼镜 \(observed.important.map { $0 ? "是" : "否" } ?? "未提供")")
                                .font(.caption)
                            Text("保留本机标题和计划时间。下面的选择只解决本机冲突，不立即发送。")
                                .font(.caption2).foregroundStyle(.secondary)
                            Button("保留手机状态，加入待发送") { store.resolveTodoConflict(row.id, useGlassesStatus: false) }
                                .buttonStyle(.borderless)
                            Button("采用眼镜状态，保留本机标题") { store.resolveTodoConflict(row.id, useGlassesStatus: true) }
                                .buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle("待发送与冲突").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("重试当前眼镜已关联的待发送修改？不会发送仅存手机的新条目。", isPresented: $confirmRetry) {
                Button("重试待发送") { features.syncTodos(pendingOnly: true) }
            }
    }
}
