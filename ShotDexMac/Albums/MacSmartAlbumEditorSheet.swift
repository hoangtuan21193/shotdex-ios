import SwiftUI

/// New Smart Album… / Edit on the Mac (board `MAC_SmartAlbumEditor`,
/// FS-18.04 §1, FS-19.07 §7): a 640×560 sheet — name, media type, Match
/// all/any, the conditions, a live count. A Source condition on a server
/// source gets the Folder row; Choose… browses that server.
struct MacSmartAlbumEditorSheet: View {
    var existing: SmartAlbum?
    var onSaved: (SmartAlbum) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(MacDependencies.self) private var dependencies
    @State private var name: String
    @State private var query: SmartAlbumQuery
    @State private var brands: [String] = []
    @State private var bodies: [String] = []
    @State private var lenses: [String] = []
    @State private var sources: [(value: String, label: String)] = []
    /// Server sources by id → their connection, for the Folder row.
    @State private var serverConnections: [String: String] = [:]
    @State private var matchCount: Int?
    @State private var takenNames: Set<String> = []
    @State private var folderPick: FolderPick?

    struct FolderPick: Identifiable {
        let id = UUID()
        let ruleId: UUID
        let server: FileServer
        let password: String
    }

    init(existing: SmartAlbum? = nil, onSaved: @escaping (SmartAlbum) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _name = State(initialValue: existing?.name ?? "")
        var initial = existing?.query ?? .empty
        if initial.rules.isEmpty { initial.rules = [SmartAlbumRule()] }
        _query = State(initialValue: initial)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDuplicateName: Bool { !trimmedName.isEmpty && takenNames.contains(trimmedName.lowercased()) }
    private var canSave: Bool { !trimmedName.isEmpty && !query.isEmpty && !isDuplicateName }

    private var visibleRules: [Binding<SmartAlbumRule>] {
        Array($query.rules).filter { $0.wrappedValue.field != .mediaType }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(existing == nil ? String(localized: "New Smart Album", comment: "Mac smart album sheet title")
                                 : String(localized: "Edit Smart Album", comment: "Mac smart album sheet title: editing"))
                .font(.headline)
                .padding([.horizontal, .top], 24)
            Form {
                Section {
                    TextField(String(localized: "Name:", comment: "Mac smart album sheet row"), text: $name,
                              prompt: Text("Smart Album Name", comment: "Mac smart album sheet: name placeholder"))
                    if isDuplicateName {
                        Text("A smart album named “\(trimmedName)” already exists.", comment: "Smart album: duplicate name")
                            .foregroundStyle(.red)
                    }
                    Picker(String(localized: "Match:", comment: "Mac smart album sheet row"), selection: $query.matchMode) {
                        Text("All", comment: "Smart album match mode").tag(RuleMatchMode.all)
                        Text("Any", comment: "Smart album match mode").tag(RuleMatchMode.any)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach(visibleRules, id: \.wrappedValue.id) { $rule in
                        SmartAlbumRuleRow(
                            rule: $rule, brands: brands, bodies: bodies, lenses: lenses, places: [], keywords: [],
                            sources: sources, folderSources: Set(serverConnections.keys),
                            onChooseFolder: { chooseFolder(for: rule) },
                            onDelete: { query.rules.removeAll { $0.id == rule.id } }
                        )
                    }
                    Button {
                        query.rules.append(SmartAlbumRule())
                    } label: {
                        Label(String(localized: "Add Condition", comment: "Smart album: add a rule"), systemImage: "plus.circle")
                    }
                } header: {
                    Text("Conditions", comment: "Smart album: rules section")
                } footer: {
                    if let matchCount {
                        Text("Matches \(matchCount) photos.", comment: "Smart album: live count of matching photos").monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Mac sheet: cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "OK", comment: "Mac smart album sheet: save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 640, height: 560)
        .tint(MacTheme.accent)
        .task { await prepare() }
        .task(id: query) { await recount(query) }
        .sheet(item: $folderPick) { pick in
            MacServerFolderPicker(server: pick.server, password: pick.password,
                                  start: SourceFolderPath.absolute(currentFolder(pick.ruleId), root: pick.server.folder)) { chosen in
                if let folder = SourceFolderPath.relative(chosen: chosen, root: pick.server.folder),
                   let index = query.rules.firstIndex(where: { $0.id == pick.ruleId }) {
                    query.rules[index].folder = folder.isEmpty ? nil : folder
                }
            }
        }
    }

    private func currentFolder(_ ruleId: UUID) -> String? {
        query.rules.first { $0.id == ruleId }?.folder
    }

    private func chooseFolder(for rule: SmartAlbumRule) {
        guard let connectionId = serverConnections[rule.text],
              let server = try? dependencies.fileServers.fetch(id: connectionId) else { return }
        folderPick = FolderPick(ruleId: rule.id, server: server,
                                password: dependencies.fileServers.password(for: server.id) ?? "")
    }

    private func prepare() async {
        let store = SourceStore(database: dependencies.database)
        sources = ((try? store.sources()) ?? []).map { ($0.id, $0.name) }
        serverConnections = (try? store.serverConnections()) ?? [:]
        let catalog = await dependencies.filterSuggestions.load()
        brands = catalog.brands
        bodies = catalog.bodies
        lenses = catalog.lenses
        let all = (try? dependencies.smartAlbums.fetchAllOrdered()) ?? []
        takenNames = Set(all.filter { $0.id != existing?.id }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
    }

    private func recount(_ snapshot: SmartAlbumQuery) async {
        guard !snapshot.isEmpty else {
            matchCount = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        let count = (try? await dependencies.libraryQueries.count(matching: snapshot)) ?? 0
        guard !Task.isCancelled, query == snapshot else { return }
        matchCount = count
    }

    private func save() {
        guard canSave else { return }
        let album = SmartAlbum(
            id: existing?.id ?? UUID().uuidString,
            name: trimmedName,
            query: SmartAlbumQuery(matchMode: query.matchMode, rules: query.validRules),
            createdAt: existing?.createdAt ?? Int(Date().timeIntervalSince1970)
        )
        try? dependencies.smartAlbums.upsert(album)
        onSaved(album)
        dismiss()
    }
}
