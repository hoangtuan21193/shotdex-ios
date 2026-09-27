import SwiftUI

/// Saves a connection — from Connect As's Save Connection (FS-15.04 §3,
/// step 4) or the form — and keeps its folder's Collections tile in step
/// with the Add to Collections switch (FS-17.04 §1).
enum ConnectionSaver {
    /// The switch's explanation, the same in both places.
    static let tileExplanation = String(localized: "A tile for this folder in Collections. One tap opens its photos.", comment: "Add to Collections switch: what it does")

    /// `addsTile`: on adds a tile for the saved folder (once), off removes
    /// the one that folder has. Nothing on the server changes.
    @MainActor
    @discardableResult
    static func save(
        _ draft: FileServerDraft,
        addsTile: Bool,
        servers: FileServerStore,
        shortcuts: ServerShortcutCatalog
    ) throws -> FileServer {
        let row = draft.normalized
        try servers.save(row, password: draft.password.isEmpty ? nil : draft.password)
        // The store numbers a taken name; read back what it kept.
        let saved = (try? servers.fetch(id: row.id)) ?? row
        shortcuts.reload()
        let existing = shortcuts.shortcut(serverId: saved.id, path: saved.folder)
        if addsTile, existing == nil {
            let name = saved.folder.isEmpty ? saved.name : ServerUploadPath.lastComponent(of: saved.folder)
            shortcuts.add(serverId: saved.id, path: saved.folder, name: name)
        } else if !addsTile, let existing {
            shortcuts.remove(existing.id)
        }
        return saved
    }
}

/// The last step of Connect As: what to call the connection, whether its
/// folder also gets a Collections tile, and Save. Tier A.
struct SaveConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    let folder: String
    let placeholder: String
    @State private var addsTile = false
    let onSave: (_ name: String, _ addsTile: Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("Name", text: $name, prompt: Text(placeholder))
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    LabeledContent("Folder", value: folder)
                }
                Section {
                    Toggle(isOn: $addsTile) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add to Collections")
                            Text(ConnectionSaver.tileExplanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Save Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespaces), addsTile)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
