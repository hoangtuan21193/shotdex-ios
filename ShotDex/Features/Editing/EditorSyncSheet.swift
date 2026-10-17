import SwiftUI

/// One opening of the Sync sheet.
struct EditorSyncRequest: Identifiable {
    let id = UUID()
    var ticks: EditorSyncGroups
}

/// Sync to N Photos (FS-03.09b §2, `MAC_EditBatch`): The Look on, This Frame
/// Only off, every group its own tick. The ticks are remembered for the next
/// Sync Look… and for Auto Sync and Apply Previous.
struct EditorSyncSheet: View {
    @State var ticks: EditorSyncGroups
    let photoCount: Int
    let onSync: (EditorSyncGroups) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(EditorSyncGroup.lookColumn) { toggle($0) }
                } header: {
                    Text("The Look", comment: "Sync sheet: the column of groups that travel by default")
                }
                Section {
                    ForEach(EditorSyncGroup.frameColumn) { toggle($0) }
                } header: {
                    Text("This Frame Only", comment: "Sync sheet: the column of groups placed on one frame")
                } footer: {
                    Text("These belong to one frame, so Sync Look leaves them out. Check them to copy them anyway — they land at the same place in each photo.",
                         comment: "Sync sheet: why the frame groups start unchecked")
                }
                Section {
                    Button(String(localized: "Check All", comment: "Sync sheet: tick every group")) {
                        ticks = .everything
                    }
                    Button(String(localized: "Check None", comment: "Sync sheet: untick every group")) {
                        ticks.groups = []
                    }
                }
            }
            .navigationTitle(Self.title(photoCount))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Sync sheet: close without syncing")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Sync", comment: "Sync sheet: apply the ticked groups to the other photos")) {
                        onSync(ticks)
                        dismiss()
                    }
                    .disabled(ticks.groups.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func toggle(_ group: EditorSyncGroup) -> some View {
        Toggle(group.title, isOn: Binding(
            get: { ticks.contains(group) },
            set: { isOn in
                if isOn { ticks.groups.insert(group) } else { ticks.groups.remove(group) }
            }
        ))
    }

    static func title(_ count: Int) -> String {
        count == 1
            ? String(localized: "Sync to 1 Photo", comment: "Sync sheet title")
            : String(localized: "Sync to \(count) Photos", comment: "Sync sheet title")
    }

    static func rememberedTicks(_ defaults: UserDefaults = .standard) -> EditorSyncGroups {
        guard let data = defaults.data(forKey: SettingsKeys.editorSyncGroups),
              let ticks = try? JSONDecoder().decode(EditorSyncGroups.self, from: data),
              !ticks.groups.isEmpty
        else { return .look }
        return ticks
    }

    static func remember(_ ticks: EditorSyncGroups, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(ticks) { defaults.set(data, forKey: SettingsKeys.editorSyncGroups) }
    }
}
