import SwiftUI

struct ReminderImportView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var store: CompanionStore
    @StateObject private var reader = ReminderImportController.forCurrentLaunch()
    @State private var selectedList = ""
    @State private var confirmImport = false
    @State private var showCompleted = false
    var body: some View {
        List {
            Section {
                Text(L10n.text("Import Selected To-Dos from iPhone Reminders", locale: locale)).font(.headline)
                Text(L10n.text("Grant access, then choose a list. Copies only selected items' titles, completion status, and scheduled times. Does not import notes, attachments, locations, or contacts.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("On iOS 17 and later, the permission is called “Full Access,” but Turbo IO only reads and does not change system reminders. Importing does not automatically send items to the glasses or create notifications.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                if reader.isFixture {
                    Text(L10n.text("Synthetic Test Mode · Does Not Read System Data", locale: locale)).foregroundStyle(Palette.amber).accessibilityIdentifier("reminders-fixture-banner")
                }
                Button(L10n.text("Grant Access and Read Lists", locale: locale)) { Task { selectedList = ""; await reader.loadLists() } }
                    .disabled(reader.busy).accessibilityIdentifier("reminders-authorize")
                Text(reader.status).font(.caption).accessibilityIdentifier("reminders-status")
                if let error = reader.error { Text(error).font(.caption).foregroundStyle(Palette.amber) }
                if reader.busy { ProgressView(L10n.text("Loading…", locale: locale)) }
            }
            if !reader.lists.isEmpty {
                Section(L10n.text("Choose List", locale: locale)) {
                    Picker(L10n.text("System List", locale: locale), selection: Binding(get: { selectedList }, set: { selectedList = $0; reader.cancel() })) {
                        Text(L10n.text("Select", locale: locale)).tag("")
                        ForEach(reader.lists) { list in Text(list.title).tag(list.id) }
                    }.disabled(reader.busy).accessibilityIdentifier("reminders-list-picker")
                    Button(L10n.text("Read Selected List", locale: locale)) { Task { await reader.loadReminders(listID: selectedList) } }
                        .disabled(selectedList.isEmpty || reader.busy).accessibilityIdentifier("reminders-read-list")
                    Text(L10n.text("Reads only this list, without system smart-list rules. Source snapshots are limited to 500 items. Over-limit lists are not truncated and presented as complete.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !reader.rows.isEmpty {
                Section(L10n.text("Choose Items to Import", locale: locale)) {
                    Toggle(L10n.text("Show Completed", locale: locale), isOn: $showCompleted)
                    Text(L10n.format("%@ selected (up to 100). Hiding completed items clears the selection to prevent accidental imports.", locale: locale, String(describing: reader.selected.count)))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(reader.rows.filter { showCompleted || !$0.completed }) { row in
                        Button { reader.toggle(row.id) } label: {
                            HStack(alignment: .top) {
                                Image(systemName: reader.selected.contains(row.id) ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(row.title).foregroundStyle(Palette.ink)
                                    Text(row.completed ? L10n.text("Completed in Reminders", locale: locale) : L10n.text("Incomplete in Reminders", locale: locale)).font(.caption).foregroundStyle(.secondary)
                                    if let day = SystemReminderSnapshot.dateOnlyLabel(row.dueComponents) { Text(day).font(.caption) }
                                    else if let due = row.dueAt { Text(due.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))).font(.caption) }
                                }
                            }
                        }.accessibilityIdentifier("reminders-row-\(row.id)")
                    }
                    Button(L10n.format("Import Selected into Turbo IO (%@)", locale: locale, String(describing: reader.selected.count))) { confirmImport = true }
                        .disabled(reader.selected.isEmpty || reader.busy).accessibilityIdentifier("reminders-import")
                    Text(L10n.text("This is a one-time copy, not continuous sync. Titles are limited to 300 characters. Recurrence rules, subtask relationships, notes, and system alerts are not copied. System originals stay unchanged.", locale: locale))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button(L10n.text("Clear Import Preview", locale: locale)) { reader.discardPreview(); selectedList = "" }
                    .accessibilityIdentifier("reminders-clear")
                Text(L10n.text("Repeated imports of the same source ID are skipped, including locally removed to-dos. Local edits are not overwritten, and removed items are not restored automatically. If system sync recreates source IDs, they may still be treated as new items.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle(L10n.text("System Reminders", locale: locale)).navigationBarTitleDisplayMode(.inline)
            .onChange(of: showCompleted) { _ in reader.clearSelection() }
            .onDisappear { reader.discardPreview() }
            .confirmationDialog(L10n.text("Copy the selected items into Turbo IO? System Reminders will stay unchanged, and nothing will be sent to the glasses immediately.", locale: locale), isPresented: $confirmImport) {
                Button(L10n.text("Confirm Import into Turbo IO Only", locale: locale)) { reader.importSelected(into: store) }
            }
    }
}
