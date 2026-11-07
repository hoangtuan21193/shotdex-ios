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
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1)
                    .accessibilityIdentifier("smartAlbumCount")
            }
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
                        if query.matchMode == .any, mediaKind.wrappedValue != nil {
                            Text("Counts as one condition under Match any.",
                                 comment: "Mac smart album editor: under Match any, the media type widens instead of narrowing")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    // On the column's edge with Name and Match, not centred in it.
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            .padding(.bottom, 12)
            conditions
            HStack(spacing: 8) {
                Button { showsHelp.toggle() } label: { Image(systemName: "questionmark") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(String(localized: "Help", comment: "Mac smart album editor: the ? button"))
                    .popover(isPresented: $showsHelp, arrowEdge: .bottom) { help }
                if let saveError {
                    Text("Couldn’t save: \(saveError)", comment: "Mac smart album editor: the album could not be written")
                        .font(.system(size: 11)).foregroundStyle(MacTheme.redText).lineLimit(2)
                }
                Spacer()
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
        .frame(width: 640, height: 560, alignment: .top)
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

    private func label(_ text: String) -> some View {
        Text(text).frame(width: 84, alignment: .trailing).gridColumnAlignment(.trailing)
    }

    private var saveTitle: String {
        isFilter ? String(localized: "Filter", comment: "Mac Advanced Filter sheet: run the conditions on the grid")
            : existing == nil ? String(localized: "Create", comment: "Mac smart album sheet: save a new album")
                              : String(localized: "Save", comment: "Mac smart album sheet: save the edited album")
    }

    /// "Matches 64 photos · Photos not checked yet aren’t counted."
    private var subtitle: String {
        guard let matchCount else {
            return String(localized: "Add conditions to choose the photos.", comment: "Mac smart album editor: no condition complete yet")
        }
        var parts = [String(AttributedString(localized: "Matches ^[\(matchCount) photo](inflect: true)",
                                             comment: "Mac smart album editor: live count of matching photos").characters)]
        // Unchecked photos match neither value (FS-06.10 §3): the count grows as the check goes on.
        if uncheckedOriginals {
            parts.append(String(localized: "Photos not checked yet aren’t counted.",
                                comment: "Smart album editor: the originals check has photos left, which no Original condition matches yet"))
        }
        // A half-typed line is left out of the count and of the album: say so.
        let incomplete = query.allRules.filter { $0.field != .mediaType && !$0.isValid }.count
        if incomplete > 0 {
            parts.append(String(AttributedString(localized: "^[\(incomplete) incomplete condition](inflect: true) ignored",
                                                 comment: "Mac smart album editor: blank or half-typed lines that Create leaves out").characters))
        }
        return parts.joined(separator: " · ")
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

    private func addRule(after id: UUID?, inGroup group: UUID?) {
        if let group, let index = query.groups.firstIndex(where: { $0.id == group }) {
            let at = query.groups[index].rules.firstIndex { $0.id == id }.map { $0 + 1 } ?? query.groups[index].rules.endIndex
            query.groups[index].rules.insert(SmartAlbumRule(), at: at)
            return
        }
        let at = query.rules.firstIndex { $0.id == id }.map { $0 + 1 } ?? query.rules.endIndex
        query.rules.insert(SmartAlbumRule(), at: at)
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

    private func recount(_ snapshot: SmartAlbumQuery) async {
        guard !snapshot.isEmpty else {
            matchCount = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let count = try? await dependencies.libraryQueries.count(matching: snapshot)
        guard !Task.isCancelled, query == snapshot else { return }
        matchCount = count
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
                onSaved(album)
                dismiss()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }
}
