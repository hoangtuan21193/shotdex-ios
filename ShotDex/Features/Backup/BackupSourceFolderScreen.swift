import SwiftUI

/// Picks the folder of a folder, drive or server source to back up
/// (FS-22.01 §2) — from the copies the FS-19 scan recorded, so it works
/// while the drive is unplugged too. ‹ is the folder above (each folder is
/// pushed); ✕ goes back to the form without choosing.
struct BackupSourceFolderScreen: View {
    let sourceId: String
    /// Relative to the source; "" = its top.
    let folder: String
    let sourceName: String
    var choose: (String) -> Void
    var open: (String) -> Void
    var close: () -> Void

    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let children = SourceCopyBackupSource.subfolders(of: folder, sourceId: sourceId, database: dependencies.database)
        List {
            Section {
                Button {
                    choose(folder)
                } label: {
                    Label(folder.isEmpty
                          ? String(localized: "Back Up the Whole Source", comment: "Source folder picker: use the entire source")
                          : String(localized: "Back Up This Folder", comment: "Source folder picker: use the folder shown"),
                          systemImage: "checkmark.circle")
                }
            }
            if !children.isEmpty {
                Section(String(localized: "Folders", comment: "Source folder picker section")) {
                    ForEach(children, id: \.self) { name in
                        Button {
                            open(folder.isEmpty ? name : "\(folder)/\(name)")
                        } label: {
                            HStack {
                                Label(name, systemImage: "folder")
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
        }
        .navigationTitle(folder.isEmpty ? sourceName : (folder as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }
        }
    }
}
