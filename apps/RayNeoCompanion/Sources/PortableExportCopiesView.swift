import SwiftUI

struct PortableExportCopiesView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var archive: LocalArchiveController
    @State private var selected: PortableExportCopy?
    var body: some View {
        List {
            Section {
                Text(L10n.text("Manages only copy directories created during ZIP export, including snapshots and failed temporary packages. Original recording archives, reception caches, and text revisions stay untouched.", locale: locale))
                Text(L10n.text("Moving copies to the holding area is reversible and frees export slots, but does not free disk space. Each area holds up to 20 copies. Nothing is deleted automatically or permanently.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L10n.text("Directory scanning does not verify file contents. To share again, return to Recording Details and generate a new verified package.", locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.text("Refresh Copy List", locale: locale)) { Task { await archive.loadExportCopies() } }.disabled(archive.isBusy)
                if archive.exportCopies.unrecognized > 0 {
                    Text(L10n.format("%@ abnormal or unknown directories are left in place; moving them is not available.", locale: locale, String(describing: archive.exportCopies.unrecognized)))
                        .foregroundStyle(Palette.amber)
                }
                if let error = archive.errorMessage { Text(error).foregroundStyle(Palette.amber) }
                if let status = archive.statusMessage { Text(status).font(.caption) }
            }
            ForEach([false, true], id: \.self) { trash in
                Section(trash ? L10n.text("Recoverable Holding Area", locale: locale) : L10n.text("Export Copies", locale: locale)) {
                    let rows = archive.exportCopies.copies.filter { $0.inTrash == trash }
                    if rows.isEmpty { Text(trash ? L10n.text("Holding Area Is Empty", locale: locale) : L10n.text("No Export Copies Created Yet", locale: locale)) }
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.text("Export ", locale: locale) + row.id.uuidString.prefix(8)).font(.headline)
                            Text(row.modifiedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)) + " · " + ByteCountFormatter.string(fromByteCount: row.bytes, countStyle: .file)).font(.caption)
                            Button(trash ? L10n.text("Restore This Copy", locale: locale) : L10n.text("Move to Recoverable Holding Area", locale: locale)) { selected = row }
                                .disabled(archive.isBusy).buttonStyle(.borderless)
                                .accessibilityIdentifier("export-copy-move-\(row.id.uuidString)")
                        }
                    }
                }
            }
        }.navigationTitle(L10n.text("ZIP Export Copies", locale: locale)).navigationBarTitleDisplayMode(.inline)
            .task { await archive.loadExportCopies() }
            .confirmationDialog(selected.map { "\($0.inTrash ? "恢复" : "暂存")导出副本 \($0.id.uuidString.prefix(8))？只移动派生副本，原归档不变。" } ?? L10n.text("Confirm Action", locale: locale),
                isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                if let row = selected {
                    Button(row.inTrash ? L10n.text("Confirm Restore Copy", locale: locale) : L10n.text("Confirm Move to Holding Area", locale: locale)) {
                        selected = nil
                        Task { await archive.moveExportCopy(row.id, toTrash: !row.inTrash) }
                    }
                }
            }
    }
}
