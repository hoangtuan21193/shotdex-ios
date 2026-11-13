import SwiftUI

/// Search's scope (board `MAC_Search`, FS-18.02 §4): which sources a photo
/// must be in, as a `Source` condition (FS-19) — the condition smart albums
/// use, so Save as Smart Album… keeps it.
enum MacSearchScope: String, CaseIterable, Hashable {
    case all, photos, folders, servers

    var title: String {
        switch self {
        case .all: String(localized: "All Sources", comment: "Mac search scope")
        case .photos: String(localized: "Photos Library", comment: "Mac search scope")
        case .folders: String(localized: "Folders", comment: "Mac search scope: folders and drives")
        case .servers: String(localized: "Servers", comment: "Mac search scope")
        }
    }

    /// Any of the sources of this kind; nil for all of them. A kind with no
    /// source matches nothing (a rule on an id no copy has).
    func query(sources: [SourceStore.Source]) -> SmartAlbumQuery? {
        let ids: [String]
        switch self {
        case .all: return nil
        case .photos: ids = [PhotoLibrarySource.id]
        case .folders: ids = sources.filter { $0.kind == "folder" || $0.kind == "drive" }.map(\.id)
        case .servers: ids = sources.filter { $0.kind == "server" }.map(\.id)
        }
        let rules = (ids.isEmpty ? ["none"] : ids).map { SmartAlbumRule(field: .source, op: .isExactly, text: $0) }
        return SmartAlbumQuery(matchMode: .any, rules: rules)
    }

    /// Which scope a library's condition is, read back — by what the rules
    /// say, not their ids (each `query(sources:)` mints new ones).
    static func current(_ query: SmartAlbumQuery?, sources: [SourceStore.Source]) -> MacSearchScope {
        guard let query else { return .all }
        return allCases.first { $0 != .all && $0.query(sources: sources).map { same($0, query) } == true } ?? .all
    }

    static func same(_ a: SmartAlbumQuery, _ b: SmartAlbumQuery) -> Bool {
        func key(_ query: SmartAlbumQuery) -> [String] { query.rules.map { "\($0.field)|\($0.op)|\($0.text)" }.sorted() }
        return a.matchMode == b.matchMode && key(a) == key(b)
    }

    /// Whether a saved smart album can keep this scope: one source nests in
    /// its "all of" conditions, several do not.
    func nestsInSmartAlbum(sources: [SourceStore.Source]) -> Bool {
        (query(sources: sources)?.rules.count ?? 0) <= 1
    }
}

/// The bar under the toolbar while a search or filter is on: the scope,
/// the count, Save as Smart Album….
struct MacSearchScopeBar: View {
    @Binding var scope: MacSearchScope
    let count: String
    /// False when the scope cannot go into a saved album with this search.
    let canSave: Bool
    let saveAsSmartAlbum: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            MacSegments(choices: MacSearchScope.allCases.map { ($0, $0.title) }, selected: scope,
                        label: String(localized: "Search in", comment: "Mac search scope: VoiceOver")) { picked in
                if picked != scope { scope = picked }
            }
            .frame(width: 360)
            Text(count).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            let reason = String(localized: "A smart album can be kept in one source; pick All Sources or Photos Library to save this search.",
                                comment: "Mac search: Save off for a scope that cannot nest")
            Button(String(localized: "Save as Smart Album…", comment: "Mac search: keep this search"), action: saveAsSmartAlbum)
                .buttonStyle(MacPushButtonStyle(isDefault: false))
                .fixedSize()
                .disabled(!canSave)
                .help(canSave ? "" : reason)
                .accessibilityHint(canSave ? "" : reason)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

/// The search field's suggestions (board `MAC_Search`): the query itself,
/// how it reads, cameras and lenses that match the last word, saved
/// searches, recent ones, and Advanced Search….
struct MacSearchSuggestions: View {
    let text: String
    /// Library values matching what is typed, ranked, with photo counts
    /// (FS-01.03c §8) — cameras, lenses, places, dates, kinds.
    let groups: [SearchGroup]
    let smartAlbums: [SmartAlbum]
    let recents: [String]
    /// How the parser reads the text: "Camera Canon EOS R6 · Focal 85mm".
    let reading: [String]
    let openSmartAlbum: (SmartAlbum) -> Void
    /// Runs the search for this text (a suggestion is a search, not just a fill).
    let search: (String) -> Void
    /// A value picked: it becomes a token in the field.
    let choose: (SearchGroup) -> Void
    let advancedSearch: () -> Void

    var body: some View {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            Button { search(trimmed) } label: {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "Search “\(trimmed)”", comment: "Mac search suggestion: run the typed query"))
                        if !reading.isEmpty {
                            Text(reading.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                } icon: { Image(systemName: "magnifyingglass") }
            }
        }
        if !groups.isEmpty {
            Section(String(localized: "In Your Library", comment: "Mac search suggestions: library values matching the text")) {
                ForEach(groups) { group in
                    Button { choose(group) } label: {
                        Label {
                            HStack {
                                Text(group.name)
                                Text(group.category.label).foregroundStyle(.secondary)
                                Spacer()
                                Text(group.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                            }
                        } icon: { Image(systemName: group.category.symbol) }
                    }
                }
            }
        }
        let saved = smartAlbums.filter { trimmed.isEmpty || $0.name.localizedCaseInsensitiveContains(trimmed) }.prefix(4)
        if !saved.isEmpty {
            Section(String(localized: "Saved Searches", comment: "Mac search suggestions: smart albums")) {
                ForEach(Array(saved), id: \.id) { album in
                    Button { openSmartAlbum(album) } label: { Label(album.name, systemImage: "gearshape") }
                }
            }
        }
        let recent = recents.filter { trimmed.isEmpty || $0.localizedCaseInsensitiveContains(trimmed) }.prefix(4)
        if !recent.isEmpty {
            Section(String(localized: "Recent", comment: "Mac search suggestions: recent searches")) {
                ForEach(Array(recent), id: \.self) { query in
                    Button { search(query) } label: { Label(query, systemImage: "clock") }
                }
            }
        }
        Button(action: advancedSearch) {
            Label(String(localized: "Advanced Search…", comment: "Mac search suggestions: open the rule editor"), systemImage: "slider.horizontal.3")
        }
    }

    /// The typed words that end with what `name` names: "Sony A7" with
    /// "Sony A7 IV" is the last two words (the longest tail, up to three,
    /// found in the name), replaced by the name.
    static func completing(_ text: String, with name: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        for count in stride(from: min(3, words.count), through: 1, by: -1) {
            let tail = words.suffix(count).joined(separator: " ")
            if name.localizedCaseInsensitiveContains(tail) {
                return (words.dropLast(count) + [name]).joined(separator: " ")
            }
        }
        return (words + [name]).joined(separator: " ")
    }

    /// The typed tail the suggestions match on: up to the last three words
    /// (so "Canon EOS R" finds "Canon EOS R5"), none right after a space.
    nonisolated static func tail(_ text: String) -> [String] {
        guard !text.hasSuffix(" ") else { return [] }
        let words = text.split(separator: " ").map(String.init)
        return (1...min(3, max(1, words.count))).compactMap { count in
            words.count >= count ? words.suffix(count).joined(separator: " ") : nil
        }.reversed()
    }

    /// Up to three names containing the longest typed tail that has any
    /// (two letters at least).
    nonisolated static func matches(_ tails: [String], in names: [String]) -> [String] {
        for tail in tails where tail.count >= 2 {
            var found: [String] = []
            for name in names where name.localizedCaseInsensitiveContains(tail) {
                found.append(name)
                if found.count == 3 { break }
            }
            if !found.isEmpty { return found }
        }
        return []
    }
}

/// The empty grid's words when a scope left nothing.
enum MacInfoScopeText {
    static func empty(_ scope: MacSearchScope, sources: [SourceStore.Source]) -> String {
        switch scope {
        case .folders where !sources.contains(where: { $0.kind == "folder" || $0.kind == "drive" }):
            String(localized: "No folders or drives are added as sources.", comment: "Mac search: Folders scope, none added")
        case .servers where !sources.contains(where: { $0.kind == "server" }):
            String(localized: "No servers are added as sources.", comment: "Mac search: Servers scope, none added")
        default:
            String(localized: "No photo in \(scope.title) matches.", comment: "Mac search: a scope leaves nothing")
        }
    }
}
