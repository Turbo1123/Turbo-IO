import SwiftUI

struct TodoDeliveryView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @EnvironmentObject private var features: CompanionDeviceFeatures
    @EnvironmentObject private var voice: CompanionVoiceRuntime
    @State private var confirmRetry = false
    private var rows: [LocalTodo] { store.todos.filter { $0.archivedAt == nil } }
    var body: some View {
        List {
            Section {
                Text(L10n.text("Local edits are kept until the next send. Reconnecting does not automatically resend everything. Sending a new item for the first time still requires confirmation on the To-Do page.", locale: locale))
                Text(L10n.text("Submission does not mean the glasses acknowledged each item. Returned completion status does not prove the title version arrived. Scheduled times are not sent.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Retry Pending Changes to Linked Items", locale: locale)) { confirmRetry = true }
                    .disabled(!voice.ready || !rows.contains { $0.wireID != nil && $0.delivery?.pending == true })
                    .accessibilityIdentifier("todo-retry-pending")
                Text(L10n.deviceFeatureStatus(features.todoStatus, locale: locale)).font(.caption)
                if let error = features.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
            }
            Section(L10n.text("Local Send History", locale: locale)) {
                if rows.isEmpty { Text(L10n.text("No To-Do Send History Yet", locale: locale)).accessibilityIdentifier("todo-delivery-empty") }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(row.title).font(.headline)
                        Text(L10n.todoDelivery(row, locale: locale)).font(.caption)
                        if let date = row.delivery?.submittedAt {
                            Text(L10n.text("Last submission: ", locale: locale) + date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard).locale(locale))).font(.caption2)
                        }
                        if let observed = row.delivery?.conflict {
                            Text(L10n.format("Phone: %@ · Glasses report: %@", locale: locale, String(describing: row.completed ? L10n.text("Completed", locale: locale) : L10n.text("Incomplete", locale: locale)), String(describing: observed.completed ? L10n.text("Completed", locale: locale) : L10n.text("Incomplete", locale: locale))))
                                .font(.caption)
                            Text(L10n.format("Important flag: Phone %@ · Glasses %@", locale: locale, String(describing: (row.important ?? false) ? L10n.text("Yes", locale: locale) : L10n.text("No", locale: locale)), String(describing: observed.important.map { $0 ? L10n.text("Yes", locale: locale) : L10n.text("No", locale: locale) } ?? L10n.text("Not provided", locale: locale))))
                                .font(.caption)
                            Text(L10n.text("Keeps the local title and scheduled time. These choices resolve the local conflict only and do not send immediately.", locale: locale))
                                .font(.caption2).foregroundStyle(.secondary)
                            Button(L10n.text("Keep Phone Status and Queue for Sending", locale: locale)) { store.resolveTodoConflict(row.id, useGlassesStatus: false) }
                                .buttonStyle(.borderless)
                            Button(L10n.text("Use Glasses Status and Keep Local Title", locale: locale)) { store.resolveTodoConflict(row.id, useGlassesStatus: true) }
                                .buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 6)
                }
            }
        }.navigationTitle(L10n.text("Pending Sends and Conflicts", locale: locale)).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(L10n.text("Retry pending changes to items linked to the current glasses? New phone-only items will not be sent.", locale: locale), isPresented: $confirmRetry) {
                Button(L10n.text("Retry Pending Sends", locale: locale)) { features.syncTodos(pendingOnly: true) }
            }
    }
}
