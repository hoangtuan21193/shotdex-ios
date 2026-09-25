import SwiftUI

/// Photos' filter menu, ShotDex's filters — one menu for every grid that
/// offers it (Library, Album Detail, Smart Album), so the rows cannot drift
/// apart between screens (FS-01.05 §5, FS-06.09).
///
/// The quick filters sit under a `Filter:` header, then Sort By and the aspect
/// toggle. A screen that has no quick filters passes `criteria: nil` and the
/// whole `Filter:` section is left out; one that has no Advanced Filter passes
/// `onAdvancedFilter: nil` and that row is left out.
struct PhotoFilterMenu<SortContent: View>: View {
    /// The quick filters, or nil for a screen that has none.
    var criteria: Binding<FilterCriteria>?
    /// Whether "All Items" shows as checked. A screen with an advanced query
    /// active is filtered even while its quick filters are empty.
    var isShowingAllItems: Bool
    /// "All Items": clears every filter the screen holds.
    var onShowAllItems: () -> Void
    var onAdvancedFilter: (() -> Void)?
    /// The Sort By submenu's contents — a `Picker`, so the current order carries
    /// the system checkmark on every screen.
    @ViewBuilder var sortContent: SortContent

    /// Shared with every grid: turned on here, it applies everywhere.
    @AppStorage(SettingsKeys.aspectRatioGrid) private var showsAspectTiles = false

    var body: some View {
        Menu {
            if let criteria {
                filterSection(criteria)
            }

            Section {
                Menu {
                    sortContent
                } label: {
                    Label("Sort By", systemImage: "arrow.up.arrow.down")
                }
                // Photos' aspect toggle, in the same menu as the order: both
                // are "how the grid is laid out", not "which photos are in
                // it", which is what the section above answers.
                Toggle(isOn: $showsAspectTiles) {
                    Label("Aspect Ratio Grid", systemImage: "rectangle.3.group")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .tint(.primary)
        .accessibilityLabel("Filter and sort")
    }

    private func filterSection(_ criteria: Binding<FilterCriteria>) -> some View {
        Section("Filter:") {
            Toggle(isOn: Binding(
                get: { isShowingAllItems },
                set: { _ in onShowAllItems() }
            )) {
                Label("All Items", systemImage: "square.grid.3x3")
            }
            Toggle(isOn: criteria.favoritesOnly) {
                Label("Favorites", systemImage: "heart")
            }
            // One row per kind rather than a submenu: the whole filter list
            // reads as one column, the way Photos lays it out.
            Toggle(isOn: mediaKindBinding(criteria, kind: .photo)) {
                Label("Photos Only", systemImage: "photo")
            }
            Toggle(isOn: mediaKindBinding(criteria, kind: .video)) {
                Label("Videos Only", systemImage: "video")
            }
            // A submenu, unlike the rows above: eight capture kinds would
            // bury Advanced Filter under a wall of toggles.
            Menu {
                ForEach(PhotoMediaSubtype.allCases) { subtype in
                    Toggle(isOn: mediaSubtypeBinding(criteria, subtype: subtype)) {
                        Label(subtype.title, systemImage: subtype.systemImage)
                    }
                }
            } label: {
                Label("Capture Kind", systemImage: "square.stack.3d.down.right")
            }
            if let onAdvancedFilter {
                Button(action: onAdvancedFilter) {
                    Label("Advanced Filter…", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    /// "Photos Only" / "Videos Only": turning one on replaces the kind set, so
    /// the two rows behave as mutually exclusive filters and turning the active
    /// one off goes back to showing everything.
    private func mediaKindBinding(_ criteria: Binding<FilterCriteria>, kind: MediaKind) -> Binding<Bool> {
        Binding(
            get: { criteria.wrappedValue.mediaKinds == [kind] },
            set: { isOn in criteria.wrappedValue.mediaKinds = isOn ? [kind] : [] }
        )
    }

    /// One capture kind on or off. Several on means "any of these", which is
    /// how the rest of the multi-selects behave.
    private func mediaSubtypeBinding(
        _ criteria: Binding<FilterCriteria>,
        subtype: PhotoMediaSubtype
    ) -> Binding<Bool> {
        Binding(
            get: { criteria.wrappedValue.mediaSubtypes.contains(subtype) },
            set: { isOn in
                if isOn {
                    criteria.wrappedValue.mediaSubtypes.insert(subtype)
                } else {
                    criteria.wrappedValue.mediaSubtypes.remove(subtype)
                }
            }
        )
    }
}
