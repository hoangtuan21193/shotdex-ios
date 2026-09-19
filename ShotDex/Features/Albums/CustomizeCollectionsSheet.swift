import SwiftUI

/// Reorders the Collections tab's sections and hides the ones a user never
/// opens.
///
/// A tier-A list with the system's own Edit button, not one pinned into edit
/// mode. A pinned list looks tidier and is broken: while a `List` is editing,
/// UIKit takes the row's touches for reordering and the visibility switches
/// stop responding — pressed on the simulator, measured, no toggle moved.
/// Edit reorders; the rest of the time the switches work.
struct CustomizeCollectionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CollectionsLayoutStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.order) { section in
                        row(section)
                    }
                    .onMove { store.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Tap a section to show or hide it, and Edit to drag them into the order you want. A section with nothing in it stays hidden whatever you choose here.")
                }

                if store.isCustomized {
                    Section {
                        Button("Reset to Default Order", role: .destructive) {
                            store.reset()
                        }
                    }
                }
            }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The whole row is the switch.
    ///
    /// A `Toggle` here did not respond to a single tap on the simulator — a
    /// `List` row that also participates in `onMove` keeps its touches for
    /// itself, and the switch never saw them. A row-wide button works in both
    /// modes and is a larger target besides.
    @ViewBuilder
    private func row(_ section: CollectionsSection) -> some View {
        if section.isAlwaysShown {
            HStack {
                Label(section.displayName, systemImage: section.systemImage)
                Spacer()
                Text("Always")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            let isShown = !store.isHidden(section)
            Button {
                store.setHidden(isShown, for: section)
            } label: {
                HStack {
                    Label(section.displayName, systemImage: section.systemImage)
                        .foregroundStyle(isShown ? Color(.label) : Color(.secondaryLabel))
                    Spacer()
                    Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isShown ? AppAccent.color : Color(.tertiaryLabel))
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isShown ? [.isSelected] : [])
        }
    }
}
