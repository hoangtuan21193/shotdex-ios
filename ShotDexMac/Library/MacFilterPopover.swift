import SwiftUI

/// Filter and Sort (board `MAC_FilterPopover`, FS-18.02 §5): the toolbar
/// button's 360-wide popover over the Library's own `FilterCriteria` and
/// sort — the same state the iOS Filter menu edits, so no filtering of its
/// own. Quick facets only; everything else is Advanced Filter… (the rule
/// sheet). Reset Filters clears what narrows the grid, not the order.
///
/// While an Advanced Filter drives the grid the quick rows are off — a
/// quick filter would silently replace it (`LibraryModel` keeps one or the
/// other) — and a line at the top says so, with Edit… and Reset Filters.
struct MacFilterPopover: View {
    @Bindable var library: LibraryModel
    @Environment(MacDependencies.self) private var dependencies
    /// "212 of 55,231 photos" — the toolbar's subtitle, repeated here.
    var countLine: String
    var advancedFilter: () -> Void
    var saveAsSmartAlbum: () -> Void

    static let width: CGFloat = 360
    private static let labelWidth: CGFloat = 68
    private static let rowHeight: CGFloat = 28
    /// What a row's control gets: 360 − 2×16 padding − 68 label − 8 gap.
    /// Menus size to their longest item; a lens name would push the
    /// popover past 360 without it.
    private static let controlWidth: CGFloat = width - 32 - labelWidth - 8
    /// A tag no camera or lens is called: the criteria hold several.
    private static let severalTag = "\u{0}several"

    private var isAdvancedOn: Bool { library.advancedQuery?.isEmpty == false }

    /// Why Save as Smart Album… / Advanced Filter… cannot carry the quick
    /// filters over, or nil when they can.
    private var gapReason: String? {
        guard !isAdvancedOn else { return nil }
        let gaps = SmartAlbumQuery.migrationGaps(library.criteria)
        guard !gaps.isEmpty else { return nil }
        return String(localized: "A smart album can't hold \(gaps.formatted(.list(type: .and))) yet. Remove it from the filter first.",
                      comment: "Mac Filter and Sort: why Save as Smart Album / Advanced Filter are off")
    }

    var body: some View {
        // The Advanced line is one row more; tighter rows keep the popover
        // inside its 480 (MAC_STYLE).
        VStack(alignment: .leading, spacing: isAdvancedOn ? 4 : 6) {
            header
            sectionDivider
            if isAdvancedOn { advancedLine }
            row(String(localized: "Sort By", comment: "Mac Filter and Sort row")) { sortControls }
            quickRows
                .disabled(isAdvancedOn)
            sectionDivider
            HStack(spacing: 8) {
                Button(String(localized: "Advanced Filter…", comment: "Mac Filter and Sort: open the rule sheet"), action: advancedFilter)
                    .disabled(gapReason != nil)
                    .help(gapReason ?? String(localized: "Filter with conditions, any or all of them.",
                                              comment: "Mac Filter and Sort: Advanced Filter button help"))
                Spacer(minLength: 0)
                Button(String(localized: "Save as Smart Album…", comment: "Mac Filter and Sort: save the conditions as a smart album"),
                       action: saveAsSmartAlbum)
                    .disabled(!library.hasActiveQuery || gapReason != nil)
                    .help(gapReason ?? (library.hasActiveQuery
                        ? String(localized: "Save these conditions as a smart album.", comment: "Mac Filter and Sort: Save as Smart Album help")
                        : String(localized: "Set a filter first; a smart album saves the filter's conditions.",
                                 comment: "Mac Filter and Sort: why Save as Smart Album is off with no filter")))
            }
            .frame(height: Self.rowHeight)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: Self.width)
        // Menus and buttons in label colour, as the board draws them; the
        // window's amber tint is for the checkboxes and the selection.
        .tint(nil)
        .presentationBackground(Color(nsColor: .windowBackgroundColor))
        .task { library.refreshFilterOptions() }
    }

    /// "Advanced Filter is on." with Edit….
    private var advancedLine: some View {
        HStack(spacing: 8) {
            Text("Advanced Filter is on.", comment: "Mac Filter and Sort: the rule sheet's conditions drive the grid")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            // Reset Filters is the header's, one row up.
            Button(String(localized: "Edit…", comment: "Mac Filter and Sort: edit the Advanced Filter"), action: advancedFilter)
                .controlSize(.small)
        }
        .frame(height: Self.rowHeight)
    }

    private func resetFilters() {
        library.criteria = .empty
        library.advancedQuery = nil
        library.sourceScope = nil
    }

    /// Between sections: the board's 45pt section pitch against 34pt rows
    /// (MAC_FilterPopover); tighter while the Advanced line takes a row.
    private var sectionDivider: some View {
        Divider().padding(.vertical, isAdvancedOn ? 0 : 2)
    }

    @ViewBuilder
    private var quickRows: some View {
            row(String(localized: "Show", comment: "Mac Filter and Sort row: photos, videos or both")) { showControl }
            sectionDivider
            row(String(localized: "Marks", comment: "Mac Filter and Sort row: favorites and flags")) {
                HStack(spacing: 16) {
                    Toggle(String(localized: "Favorites", comment: "Mac Filter and Sort: only favorites"), isOn: $library.criteria.favoritesOnly)
                    Toggle(MarkCopy.picksFilter, isOn: flag(.picks))
                    Toggle(MarkCopy.rejectedFilter, isOn: flag(.rejected))
                }
                .toggleStyle(.checkbox)
                .tint(MacTheme.accent)
            }
            // FS-06.10 §4: answered by the original check, like the Original rule.
            row(String(localized: "Storage", comment: "Mac Filter and Sort row: where the originals are")) {
                Toggle(OriginalPresence.filterTitle, isOn: $library.criteria.originalOnDeviceOnly)
                    .toggleStyle(.checkbox)
                    .tint(MacTheme.accent)
            }
            // Photos not checked yet match neither way (FS-06.10 §3): say the
            // filter is still filling while it is.
            if let line = dependencies.originalPresenceCheck.partialLine {
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.leading, Self.labelWidth + 8 + 20)
            }
            row(MarkCopy.rating) {
                Picker(MarkCopy.rating, selection: $library.criteria.ratingFilter) {
                    Text(MarkCopy.anyRating).tag(RatingFilter?.none)
                    ForEach(RatingFilter.menuChoices, id: \.self) { choice in
                        Text(MarkCopy.ratingMenuRow(choice)).tag(RatingFilter?.some(choice))
                    }
                }
                .labelsHidden()
                .frame(width: Self.controlWidth, alignment: .leading)
            }
            sectionDivider
            row(String(localized: "Camera", comment: "Mac Filter and Sort row")) {
                singlePicker(String(localized: "Camera", comment: "Mac Filter and Sort row"),
                             values: library.availableBodies, selection: $library.criteria.cameraBodies,
                             several: { String(localized: "\($0) Cameras", comment: "Mac Filter and Sort: several cameras are picked") })
            }
            row(String(localized: "Lens", comment: "Mac Filter and Sort row")) {
                singlePicker(String(localized: "Lens", comment: "Mac Filter and Sort row"),
                             values: library.availableLenses, selection: $library.criteria.lenses,
                             several: { String(localized: "\($0) Lenses", comment: "Mac Filter and Sort: several lenses are picked") })
            }
            row(String(localized: "Focal", comment: "Mac Filter and Sort row: focal length")) {
                rangeFields($library.criteria.focalRange, width: 58, kind: .focal,
                            label: String(localized: "Focal length", comment: "Mac Filter and Sort: accessibility name of the focal fields"))
                Picker(String(localized: "Focal length", comment: "Mac Filter and Sort: accessibility name of the focal fields"),
                       selection: $library.criteria.focalLengthMode) {
                    Text("Actual", comment: "Mac Filter and Sort: the lens's own focal length").tag(FocalLengthMode.actual)
                    Text("Full-Frame Equivalent", comment: "Mac Filter and Sort: focal length on full frame").tag(FocalLengthMode.equivalent)
                }
                .labelsHidden()
                // What the two 58 fields, "to" and the gaps leave of the row.
                .frame(width: 96)
            }
            row(String(localized: "ISO", comment: "Mac Filter and Sort row")) {
                rangeFields($library.criteria.isoRange, width: 84, kind: .iso,
                            label: String(localized: "ISO", comment: "Mac Filter and Sort row"))
            }
            row(String(localized: "Aperture", comment: "Mac Filter and Sort row")) {
                rangeFields($library.criteria.apertureRange, width: 84, kind: .aperture,
                            label: String(localized: "Aperture", comment: "Mac Filter and Sort row"))
            }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Filter and Sort", comment: "Mac Filter and Sort popover title")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 0)
            Text(countLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
            Button(MacFilterCopy.resetFilters, action: resetFilters)
            .controlSize(.small)
            .disabled(!library.hasActiveQuery)
        }
        .frame(height: Self.rowHeight)
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .trailing)
                .accessibilityHidden(true)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
    }

    private var sortControls: some View {
        HStack(spacing: 8) {
            Picker(String(localized: "Sort By", comment: "Mac Filter and Sort row"), selection: Binding(
                get: { LibrarySortField(library.sort) },
                set: { library.sort = $0.sort(newestFirst: LibrarySortField.isNewestFirst(library.sort)) }
            )) {
                ForEach(LibrarySortField.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: (Self.controlWidth - 8) / 2)
            Picker(String(localized: "Order", comment: "Mac Filter and Sort: sort direction"), selection: Binding(
                get: { LibrarySortField.isNewestFirst(library.sort) },
                set: { library.sort = LibrarySortField(library.sort).sort(newestFirst: $0) }
            )) {
                Text("Newest First", comment: "Mac Filter and Sort: sort direction").tag(true)
                Text("Oldest First", comment: "Mac Filter and Sort: sort direction").tag(false)
            }
            .labelsHidden()
            .frame(width: (Self.controlWidth - 8) / 2)
        }
    }

    /// All · Photos · Videos over `mediaKinds` (empty, or both, is All).
    private var showControl: some View {
        Picker(String(localized: "Show", comment: "Mac Filter and Sort row: photos, videos or both"), selection: Binding(
            get: { library.criteria.mediaKinds.count == 1 ? library.criteria.mediaKinds.first : nil },
            set: { library.criteria.mediaKinds = $0.map { [$0] } ?? [] }
        )) {
            Text("All", comment: "Mac Filter and Sort: photos and videos").tag(MediaKind?.none)
            Text("Photos", comment: "Mac Filter and Sort: photos only").tag(MediaKind?.some(.photo))
            Text("Videos", comment: "Mac Filter and Sort: videos only").tag(MediaKind?.some(.video))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: Self.controlWidth, alignment: .leading)
        // Amber, never the system accent (FS-18 AC-12).
        .tint(MacTheme.accent)
    }

    private func flag(_ flag: PhotoFlagFilter) -> Binding<Bool> {
        Binding(
            get: { library.criteria.flags.contains(flag) },
            set: { isOn in
                if isOn { library.criteria.flags.insert(flag) } else { library.criteria.flags.remove(flag) }
            }
        )
    }

    /// One camera or lens out of the library's, or Any. Criteria holding
    /// several (a chip on iOS, a search) say so rather than show one.
    private func singlePicker(_ title: String, values: [String], selection: Binding<Set<String>>,
                              several: @escaping (Int) -> String) -> some View {
        let picked = selection.wrappedValue
        return Picker(title, selection: Binding(
            get: { picked.count > 1 ? Self.severalTag : picked.first ?? "" },
            set: { if $0 != Self.severalTag { selection.wrappedValue = $0.isEmpty ? [] : [$0] } }
        )) {
            Text("Any", comment: "Mac Filter and Sort: no camera or lens constraint").tag("")
            if picked.count > 1 {
                Text(several(picked.count)).tag(Self.severalTag)
            }
            // A value the index no longer lists still shows as picked.
            ForEach(Array(Set(values).union(picked.count == 1 ? picked : []).sorted()), id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .frame(width: Self.controlWidth, alignment: .leading)
    }

    private func rangeFields(_ range: Binding<NumericRangeFilter>, width: CGFloat, kind: RangeBoundInput,
                             label: String) -> some View {
        func bound(lower: Bool) -> Binding<Double?> {
            Binding(
                get: { lower ? range.wrappedValue.lowerBound : range.wrappedValue.upperBound },
                set: { range.wrappedValue = RangeBoundInput.setting($0, lower: lower, in: range.wrappedValue) }
            )
        }
        return HStack(spacing: 6) {
            MacFilterField(value: bound(lower: true), kind: kind, width: width,
                           accessibilityLabel: String(localized: "\(label) from", comment: "Mac Filter and Sort: the lower bound field"))
            Text("to", comment: "Mac Filter and Sort: between the two bounds of a range")
                .foregroundStyle(.secondary)
            MacFilterField(value: bound(lower: false), kind: kind, width: width,
                           accessibilityLabel: String(localized: "\(label) to", comment: "Mac Filter and Sort: the upper bound field"))
        }
    }
}

/// A bound of a range: typed, or picked from the usual stops (board: a
/// field with a menu arrow). Commits on Return, when focus leaves, or when
/// the popover closes — not on every keystroke, which would re-query the
/// grid. Emptying the field clears the bound; a typo puts the text back.
struct MacFilterField: View {
    @Binding var value: Double?
    var kind: RangeBoundInput
    var width: CGFloat
    var accessibilityLabel: String
    @State private var text = ""
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            TextField(accessibilityLabel, text: $text, prompt: Text("Any", comment: "Mac Filter and Sort: an empty range bound"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .monospacedDigit()
                .padding(.leading, 8)
                .focused($isFocused)
                .onSubmit(commit)
            Menu {
                ForEach(kind.stops, id: \.self) { stop in
                    Button(kind.format(stop)) { value = stop }
                }
                Divider()
                Button(String(localized: "Any", comment: "Mac Filter and Sort: an empty range bound")) { value = nil }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: 20, height: 26)
            .accessibilityLabel(String(localized: "\(accessibilityLabel) choices", comment: "Mac Filter and Sort: the menu of usual values beside a range field"))
        }
        .frame(width: width, height: 26)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
        // A drawn field: dim it like the system controls beside it.
        .opacity(isEnabled ? 1 : 0.45)
        .onAppear { text = value.map(kind.format) ?? "" }
        .onChange(of: value) { text = value.map(kind.format) ?? "" }
        .onChange(of: isFocused) { if !isFocused { commit() } }
        // Typed, then the popover closed by a click outside: still applies.
        .onDisappear(perform: commit)
        // AppKit hands the popover's first text field the focus on open; give
        // it back, so the popover opens with no field taking keystrokes.
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = false
        }
    }

    private func commit() {
        switch kind.parse(text) {
        case .cleared: if value != nil { value = nil }
        case .value(let parsed): if parsed != value { value = parsed }
        case .invalid: break
        }
        text = value.map(kind.format) ?? ""
    }
}

/// Under the toolbar (View › Show Filter Bar): what narrows the grid, one
/// capsule each with ×. Each condition lives here only (FS-01.05 §1).
struct MacFilterBar: View {
    @Bindable var library: LibraryModel
    @Environment(MacDependencies.self) private var dependencies

    struct Chip: Identifiable {
        var id: String
        var field: String?
        var value: String
        var removalLabel: String
        var remove: () -> Void
    }

    static let height: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip($0) }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: Self.height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Active filters", comment: "Mac filter bar: accessibility name"))
            // Original on This Mac while the check runs: the grid is still
            // filling, not short of photos (FS-06.10 §3).
            if library.criteria.originalOnDeviceOnly, let line = dependencies.originalPresenceCheck.partialLine {
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 26)
            }
        }
        .padding(.vertical, 4)
    }

    private var chips: [Chip] {
        if let advanced = library.advancedQuery, !advanced.isEmpty {
            return advanced.validRules.map { rule in
                Chip(id: rule.id.uuidString, field: nil, value: rule.compactDisplaySummary,
                     removalLabel: String(localized: "Remove condition: \(rule.compactDisplaySummary)",
                                          comment: "Mac filter bar: remove an Advanced Filter condition")) {
                    var updated = advanced
                    updated.rules.removeAll { $0.id == rule.id }
                    library.advancedQuery = updated.isEmpty ? nil : updated
                }
            }
        }
        return ActiveFilterToken.tokens(for: library.criteria).map { token in
            Chip(id: token.id, field: token.field, value: token.value, removalLabel: token.removalAccessibilityLabel) {
                var criteria = library.criteria
                token.clear(&criteria)
                library.criteria = criteria
            }
        }
    }

    private func chip(_ chip: Chip) -> some View {
        HStack(spacing: 5) {
            if let field = chip.field {
                Text(field)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(chip.value)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
            Button(action: chip.remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    // 24 × 24 to click; the glyph's 16 box sits where the board
                    // draws it, 4 from the capsule's end.
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(chip.removalLabel)
        }
        .lineLimit(1)
        .padding(.leading, 10)
        .frame(height: 24)
        .background(MacTheme.fill, in: Capsule())
        // One element per condition, read as its words, × as its action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([chip.field, chip.value].compactMap { $0 }.joined(separator: " "))
        .accessibilityAction(named: String(localized: "Remove", comment: "Mac filter bar: VoiceOver action removing a condition"),
                             chip.remove)
    }
}

/// View › Filter and Sort… ⇧⌘L · Show Filter Bar (FS-18.01b).
struct MacFilterCommands: Commands {
    @AppStorage(MacFilterBar.visibilityKey) private var showsFilterBar = true

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button(String(localized: "Filter and Sort…", comment: "Mac menu: View › Filter and Sort…")) {
                NotificationCenter.default.post(name: .macShowFilterPopover, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
            Button(showsFilterBar ? String(localized: "Hide Filter Bar", comment: "Mac menu: View › Hide Filter Bar")
                                  : String(localized: "Show Filter Bar", comment: "Mac menu: View › Show Filter Bar")) {
                showsFilterBar.toggle()
            }
        }
    }
}

extension MacFilterBar {
    static let visibilityKey = "macShowsFilterBar"
}

extension Notification.Name {
    static let macShowFilterPopover = Notification.Name("macShowFilterPopover")
}

/// The Library narrowed by Original on This Mac asks the original check for
/// fresh answers while it is on screen, and reloads as batches land — at
/// most every 3 s (FS-06.10 §4; `OriginalOnDeviceReloader`, shared with iOS).
private struct MacOriginalOnDeviceWatch: ViewModifier {
    @Environment(MacDependencies.self) private var dependencies
    var isActive: Bool
    var reload: @MainActor () async -> Void
    @State private var reloader: OriginalOnDeviceReloader?
    @State private var isOnScreen = false

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true; sync() }
            .onDisappear { isOnScreen = false; sync() }
            .onChange(of: isActive) { sync() }
            .onChange(of: dependencies.originalPresenceCheck.generation) { sync() }
    }

    private func sync() {
        let check = dependencies.originalPresenceCheck
        let hooks = OriginalOnDeviceReloader.Hooks(open: { check.screenOpened() }, close: { check.screenClosed() }, reload: reload)
        let reloader = reloader ?? OriginalOnDeviceReloader(hooks: hooks)
        if self.reloader == nil { self.reloader = reloader }
        reloader.hooks = hooks
        reloader.update(isActive: isActive, isOnScreen: isOnScreen, isPaused: false, generation: check.generation)
    }
}

extension View {
    func macWatchesOriginalOnDevice(_ isActive: Bool, reload: @escaping @MainActor () async -> Void) -> some View {
        modifier(MacOriginalOnDeviceWatch(isActive: isActive, reload: reload))
    }
}

enum MacFilterCopy {
    /// One name for clearing every filter: the popover and the empty grid.
    static var resetFilters: String {
        String(localized: "Reset Filters", comment: "Mac Library: clear every filter")
    }
}

extension OriginalPresenceCheck {
    /// "Checking originals · 12,400 of 55,000" while photos are still
    /// unchecked — which no Original condition matches yet — else nil.
    var partialLine: String? {
        guard progress.checked < progress.total else { return nil }
        return OriginalPresenceProgressLine.text(checked: progress.checked, total: progress.total, finishedAt: nil)
    }
}
