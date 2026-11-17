import AppKit
import GRDB
import SwiftUI

/// Utilities › Video Projects (board `MAC_VideoProjects`, FS-12.18 §4): drafts
/// and exported projects in one grid, last edited first. A card is the
/// first three clips side by side, Draft on a draft, the length when known.
@MainActor
@Observable
final class MacVideoProjectsModel {
    struct Card: Identifiable, Equatable {
        let creation: Creation
        let recipe: VideoProjectRecipe?
        var id: String { creation.id }
        var edited: Date { Date(timeIntervalSince1970: TimeInterval(creation.updatedAt)) }
        var created: Date { Date(timeIntervalSince1970: TimeInterval(creation.createdAt)) }
        var isDraft: Bool { creation.isDraft }
        var clipIds: [String] { recipe?.clips.map(\.assetID) ?? [] }

        /// Seconds when every clip's length is known; nil otherwise (a video
        /// clip whose source length is read only when the project opens).
        var duration: Double? {
            guard let recipe, !recipe.clips.isEmpty else { return nil }
            if recipe.clips.contains(where: { $0.kind == .video && $0.trimEnd == nil && $0.sourceDuration == nil }) { return nil }
            // The export's own math: overlaps capped by their neighbours, stale ones ignored.
            let durations = recipe.clips.map(\.effectiveDuration)
            let requested = Array(recipe.transitions.prefix(max(0, durations.count - 1)).map(\.requestedOverlap))
            return VideoTimelineMath.totalDuration(durations: durations,
                                                   overlaps: VideoTimelineMath.effectiveOverlaps(requested: requested, durations: durations))
        }
    }

    private(set) var cards: [Card] = []
    private(set) var isLoading = true
    private(set) var loadFailed = false
    var order: MacCollagesModel.Order = UserDefaults.standard.string(forKey: "mac.videoProjects.order")
        .flatMap(MacCollagesModel.Order.init) ?? .lastEdited {
        didSet { UserDefaults.standard.set(order.rawValue, forKey: "mac.videoProjects.order") }
    }
    var search = ""
    private(set) var pictures: [String: CGImage] = [:]
    private var names: [String: String] = [:]
    private let dependencies: MacDependencies
    var onChange: (() -> Void)?

    init(dependencies: MacDependencies) { self.dependencies = dependencies }

    var store: CreationStore { CreationStore(database: dependencies.database) }

    func load() async {
        // Try Again shows the spinner, not the old error.
        isLoading = true
        loadFailed = false
        let store = store
        let database = dependencies.database
        let read = await Task.detached(priority: .userInitiated) { () -> ([Card], [String: String])? in
            guard let rows = try? store.fetchOrdered(kind: .video) else { return nil }
            // An unreadable recipe still shows (FS-12.18 §6): it says so when opened.
            let cards = rows.map { Card(creation: $0, recipe: $0.videoRecipe) }
            let ids = Array(Set(cards.flatMap(\.clipIds)))
            var names: [String: String] = [:]
            for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
                let rows = (try? database.reader.read { db in
                    try Row.fetchAll(db, sql: "SELECT assetId, originalFilename FROM photo_metadata WHERE assetId IN (\(chunk.map { _ in "?" }.joined(separator: ",")))",
                                     arguments: StatementArguments(chunk))
                }) ?? []
                for row in rows { if let name: String = row["originalFilename"] { names[row["assetId"]] = name } }
            }
            return (cards, names)
        }.value
        isLoading = false
        guard let read else { loadFailed = true; return }
        loadFailed = false
        cards = read.0
        names = read.1
    }

    var draftCount: Int { cards.filter(\.isDraft).count }

    var shown: [Card] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = cards.sorted { order == .lastEdited ? $0.edited > $1.edited : $0.created > $1.created }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { card in
            dateText(card).lowercased().contains(query) || detailText(card).lowercased().contains(query)
                || card.clipIds.contains { names[$0]?.lowercased().contains(query) == true }
        }
    }

    /// "Oct 3, 2026 at 2:10 PM", by the date the page is sorted by.
    func dateText(_ card: Card) -> String {
        (order == .lastEdited ? card.edited : card.created).formatted(date: .abbreviated, time: .shortened)
    }

    /// Draft: "Edited 5 min ago · 5 clips". Exported: "12 clips · 16:9".
    func detailText(_ card: Card) -> String {
        guard let recipe = card.recipe else {
            return String(localized: "Can’t be opened", comment: "Mac Video Projects: a project whose recipe is unreadable")
        }
        let clips = MacInflect.string("^[\(recipe.clips.count) clip](inflect: true)", comment: "Mac Video Projects: clips in a project")
        if card.isDraft {
            let ago = card.edited.formatted(.relative(presentation: .named))
            return String(localized: "Edited \(ago)", comment: "Mac Video Projects: when a draft was last changed") + " · " + clips
        }
        return clips + " · " + recipe.aspect.displayName
    }

    /// "0:24".
    static func lengthText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// The first three clips' thumbnails, off the main actor.
    func drawCover(_ card: Card) async {
        for id in card.clipIds.prefix(3) where pictures[id] == nil {
            guard !Task.isCancelled else { return }
            let picture: CGImage?
            #if DEBUG
            if MacDemoLibrary.isOn { picture = MacDemoLibrary.picture(for: id) } else {
                picture = await MacViewerThumbnail.load(id, side: 320, dependencies: dependencies)
            }
            #else
            // 2× the 157 pt tile.
            picture = await MacViewerThumbnail.load(id, side: 320, dependencies: dependencies)
            #endif
            if let picture { pictures[id] = picture }
        }
    }

    /// A card scrolled away gives its pictures back.
    func forget(_ card: Card) {
        for id in card.clipIds.prefix(3) { pictures[id] = nil }
    }

    /// Delete Draft / Remove from Video Projects: the record only, never a
    /// photo or video in the library. False when it could not be deleted.
    func remove(_ card: Card) async -> Bool {
        let store = store
        let id = card.id
        let removed = await Task.detached(priority: .userInitiated) { (try? store.delete(id: id)) != nil }.value
        guard removed else { return false }
        cards.removeAll { $0.id == id }
        forget(card)
        onChange?()
        return true
    }
}

struct MacVideoProjectsPage: View {
    @State private var model: MacVideoProjectsModel
    @State private var selected: String?
    @State private var removing: MacVideoProjectsModel.Card?
    @State private var removeFailed = false
    @State private var cannotOpen = false
    @State private var unreadable: MacVideoProjectsModel.Card?

    /// Open, double-click, Return: an unreadable draft says so (FS-12.18 §6);
    /// any other waits for Video Studio on the Mac.
    private func open(_ card: MacVideoProjectsModel.Card) {
        if card.recipe == nil { unreadable = card } else { cannotOpen = true }
    }

    init(dependencies: MacDependencies, changed: @escaping () -> Void) {
        let model = MacVideoProjectsModel(dependencies: dependencies)
        model.onChange = changed
        _model = State(initialValue: model)
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.loadFailed {
                ContentUnavailableView {
                    Label(String(localized: "Projects Couldn’t Be Read", comment: "Mac Video Projects: load failed"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Video projects couldn’t be read from the library. Try again.", comment: "Mac Video Projects: load failed")
                } actions: {
                    Button(String(localized: "Try Again", comment: "Mac Video Projects")) { Task { await model.load() } }
                }
            } else if model.cards.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Video Projects", comment: "Mac Video Projects: empty"), systemImage: "film.stack")
                } description: {
                    Text("Video projects made on iPhone or iPad show here, drafts included.", comment: "Mac Video Projects: empty")
                }
            } else if model.shown.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else {
                grid
            }
        }
        .preferredColorScheme(NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        .navigationTitle(String(localized: "Video Projects", comment: "Mac Video Projects: the page title"))
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .searchable(text: $model.search, placement: .toolbar, prompt: Text("Search Projects", comment: "Mac Video Projects: the search field"))
        .task { await model.load() }
        .background {
            // Return opens the selected project.
            // Not while typing a search: its Return and ⌫ are the field's.
            Group {
                Button("") {
                    guard !(NSApp.keyWindow?.firstResponder is NSTextView), let card = selectedCard else { return }
                    open(card)
                }
                .keyboardShortcut(.defaultAction)
                Button("") {
                    guard !(NSApp.keyWindow?.firstResponder is NSTextView), let card = selectedCard else { return }
                    removing = card
                }
                .keyboardShortcut(.delete, modifiers: [])
            }
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .alert(removeTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(String(localized: "Cancel", comment: "Mac Video Projects"), role: .cancel) { removing = nil }
            Button(removing?.isDraft == false
                   ? String(localized: "Remove", comment: "Mac Video Projects: confirm removing an exported project")
                   : String(localized: "Delete Draft", comment: "Mac Video Projects: confirm deleting a draft"), role: .destructive) {
                if let card = removing {
                    Task {
                        if await model.remove(card) { if selected == card.id { selected = nil } } else { removeFailed = true }
                    }
                }
                removing = nil
            }
        } message: {
            Text(removeMessage)
        }
        .alert(unreadable?.isDraft == false
               ? String(localized: "This project can’t be opened.", comment: "Mac Video Projects: unreadable exported project")
               : String(localized: "This draft can’t be opened.", comment: "Mac Video Projects: unreadable recipe (FS-12.18 §6)"),
               isPresented: Binding(get: { unreadable != nil }, set: { if !$0 { unreadable = nil } })) {
            Button(String(localized: "OK", comment: "Mac Video Projects"), role: .cancel) {}
        } message: {
            Text(unreadable?.isDraft == false
                 ? String(localized: "It stays in Video Projects; remove it if you no longer need it.", comment: "Mac Video Projects: unreadable exported project")
                 : String(localized: "It stays in Video Projects; delete it if you no longer need it.", comment: "Mac Video Projects: unreadable recipe"))
        }
        .alert(String(localized: "The project couldn’t be deleted", comment: "Mac Video Projects: delete failed"), isPresented: $removeFailed) {
            Button(String(localized: "OK", comment: "Mac Video Projects"), role: .cancel) {}
        } message: {
            Text("It is still in Video Projects. Try again.", comment: "Mac Video Projects: delete failed")
        }
        // Video Studio comes to the Mac after this page (MAC_LOOP row 49): say so, never a silent click.
        .alert(String(localized: "Video Studio isn’t on the Mac yet", comment: "Mac Video Projects: open or new"), isPresented: $cannotOpen) {
            Button(String(localized: "OK", comment: "Mac Video Projects"), role: .cancel) {}
        } message: {
            Text("Open and make video projects on iPhone or iPad for now. Their drafts and exports show here.",
                 comment: "Mac Video Projects: where to edit for now")
        }
    }

    /// Only a card on screen: one hidden by the search is not acted on.
    private var selectedCard: MacVideoProjectsModel.Card? { model.shown.first { $0.id == selected } }

    /// "7 projects · 3 drafts".
    private var subtitle: String {
        var parts = [MacInflect.string("^[\(model.cards.count) project](inflect: true)", comment: "Mac Video Projects: how many")]
        if model.draftCount > 0 {
            parts.append(MacInflect.string("^[\(model.draftCount) draft](inflect: true)", comment: "Mac Video Projects: how many drafts"))
        }
        return parts.joined(separator: " · ")
    }

    /// The toolbar's name for what the dialog will do.
    private var deleteTitle: String {
        guard let card = selectedCard else { return String(localized: "Delete", comment: "Mac Video Projects toolbar: nothing selected") }
        return card.isDraft ? String(localized: "Delete Draft…", comment: "Mac Video Projects toolbar")
                            : String(localized: "Remove from Video Projects…", comment: "Mac Video Projects toolbar")
    }

    private var removeTitle: String {
        removing?.isDraft == false
            ? String(localized: "Remove from Video Projects?", comment: "Mac Video Projects: confirm removing an exported project")
            : String(localized: "Delete Draft?", comment: "Mac Video Projects: confirm deleting a draft")
    }

    private var removeMessage: String {
        let name = removing.map(model.dateText) ?? ""
        return removing?.isDraft == false
            ? String(localized: "“\(name)” leaves Video Projects. The exported video and the photos and videos in your library stay.",
                     comment: "Mac Video Projects: what removing an exported project does")
            : String(localized: "“\(name)” will be deleted. The photos and videos stay in your library.",
                     comment: "Mac Video Projects: what deleting a draft does")
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let shown = model.shown
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 279, maximum: 279), spacing: 16, alignment: .topLeading)],
                          alignment: .leading, spacing: 20) {
                    ForEach(shown) { card in cardView(card) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
            }
            .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
        }
    }

    private func cardView(_ card: MacVideoProjectsModel.Card) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 1) {
                // Equal thirds (as many as there are clips, up to three).
                let count = max(1, min(3, card.clipIds.count))
                let width = (279 - CGFloat(count - 1)) / CGFloat(count)
                ForEach(Array(card.clipIds.prefix(3).enumerated()), id: \.offset) { _, id in
                    MacTheme.fill2
                        .frame(width: width, height: 157)
                        .overlay {
                            if let picture = model.pictures[id] {
                                Image(decorative: picture, scale: 1).resizable().scaledToFill()
                            }
                        }
                        .clipped()
                }
                if card.clipIds.isEmpty { MacTheme.fill2 }
            }
            .frame(width: 279, height: 157)
            .clipShape(RoundedRectangle(cornerRadius: MacCollagesMetrics.radius))
            .overlay(alignment: .topLeading) {
                if card.isDraft { badge(String(localized: "Draft", comment: "Mac Video Projects: a project never exported")) }
            }
            .overlay(alignment: .bottomTrailing) {
                if let duration = card.duration { badge(MacVideoProjectsModel.lengthText(duration)).monospacedDigit() }
            }
            .overlay {
                if selected == card.id {
                    RoundedRectangle(cornerRadius: MacCollagesMetrics.radius).strokeBorder(MacTheme.accent, lineWidth: 3)
                }
            }
            .task(id: card.clipIds.prefix(3).joined()) { await model.drawCover(card) }
            .onDisappear { model.forget(card) }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.dateText(card)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(model.detailText(card)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 279, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { selected = card.id; open(card) }
        .simultaneousGesture(TapGesture().onEnded { selected = card.id })
        .contextMenu {
            Button(String(localized: "Open in Video Studio", comment: "Mac Video Projects: menu")) { open(card) }
            Divider()
            Button(card.isDraft ? String(localized: "Delete Draft…", comment: "Mac Video Projects: menu")
                                : String(localized: "Remove from Video Projects…", comment: "Mac Video Projects: menu")) { removing = card }
        }
        .id(card.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Video project, \(model.dateText(card))", comment: "Mac Video Projects: VoiceOver for a card")
                            + (card.isDraft ? ", " + String(localized: "Draft", comment: "Mac Video Projects: a project never exported") : ""))
        .accessibilityValue(model.detailText(card) + (card.duration.map { ", " + MacVideoProjectsModel.lengthText($0) } ?? ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("projects.card.\(model.dateText(card))")
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6).frame(height: 18)
            .background(MacTheme.hudFill, in: RoundedRectangle(cornerRadius: 9))
            .padding(8)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker(selection: $model.order) {
                    ForEach(MacCollagesModel.Order.allCases) { Text($0.title).tag($0) }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                Label(model.order.title, systemImage: "list.bullet").labelStyle(.titleAndIcon)
            }
            .help(String(localized: "Sort projects", comment: "Mac Video Projects toolbar"))
            .accessibilityIdentifier("projects.order")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { cannotOpen = true } label: {
                Label(String(localized: "New Video Project", comment: "Mac Video Projects toolbar"), systemImage: "plus")
            }
            .help(String(localized: "New Video Project", comment: "Mac Video Projects toolbar"))
            .accessibilityIdentifier("projects.new")
            Button { if let card = selectedCard { removing = card } } label: {
                Label(deleteTitle, systemImage: "trash")
            }
            .disabled(selectedCard == nil)
            .help(deleteTitle + " (⌫)")
            .accessibilityIdentifier("projects.delete")
        }
    }
}
