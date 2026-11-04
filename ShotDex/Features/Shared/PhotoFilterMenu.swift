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
    /// A last section for what the screen does with the whole set — Album
    /// Detail's Keep on This iPhone. Nil on every other grid.
    var setActions: AnyView? = nil
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
            if let setActions {
                Section { setActions }
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
            // Right after Favorites, as the board draws it (FS-06.10 §4): the
            // same one-tap narrowing, answered by the original check.
            Toggle(isOn: criteria.originalOnDeviceOnly) {
                Label(OriginalPresence.filterTitle, systemImage: "iphone")
            }
            // Two flat rows right after Favorites — one tap, like Favorites —
            // and the stars as a submenu (FS-01.12 §7).
            Toggle(isOn: flagBinding(criteria, .picks)) {
                Label(MarkCopy.picksFilter, systemImage: "flag.fill")
            }
            Toggle(isOn: flagBinding(criteria, .rejected)) {
                Label(MarkCopy.rejectedFilter, systemImage: "xmark")
            }
            Picker(selection: criteria.ratingFilter) {
                Text(MarkCopy.anyRating).tag(RatingFilter?.none)
                ForEach(RatingFilter.menuChoices, id: \.self) { choice in
                    Text(MarkCopy.ratingMenuRow(choice)).tag(RatingFilter?.some(choice))
                }
            } label: {
                Label(MarkCopy.rating, systemImage: "star")
            }
            .pickerStyle(.menu)
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

    /// Picks / Rejected on or off. Both on means either flag.
    private func flagBinding(_ criteria: Binding<FilterCriteria>, _ flag: PhotoFlagFilter) -> Binding<Bool> {
        Binding(
            get: { criteria.wrappedValue.flags.contains(flag) },
            set: { isOn in
                if isOn {
                    criteria.wrappedValue.flags.insert(flag)
                } else {
                    criteria.wrappedValue.flags.remove(flag)
                }
            }
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

private struct OriginalOnDeviceWatch: ViewModifier {
    @Environment(AppDependencies.self) private var dependencies
    var isActive: Bool
    /// Selection is in progress: a reload would pull tiles out from under it.
    var isPaused: Bool
    var reload: @MainActor () async -> Void

    @State private var reloader: OriginalOnDeviceReloader?
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        let generation = dependencies.originalPresenceCheck.generation
        return content
            .onAppear {
                isOnScreen = true
                sync()
            }
            .onDisappear {
                isOnScreen = false
                sync()
            }
            .onChange(of: isActive) { sync() }
            .onChange(of: isPaused) { sync() }
            .onChange(of: generation) { sync() }
    }

    private func sync() {
        let check = dependencies.originalPresenceCheck
        let hooks = OriginalOnDeviceReloader.Hooks(
            open: { check.screenOpened() },
            close: { check.screenClosed() },
            reload: reload
        )
        let reloader = reloader ?? OriginalOnDeviceReloader(hooks: hooks)
        if self.reloader == nil { self.reloader = reloader }
        // The screen's closure captures its current model; keep the latest.
        reloader.hooks = hooks
        reloader.update(isActive: isActive, isOnScreen: isOnScreen, isPaused: isPaused, generation: check.generation)
    }
}

extension View {
    /// See `OriginalOnDeviceReloader`.
    func watchesOriginalOnDevice(
        _ isActive: Bool,
        isPaused: Bool = false,
        reload: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(OriginalOnDeviceWatch(isActive: isActive, isPaused: isPaused, reload: reload))
    }
}
