import SwiftUI

/// The designs a photo widget can wear, as a list.
///
/// One design per look the user wants on their Home Screen. Which one a placed
/// widget wears is answered out there, in the Home Screen's own Edit Widget
/// menu, so two widgets side by side can look nothing alike — the thing four
/// fixed widget kinds could never do.
struct PhotoWidgetDesignsScreen: View {
    @Environment(AppDependencies.self) private var dependencies

    /// The design being renamed, which is also what the alert is bound to:
    /// nil means no alert.
    @State private var renaming: PhotoWidgetDesign?
    @State private var draftName = ""
    /// Pushed after Add, so a new design opens on its own settings rather than
    /// leaving the user to find the row that just appeared.
    @State private var addedDesignId: String?

    private var store: PhotoWidgetSettingsStore { dependencies.photoWidgetSettings }

    var body: some View {
        List {
            Section {
                ForEach(store.designs) { design in
                    NavigationLink {
                        PhotoWidgetSettingsScreen(designId: design.id)
                    } label: {
                        row(for: design)
                    }
                    .swipeActions(edge: .trailing) {
                        // The last design is not deletable: a placed widget
                        // has to have something to read.
                        if store.designs.count > 1 {
                            Button("Delete", role: .destructive) {
                                store.removeDesign(id: design.id)
                            }
                        }
                    }
                    .contextMenu {
                        Button("Rename") { startRenaming(design) }
                        Button("Duplicate") { store.duplicateDesign(id: design.id) }
                        if store.designs.count > 1 {
                            Button("Delete", role: .destructive) {
                                store.removeDesign(id: design.id)
                            }
                        }
                    }
                }
                .onMove { source, destination in
                    store.moveDesigns(fromOffsets: source, toOffset: destination)
                }
            } footer: {
                Text("Touch and hold the Home Screen, add a Photo Widget, then touch and hold the widget and choose Edit Widget to pick which design it wears.")
            }

            Section {
                Button("Add Design") {
                    let design = store.addDesign()
                    addedDesignId = design.id
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Photo Widget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .navigationDestination(item: $addedDesignId) { id in
            PhotoWidgetSettingsScreen(designId: id)
        }
        .alert("Rename Design", isPresented: isRenamingPresented) {
            TextField("Name", text: $draftName)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Rename") {
                if let renaming { store.renameDesign(id: renaming.id, to: draftName) }
                renaming = nil
            }
        }
        .onDisappear { store.saveNow() }
    }

    private func row(for design: PhotoWidgetDesign) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(design.name)
            Text(summary(for: design))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// What the design carries and what it draws over, in one line — the two
    /// things that tell two designs apart in a list.
    private func summary(for design: PhotoWidgetDesign) -> String {
        let rows = PhotoWidgetComponent.components(settings: design.settings)
            .map(\.title)
        let carried = rows.isEmpty ? "Photo only" : rows.joined(separator: " · ")
        return "\(carried) — \(design.settings.sourceSummary)"
    }

    private var isRenamingPresented: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private func startRenaming(_ design: PhotoWidgetDesign) {
        draftName = design.name
        renaming = design
    }
}
