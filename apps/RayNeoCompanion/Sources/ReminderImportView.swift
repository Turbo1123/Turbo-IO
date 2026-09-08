import SwiftUI

struct ReminderImportView: View {
    @EnvironmentObject private var store: CompanionStore
    @StateObject private var reader = ReminderImportController.forCurrentLaunch()
    @State private var selectedList = ""
    @State private var confirmImport = false
    @State private var showCompleted = false
    var body: some View {
        List {
            Section {
                Text("从 iPhone 的提醒事项导入所选待办").font(.headline)
                Text("先授权、再选清单。仅复制勾选条目的标题、完成状态和计划时间；不导入备注、附件、位置或联系人。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("iOS 17 起系统权限名为“完全访问”，但Turbo IO仅执行读取，不修改系统待办。导入不会自动发送到眼镜，也不创建通知。")
                    .font(.caption).foregroundStyle(.secondary)
                if reader.isFixture {
                    Text("合成测试模式 · 不读取系统数据").foregroundStyle(Palette.amber).accessibilityIdentifier("reminders-fixture-banner")
                }
                Button("授权并读取清单") { Task { selectedList = ""; await reader.loadLists() } }
                    .disabled(reader.busy).accessibilityIdentifier("reminders-authorize")
                Text(reader.status).font(.caption).accessibilityIdentifier("reminders-status")
                if let error = reader.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                if reader.busy { ProgressView("读取中…") }
            }
            if !reader.lists.isEmpty {
                Section("选择清单") {
                    Picker("系统清单", selection: Binding(get: { selectedList }, set: { selectedList = $0; reader.cancel() })) {
                        Text("请选择").tag("")
                        ForEach(reader.lists) { list in Text(list.title).tag(list.id) }
                    }.disabled(reader.busy).accessibilityIdentifier("reminders-list-picker")
                    Button("读取所选清单") { Task { await reader.loadReminders(listID: selectedList) } }
                        .disabled(selectedList.isEmpty || reader.busy).accessibilityIdentifier("reminders-read-list")
                    Text("只读取该清单，不包含系统智能列表规则。来源快照最多 500 条；超限时不截取冒充完整列表。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !reader.rows.isEmpty {
                Section("选择要导入的条目") {
                    Toggle("显示已完成", isOn: $showCompleted)
                    Text("已选 \(reader.selected.count) 条（最多 100 条）；隐藏已完成条目时会清除选择，避免误导入。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(reader.rows.filter { showCompleted || !$0.completed }) { row in
                        Button { reader.toggle(row.id) } label: {
                            HStack(alignment: .top) {
                                Image(systemName: reader.selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.title).foregroundStyle(Palette.ink)
                                    Text(row.completed ? "系统已完成" : "系统未完成").font(.caption).foregroundStyle(.secondary)
                                    if let day = SystemReminderSnapshot.dateOnlyLabel(row.dueComponents) { Text(day).font(.caption) }
                                    else if let due = row.dueAt { Text(due.formatted(date: .abbreviated, time: .shortened)).font(.caption) }
                                }
                            }
                        }.accessibilityIdentifier("reminders-row-\(row.id)")
                    }
                    Button("导入所选到Turbo IO（\(reader.selected.count)）") { confirmImport = true }
                        .disabled(reader.selected.isEmpty || reader.busy).accessibilityIdentifier("reminders-import")
                    Text("这是一次性复制，不持续同步。标题最多保留 300 字；不复制重复规则、子任务关系、备注或系统提醒。系统原件保持不变。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("清除读取预览") { reader.discardPreview(); selectedList = "" }
                    .accessibilityIdentifier("reminders-clear")
                Text("同一来源标识重复导入会跳过，包括已移除的本机待办，不覆盖编辑也不自动恢复。系统同步若重建来源标识，仍可能视为新条目。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("系统提醒事项").navigationBarTitleDisplayMode(.inline)
            .onChange(of: showCompleted) { _ in reader.clearSelection() }
            .onDisappear { reader.discardPreview() }
            .confirmationDialog("将所选条目复制到Turbo IO？不修改系统提醒事项，也不立即发送眼镜。", isPresented: $confirmImport) {
                Button("确认仅导入Turbo IO") { reader.importSelected(into: store) }
            }
    }
}
