import SwiftUI

/// The shared rule-builder body: a match-mode picker plus a grow-as-you-go
/// list of conditions (each a `SmartAlbumRuleRow`), with a live match-count
/// footer. Rendered as `Section`s, so the parent embeds it inside its own
/// `List`. Used by both the smart-album editor (`SmartAlbumEditorSheet`) and
/// the Library advanced search (`AdvancedSearchSheet`) so the two stay in sync.
struct RuleBuilderSections: View {
    @Binding var query: SmartAlbumQuery
    let brands: [String]
    let bodies: [String]
    let lenses: [String]
    var places: [String] = []
    /// Live count of matching photos; nil hides the footer.
    var matchCount: Int?
    /// Which sections to draw. A wide sheet puts the scope (media type and
    /// match mode) in one column and the conditions in the other.
    var parts: Parts = .all
    /// Absent in previews and tests; then the Keyword field suggests nothing.
    @Environment(AppDependencies.self) private var dependencies: AppDependencies?
    @State private var keywords: [String] = []
    @State private var sources: [(value: String, label: String)] = []
    @State private var servers: [(value: String, label: String)] = []
    /// Server sources by id → their connection, for the Folder row.
    @State private var serverConnections: [String: String] = [:]
    /// Hosts the Folder row's browser; without one the row is not offered.
    @Environment(SourceFolderPicker.self) private var folderPicker: SourceFolderPicker?

    /// An Original condition while the check has photos left.
    private var uncheckedOriginals: Bool {
        guard query.usesOriginal, let check = dependencies?.originalPresenceCheck else { return false }
        return check.progress.checked < check.progress.total
    }

    /// Photo-vs-video as a scope control instead of a condition row. Backed by a
    /// single `.mediaType` rule so it compiles through the same SQL builder as
    /// everything else; "All" simply removes it.
    private var mediaKind: Binding<MediaKind?> {
        Binding(
            get: {
                query.rules
                    .first { $0.field == .mediaType && $0.op == .isExactly }
                    .flatMap { MediaKind(rawValue: $0.text) }
            },
            set: { kind in
                query.rules.removeAll { $0.field == .mediaType && $0.op == .isExactly }
                guard let kind else { return }
                query.rules.insert(
                    SmartAlbumRule(field: .mediaType, op: .isExactly, text: kind.rawValue),
                    at: 0
                )
            }
        )
    }

    /// Editable bindings for the conditions shown as rows.
    private var visibleRuleBindings: [Binding<SmartAlbumRule>] {
        Array($query.rules).filter { $0.wrappedValue.field != .mediaType }
    }

    /// The connection's browser in choose-folder mode, opened at the
    /// condition's folder; the answer is kept from the source's root.
    private func chooseFolder(for rule: SmartAlbumRule) {
        guard let dependencies, let connectionId = serverConnections[rule.text],
              let server = try? dependencies.fileServers.fetch(id: connectionId) else { return }
        let session = ServerBrowseSession(server: server, client: RemoteFileClientFactory.make(
            for: server, password: dependencies.fileServers.password(for: server.id) ?? ""
        ))
        let start = SourceFolderPath.absolute(rule.folder, root: server.folder)
        let picker = ServerBrowserModel(session: session, start: start, mode: .chooseFolder) { folder in
            ServerFolderModel(
                session: session, folder: folder, cache: dependencies.serverThumbnails,
                downloads: dependencies.serverDownloads,
                existingAssetIds: { PhotoKitAssetCreator.existingAssetIds($0) }
            )
        }
        folderPicker?.pick = .init(ruleId: rule.id, root: server.folder, route: FolderPickerRoute(model: picker))
    }

    enum Parts {
        case all, scope, conditions
    }

    var body: some View {
        if parts != .conditions { scopeSections }
        if parts != .scope { conditionsSection }
    }

    @ViewBuilder
    private var scopeSections: some View {
        Section {
            Picker("Media Type", selection: mediaKind) {
                Text("All").tag(MediaKind?.none)
                ForEach(MediaKind.allCases) { kind in
                    Text(kind.displayName).tag(MediaKind?.some(kind))
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Media Type")
        } footer: {
            if query.matchMode == .any, mediaKind.wrappedValue != nil {
                Text("Counts as one of the conditions, so it widens the match rather than narrowing it.")
            }
        }

        Section {
            Picker("Match", selection: $query.matchMode) {
                Text("All").tag(RuleMatchMode.all)
                Text("Any").tag(RuleMatchMode.any)
            }
            .pickerStyle(.segmented)
            Text(query.matchMode == .all
                ? "Photos must match every condition below."
                : "Photos must match at least one condition below.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var conditionsSection: some View {
        Section {
            // The media-type rule has its own control above, so it is filtered
            // out of the rows rather than skipped inside the `ForEach` — swipe
            // offsets have to line up with what is actually on screen.
            ForEach(visibleRuleBindings, id: \.wrappedValue.id) { $rule in
                SmartAlbumRuleRow(
                    rule: $rule,
                    brands: brands,
                    bodies: bodies,
                    lenses: lenses,
                    places: places,
                    keywords: keywords,
                    sources: sources,
                    servers: servers,
                    folderSources: folderPicker == nil ? [] : Set(serverConnections.keys),
                    onChooseFolder: { chooseFolder(for: rule) },
                    onDelete: { query.rules.removeAll { $0.id == rule.id } }
                )
            }
            .onDelete { offsets in
                let deleted = Set(offsets.map { visibleRuleBindings[$0].wrappedValue.id })
                query.rules.removeAll { deleted.contains($0.id) }
            }

            Button {
                query.rules.append(SmartAlbumRule())
            } label: {
                Label("Add Condition", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Conditions")
        } footer: {
            if let matchCount {
                // Unchecked photos match neither value (FS-06.10 §3): the
                // count grows as the check goes on. Two keys, so the count
                // keeps its plural forms.
                Text("Matches \(matchCount) photo.")
                    + (uncheckedOriginals ? Text(" ") + Text("Photos not checked yet aren’t counted.") : Text(""))
            }
        }
        .task {
            if let database = dependencies?.database {
                let store = SourceStore(database: database)
                let all = (try? store.sources()) ?? []
                // A server is not a place a photo lives here; it is a question
                // asked of a Photos item — Also on Server (FS-19.07 §7).
                sources = all.filter { $0.kind != "server" }.map { ($0.id, $0.name) }
                servers = all.filter { $0.kind == "server" }.map { ($0.id, $0.name) }
                serverConnections = (try? store.serverConnections()) ?? [:]
            }
        }
        .task {
            // The Keyword field's suggestions, from the same catalog as the
            // Add Keyword field (FS-02.07 §7).
            guard ExtendedMetadataSupport.isAvailable, let cache = dependencies?.filterSuggestions else { return }
            keywords = await cache.load().keywords.map(\.keyword)
        }
    }
}

/// The Folder row's browser (FS-19.07 §7), presented by the sheet that
/// hosts the rule builder: a sheet attached inside the builder's `List`
/// section is copied onto every row, and presenting one took the whole
/// editor down with it.
@MainActor
@Observable
final class SourceFolderPicker {
    struct Pick: Identifiable {
        let id = UUID()
        let ruleId: UUID
        /// The source's root on the server — the connection's Folder.
        let root: String
        let route: FolderPickerRoute
    }

    var pick: Pick?
}

extension View {
    /// Presents `picker`'s browser over this view and writes the chosen
    /// folder into the condition, relative to the source's root.
    func sourceFolderPicker(_ picker: SourceFolderPicker, query: Binding<SmartAlbumQuery>) -> some View {
        environment(picker)
            .sheet(item: Binding(get: { picker.pick }, set: { picker.pick = $0 })) { pick in
                NavigationStack {
                    ServerBrowserScreen(model: pick.route.model) { chosen in
                        if let folder = SourceFolderPath.relative(chosen: chosen, root: pick.root),
                           let index = query.wrappedValue.rules.firstIndex(where: { $0.id == pick.ruleId }) {
                            query.wrappedValue.rules[index].folder = folder.isEmpty ? nil : folder
                        }
                        picker.pick = nil
                    }
                }
                .onDisappear { Task { await pick.route.model.session.close() } }
            }
    }
}
