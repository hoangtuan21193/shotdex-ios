import SwiftUI

/// New Smart Album… / Edit on the Mac (board `MAC_SmartAlbumEditor`,
/// FS-18.04 §1.3, FS-06.08 §2b, FS-19.07 §7): a 640×560 sheet — name, media
/// type, Match all/any, one line per condition with − and +, ⌥+ for a nested
/// group, and the live count under the title. A Source condition on a server
/// source gets the Folder line; Choose… browses that server.
///
/// The same sheet is the Library's **Advanced Filter…** (FS-18.02 §5): with
/// `applyFilter` set it has no name, and OK runs the conditions on the grid
/// instead of saving an album.
struct MacSmartAlbumEditorSheet: View {
    var existing: SmartAlbum?
    var applyFilter: ((SmartAlbumQuery) -> Void)?
    var onSaved: (SmartAlbum) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MacDependencies.self) private var dependencies
    @State private var name: String
    @State private var query: SmartAlbumQuery
    @State private var options = MacRuleOptions()
    /// Server sources by id → their connection, for the Folder line.
    @State private var serverConnections: [String: String] = [:]
    @State private var matchCount: Int?
    /// A recount is running: the last number stays up, dimmed (FS-06.08 §3c A2).
    @State private var isCounting = false
    @State private var takenNames: Set<String> = []
    @State private var folderPick: FolderPick?
    /// ⌥ is down: the top-level + adds a group (Finder's predicate editor).
    @State private var isOptionDown = false
    @State private var showsHelp = false
    /// Names read: until then a duplicate name cannot be told, so no Create.
    @State private var hasLoaded = false
    @State private var isSaving = false
    @State private var saveError: String?
    /// Choose… is reading the server and its password off the main actor.
    @State private var isOpeningFolder = false
    /// A group just added: scrolled into view.
    @State private var scrollTarget: UUID?
    /// Keep in Photos (FS-06.12 §9): on unless turned off (user 2026-11-08).
    @State private var keepsInPhotos = SmartAlbumPhotosAlbumStore.isOnByDefault
    /// What the album had when the sheet opened: Save writes the switch only if it moved.
    @State private var keptInPhotos = SmartAlbumPhotosAlbumStore.isOnByDefault

    struct FolderPick: Identifiable {
        let id = UUID()
        let ruleId: UUID
        let server: FileServer
        let password: String
    }

    /// - Parameters:
    ///   - initialQuery: a new album's (or the filter's) starting
    ///     conditions — Save as Smart Album… hands over the Library's.
    ///   - applyFilter: set for Advanced Filter…; nil for an album.
    init(existing: SmartAlbum? = nil, initialQuery: SmartAlbumQuery? = nil,
         applyFilter: ((SmartAlbumQuery) -> Void)? = nil, onSaved: @escaping (SmartAlbum) -> Void = { _ in }) {
        self.existing = existing
        self.applyFilter = applyFilter
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        var initial = existing?.query ?? initialQuery ?? .empty
        // Always one line to type into (Media Type is not a line).
        if !initial.rules.contains(where: { $0.field != .mediaType }), initial.groups.isEmpty { initial.rules.append(SmartAlbumRule()) }
        _query = State(initialValue: initial)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicateName: Bool { !trimmedName.isEmpty && takenNames.contains(trimmedName.lowercased()) }
    private var isFilter: Bool { applyFilter != nil }
    private var canSave: Bool {
        isFilter ? !query.isEmpty : hasLoaded && !isSaving && !trimmedName.isEmpty && !query.isEmpty && !isDuplicateName
    }

    /// An Original condition while the check has photos left.
    private var uncheckedOriginals: Bool {
        let progress = dependencies.originalPresenceCheck.progress
        return query.usesOriginal && progress.checked < progress.total
    }

    /// The conditions shown as lines: Media Type has its own control.
    private var visibleRules: [SmartAlbumRule] {
        query.rules.filter { $0.field != .mediaType }
    }

    /// A line's rule found by id on every read and write: a positional
    /// binding would write into the line that moved up after a removal.
    private func ruleBinding(_ rule: SmartAlbumRule) -> Binding<SmartAlbumRule> {
        Binding(get: { query.allRules.first { $0.id == rule.id } ?? rule },
                set: { new in updateRule(rule.id) { $0 = new } })
    }

    private func matchBinding(_ group: SmartAlbumRuleGroup) -> Binding<RuleMatchMode> {
        Binding(get: { query.groups.first { $0.id == group.id }?.matchMode ?? group.matchMode },
                set: { mode in
                    if let index = query.groups.firstIndex(where: { $0.id == group.id }) { query.groups[index].matchMode = mode }
                })
    }

    private var title: String {
        isFilter ? String(localized: "Advanced Filter", comment: "Mac Library: the rule sheet that filters the grid")
            : existing == nil ? String(localized: "New Smart Album", comment: "Mac smart album sheet title")
                              : String(localized: "Edit Smart Album", comment: "Mac smart album sheet title: editing")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The count moved to the button row (board, FS-06.08 §3c D3).
            Text(title).font(.system(size: 15, weight: .semibold))
                .padding(.bottom, 16)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 12) {
                if !isFilter {
                    GridRow {
                        label(String(localized: "Name:", comment: "Mac smart album sheet row"))
                        VStack(alignment: .leading, spacing: 2) {
                            TextField(String(localized: "Smart album name", comment: "VoiceOver: the smart album name field"), text: $name,
                                      prompt: Text("Smart Album Name", comment: "Mac smart album sheet: name placeholder"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 300)
                                .accessibilityLabel(String(localized: "Name", comment: "VoiceOver: the smart album name field"))
                            if isDuplicateName {
                                Text("A smart album named “\(trimmedName)” already exists.", comment: "Smart album: duplicate name")
                                    .font(.system(size: 11)).foregroundStyle(MacTheme.redText)
                            }
                        }
                    }
                }
                GridRow {
                    label(String(localized: "Media Type:", comment: "Mac smart album sheet row"))
                    HStack(spacing: 10) {
                        Picker(String(localized: "Media Type", comment: "Mac smart album sheet row"), selection: mediaKind) {
                            Text("All", comment: "Smart album media type: photos and videos").tag(MediaKind?.none)
                            ForEach(MediaKind.allCases) { kind in Text(kind.displayName).tag(MediaKind?.some(kind)) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .tint(MacTheme.accent)
                        .fixedSize()
                        // Under Match any the kind is one more condition (as on iOS):
                        // said where the control is.
                        if query.matchMode == .any, mediaKind.wrappedValue != nil, query.conditionCount(excluding: []) > 1 {
                            Text("Counts as one condition under Match any.",
                                 comment: "Mac smart album editor: under Match any, the media type widens instead of narrowing")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    // On the column's edge with Name and Match, not centred in it.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // One condition has nothing to join (FS-06.08 §3c D1): no all / any.
                // The media type counts — it is a condition in the SQL.
                if query.conditionCount(excluding: []) <= 1 {
                    GridRow {
                        Color.clear.frame(width: 84, height: 1).gridColumnAlignment(.trailing)
                        Text("Match the following condition:", comment: "Mac smart album sheet: one condition, nothing to match all or any of")
                            .frame(height: 22)
                    }
                } else {
                GridRow {
                    label(String(localized: "Match", comment: "Mac smart album sheet row: before all/any"))
                    HStack(spacing: 8) {
                        Picker(String(localized: "Match", comment: "Mac smart album sheet row: before all/any"), selection: $query.matchMode) {
                            Text("all", comment: "Smart album match mode, inside 'Match all of the following conditions'").tag(RuleMatchMode.all)
                            Text("any", comment: "Smart album match mode, inside 'Match any of the following conditions'").tag(RuleMatchMode.any)
                        }
                        .labelsHidden()
                        .frame(width: 64)
                        Text("of the following conditions:", comment: "Mac smart album sheet: after Match all/any")
                    }
                }
                }
            }
            .padding(.bottom, 12)
            conditions
            if !isFilter { keepInPhotosRow }
            HStack(spacing: 8) {
                Button { showsHelp.toggle() } label: { Image(systemName: "questionmark") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(String(localized: "Help", comment: "Mac smart album editor: the ? button"))
                    .popover(isPresented: $showsHelp, arrowEdge: .bottom) { help }
                if let saveError {
                    Text("Couldn’t save: \(saveError)", comment: "Mac smart album editor: the album could not be written")
                        .font(.system(size: 11)).foregroundStyle(MacTheme.redText).lineLimit(2)
                } else {
                    countLine
                }
                Spacer(minLength: 8)
                // 84 wide each (board): the width goes on the label, inside the chrome.
                Button(role: .cancel) { dismiss() } label: {
                    Text("Cancel", comment: "Mac sheet: cancel").frame(minWidth: 68)
                }
                .keyboardShortcut(.cancelAction)
                Button { save() } label: { Text(saveTitle).frame(minWidth: 68) }
                    .keyboardShortcut(.defaultAction)
                    .tint(MacTheme.accentFill)
                    .disabled(!canSave)
            }
            .controlSize(.large)
            .padding(.top, 14)
        }
        .padding(.horizontal, 25)
        .padding(.top, 20)
        .padding(.bottom, 20)
        // Accent on Create and the segments only: popups stay system (board).
        .frame(width: 640, height: isFilter ? 560 : 600, alignment: .top)
        .presentationBackground(MacTheme.sheet)
        .onModifierKeysChanged(mask: .option) { _, keys in isOptionDown = keys.contains(.option) }
        .task { await prepare() }
        .task(id: query) { await recount(query) }
        .sheet(item: $folderPick) { pick in
            MacServerFolderPicker(server: pick.server, password: pick.password,
                                  start: SourceFolderPath.absolute(currentFolder(pick.ruleId), root: pick.server.folder)) { chosen in
                if let folder = SourceFolderPath.relative(chosen: chosen, root: pick.server.folder) {
                    updateRule(pick.ruleId) { $0.folder = folder.isEmpty ? nil : folder }
                }
            }
        }
    }

    /// Keep in Photos, under the conditions (board `MAC_SmartAlbumEditor`):
    /// a checkbox and what it does. Needs Full Photos access — without it the
    /// album could not hold exactly these photos; on stays turn-off-able.
    private var keepInPhotosRow: some View {
        let isFullAccess = dependencies.photoLibrary.authorizationState == .authorized
        return VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: $keepsInPhotos) {
                Text("Keep in Photos", comment: "Mac smart album editor: checkbox, keep an album in Photos with these photos")
            }
            .toggleStyle(.checkbox)
            .disabled(!isFullAccess && !keepsInPhotos)
            Group {
                if isFullAccess {
                    Text("ShotDex keeps an album in Photos with exactly these photos. It shows on your other devices through iCloud Photos.",
                         comment: "Mac smart album editor: under Keep in Photos")
                } else {
                    Text("Needs Full Photos Access in System Settings › Privacy & Security › Photos.",
                         comment: "Mac smart album editor: Keep in Photos cannot work without full Photos access")
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 20)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
    }

    private func label(_ text: String) -> some View {
        Text(text).frame(width: 84, alignment: .trailing).gridColumnAlignment(.trailing)
    }

    private var saveTitle: String {
        isFilter ? String(localized: "Filter", comment: "Mac Advanced Filter sheet: run the conditions on the grid")
            : existing == nil ? String(localized: "Create", comment: "Mac smart album sheet: save a new album")
                              : String(localized: "Save", comment: "Mac smart album sheet: save the edited album")
    }

    /// "**1,284 photos match** · Photos not checked yet aren’t counted." by
    /// the buttons, always in view (board, FS-06.08 §3c D3). No valid
    /// condition counts the whole library; a recount keeps the last number,
    /// dimmed (A2).
    private var countLine: some View {
        let count: Text = if let matchCount {
            Text(matchCount == 1
                 ? String(localized: "1 photo matches", comment: "Smart album sheet count bar, one photo")
                 : String(localized: "\(matchCount.formatted()) photos match", comment: "Smart album sheet count bar, e.g. 1,284 photos match"))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        } else {
            Text(String(localized: "Counting…", comment: "Smart album sheet count bar before the first count"))
        }
        let notes = countNotes
        return (notes.isEmpty ? count : count + Text(verbatim: " · " + notes.joined(separator: " ")))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(2)
            .opacity(isCounting && matchCount != nil ? 0.5 : 1)
            .accessibilityIdentifier("smartAlbumCount")
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var countNotes: [String] {
        var notes: [String] = []
        // A half-typed line is left out of the count and of the album: say so.
        let incomplete = query.allRules.filter { $0.field != .mediaType && !$0.isValid }.count
        if incomplete > 0 {
            notes.append(incomplete == 1
                ? String(localized: "1 incomplete condition won’t be saved.", comment: "Smart album count bar note")
                : String(localized: "\(incomplete) incomplete conditions won’t be saved.", comment: "Smart album count bar note"))
        }
        // Unchecked photos match neither value (FS-06.10 §3): the count grows as the check goes on.
        if uncheckedOriginals {
            notes.append(String(localized: "Photos not checked yet aren’t counted.", comment: "Smart album count bar note: the Original check is still running"))
        }
        return notes
    }

    /// The bordered list of condition lines and groups (board: 590×314, r10).
    private var conditions: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 0) {
                ForEach(visibleRules) { rule in
                    line(ruleBinding(rule), groupIndex: nil)
                    Divider()
                }
                ForEach(query.groups) { group in
                    MacRuleGroupLine(matchMode: matchBinding(group),
                                     onRemove: { query.groups.removeAll { $0.id == group.id }; keepOneLine() },
                                     onAdd: { addRule(after: group.rules.last?.id, inGroup: group.id) })
                    .id(group.id)
                    Divider()
                    ForEach(group.rules) { rule in
                        line(ruleBinding(rule), groupIndex: group.id)
                        Divider()
                    }
                }
            }
        }
        // Groups draw below the conditions: a new one may be out of sight.
        .onChange(of: scrollTarget) { _, id in
            guard let id else { return }
            withAnimation { proxy.scrollTo(id, anchor: .bottom) }
            scrollTarget = nil
        }
        }
        .frame(height: 314)
        .background(MacTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MacTheme.separator))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Conditions", comment: "Smart album: rules section"))
    }

    private func line(_ rule: Binding<SmartAlbumRule>, groupIndex group: UUID?) -> some View {
        let id = rule.wrappedValue.id
        return MacRuleLine(rule: rule, options: options, isNested: group != nil, addsGroup: isOptionDown,
                           onChooseFolder: { chooseFolder(for: rule.wrappedValue) },
                           onRemove: { removeRule(id, inGroup: group) },
                           onAdd: { addRule(after: id, inGroup: group) },
                           onAddGroup: {
                               let group = SmartAlbumRuleGroup()
                               query.groups.append(group)
                               scrollTarget = group.id
                           })
    }

    /// The last condition of the album stays as a blank line; a group's last
    /// takes the group with it.
    private func removeRule(_ id: UUID, inGroup group: UUID?) {
        if let group, let index = query.groups.firstIndex(where: { $0.id == group }) {
            query.groups[index].rules.removeAll { $0.id == id }
            if query.groups[index].rules.isEmpty { query.groups.remove(at: index) }
        } else {
            query.rules.removeAll { $0.id == id }
        }
        keepOneLine()
    }

    /// Never zero top-level lines: there would be no + left to add one with.
    private func keepOneLine() {
        // A top-level line holds the + (and ⌥+ for a group) even beside groups.
        if !query.rules.contains(where: { $0.field != .mediaType }) {
            query.rules.append(SmartAlbumRule())
        }
    }

    /// + puts a blank line right under its own, on the same field
    /// (FS-06.08 §3c D2), seeded the way picking that field seeds it.
    private func addRule(after id: UUID?, inGroup group: UUID?) {
        if let group, let index = query.groups.firstIndex(where: { $0.id == group }) {
            let rules = query.groups[index].rules
            let row = rules.firstIndex { $0.id == id }
            var rule = row.map { SmartAlbumRule(field: rules[$0].field) } ?? SmartAlbumRule()
            MacRuleLine.seed(&rule, options: options)
            query.groups[index].rules.insert(rule, at: row.map { $0 + 1 } ?? rules.endIndex)
            return
        }
        // An id not among the top-level lines appends at the end.
        let newId = query.insertRule(after: id ?? UUID())
        updateRule(newId) { MacRuleLine.seed(&$0, options: options) }
    }

    private func updateRule(_ id: UUID, _ change: (inout SmartAlbumRule) -> Void) {
        if let index = query.rules.firstIndex(where: { $0.id == id }) { change(&query.rules[index]); return }
        for g in query.groups.indices {
            if let index = query.groups[g].rules.firstIndex(where: { $0.id == id }) { change(&query.groups[g].rules[index]); return }
        }
    }

    /// Media Type is the album's mediaType rule, first in the list (as on iOS).
    private var mediaKind: Binding<MediaKind?> {
        Binding(
            get: { query.rules.first { $0.field == .mediaType && $0.op == .isExactly }.flatMap { MediaKind(rawValue: $0.text) } },
            set: { kind in
                query.rules.removeAll { $0.field == .mediaType && $0.op == .isExactly }
                guard let kind else { return }
                query.rules.insert(SmartAlbumRule(field: .mediaType, op: .isExactly, text: kind.rawValue), at: 0)
            }
        )
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Smart Album Conditions", comment: "Mac smart album editor help: title").font(.headline)
            Text("Photos join the album by themselves while they match. Match all needs every condition, any needs one.",
                 comment: "Mac smart album editor help: what the conditions do")
            Text("Hold Option and click + to add a group, whose own Any or All works as one condition — for example, photos from either of two lenses. Groups sit below the other conditions, one level deep.",
                 comment: "Mac smart album editor help: nested groups")
        }
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300)
        .padding(14)
    }

    private func currentFolder(_ ruleId: UUID) -> String? {
        query.allRules.first { $0.id == ruleId }?.folder
    }

    /// The server row and its Keychain password, read off the main actor.
    private func chooseFolder(for rule: SmartAlbumRule) {
        guard !isOpeningFolder, let connectionId = serverConnections[rule.text] else { return }
        isOpeningFolder = true
        let servers = dependencies.fileServers
        Task {
            let found = await Task.detached(priority: .userInitiated) { () -> (FileServer, String)? in
                guard let server = try? servers.fetch(id: connectionId) else { return nil }
                return (server, servers.password(for: server.id) ?? "")
            }.value
            isOpeningFolder = false
            guard let found else { return }
            folderPick = FolderPick(ruleId: rule.id, server: found.0, password: found.1)
        }
    }

    private func prepare() async {
        // Off the main actor: the sheet opens before the reads finish.
        let store = SourceStore(database: dependencies.database)
        let albumStore = dependencies.smartAlbums
        let existingId = existing?.id
        let links = SmartAlbumPhotosAlbumStore(database: dependencies.database)
        let kept = await Task.detached(priority: .userInitiated) {
            existingId.flatMap { try? links.link($0) }?.isEnabled ?? SmartAlbumPhotosAlbumStore.isOnByDefault
        }.value
        // The checkbox as the person left it if they clicked it while this read.
        if keepsInPhotos == keptInPhotos { keepsInPhotos = kept }
        keptInPhotos = kept
        let read = await Task.detached(priority: .userInitiated) {
            let everySource = (try? store.sources()) ?? []
            let names = ((try? albumStore.fetchAllOrdered()) ?? []).filter { $0.id != existingId }
                .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            // Servers are asked through Also on Server, not Source (FS-19.07 §7).
            return (sources: everySource.filter { $0.kind != "server" }.map { [$0.id, $0.name] },
                    servers: everySource.filter { $0.kind == "server" }.map { [$0.id, $0.name] },
                    connections: (try? store.serverConnections()) ?? [:], names: Set(names))
        }.value
        guard !Task.isCancelled else { return }
        var options = MacRuleOptions()
        options.sources = read.sources.map { ($0[0], $0[1]) }
        options.servers = read.servers.map { ($0[0], $0[1]) }
        serverConnections = read.connections
        takenNames = read.names
        options.folderSources = Set(serverConnections.keys)
        let catalog = await dependencies.filterSuggestions.load()
        options.brands = catalog.brands
        options.bodies = catalog.bodies
        options.lenses = catalog.lenses
        guard !Task.isCancelled else { return }
        self.options = options
        hasLoaded = true
    }

    /// No valid condition counts the whole library — what an album with no
    /// condition would hold (FS-06.08 §3c D3); the last number stays up,
    /// dimmed, until the new one lands (A2).
    private func recount(_ snapshot: SmartAlbumQuery) async {
        isCounting = true
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let count = try? await dependencies.libraryQueries.count(matching: snapshot.cleaned)
        guard !Task.isCancelled, query == snapshot else { return }
        if let count { matchCount = count }
        isCounting = false
    }

    private func save() {
        guard canSave else { return }
        if let applyFilter {
            applyFilter(query.cleaned)
            dismiss()
            return
        }
        let album = SmartAlbum(
            id: existing?.id ?? UUID().uuidString,
            name: trimmedName,
            query: query.cleaned,
            createdAt: existing?.createdAt ?? Int(Date().timeIntervalSince1970)
        )
        // Off the main actor: the writer may be busy with an index batch.
        isSaving = true
        saveError = nil
        Task {
            do {
                try await dependencies.smartAlbums.save(album)
                // Only after the album row exists: a link to no album is never cleaned up.
                if keepsInPhotos != keptInPhotos {
                    let links = SmartAlbumPhotosAlbumStore(database: dependencies.database)
                    let (keeps, id) = (keepsInPhotos, album.id)
                    try await Task.detached { try links.setEnabled(keeps, smartAlbumId: id) }.value
                    dependencies.photosAlbumSync?.linksChanged()
                }
                // A rename or new conditions change the album in Photos too.
                dependencies.photosAlbumSync?.setNeedsSync()
                onSaved(album)
                dismiss()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}
