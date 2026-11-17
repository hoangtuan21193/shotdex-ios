import AppKit
import GRDB
import ShotDexKit
import SwiftUI

/// Utilities › Collages (board `MAC_Creations`, FS-18.04 §1.5): every
/// exported collage, newest first, in month sections; a card is the collage
/// itself drawn from its photos' thumbnails. Open in Collage, Show in
/// Library, Export…, Share…, Remove from Collages….
@MainActor
@Observable
final class MacCollagesModel {
    enum Order: String, CaseIterable, Identifiable {
        case lastEdited, dateCreated
        var id: String { rawValue }
        var title: String {
            switch self {
            case .lastEdited: String(localized: "Last Edited", comment: "Mac Collages: sort by when last exported")
            case .dateCreated: String(localized: "Date Created", comment: "Mac Collages: sort by when first made")
            }
        }
    }

    struct Card: Identifiable, Equatable {
        let creation: Creation
        let recipe: CollageRecipe
        var id: String { creation.id }
        var date: Date { Date(timeIntervalSince1970: TimeInterval(creation.updatedAt)) }
        var created: Date { Date(timeIntervalSince1970: TimeInterval(creation.createdAt)) }
        var photoIds: [String] { recipe.cells.compactMap(\.assetID) }
    }

    struct Section: Identifiable {
        let id: String
        let title: String
        let cards: [Card]
    }

    private(set) var cards: [Card] = []
    private(set) var isLoading = true
    /// The collages could not be read: said, never shown as "No Collages".
    private(set) var loadFailed = false
    // Read in the declaration, not assigned in `init`: an observable write
    // while the window's body builds this model re-runs that body forever.
    var order: Order = UserDefaults.standard.string(forKey: "mac.collages.order").flatMap(Order.init) ?? .lastEdited {
        didSet { UserDefaults.standard.set(order.rawValue, forKey: "mac.collages.order") }
    }
    var search = ""
    /// File names of the collages' photos, for search.
    private var names: [String: String] = [:]
    /// Rendered cards by id (and the recipe they were drawn from).
    private(set) var pictures: [String: CGImage] = [:]
    private var drawn: [String: CollageRecipe] = [:]
    private let dependencies: MacDependencies

    init(dependencies: MacDependencies) {
        self.dependencies = dependencies
    }

    var store: CreationStore { CreationStore(database: dependencies.database) }

    /// Reads the collages and their photos' names off the main actor.
    func load() async {
        let store = store
        let database = dependencies.database
        let read = await Task.detached(priority: .userInitiated) { () -> ([Card], [String: String])? in
            guard let rows = try? store.fetchOrdered(kind: .collage) else { return nil }
            let cards = rows.compactMap { creation in
                creation.collageRecipe.map { Card(creation: creation, recipe: $0) }
            }
            let ids = Array(Set(cards.flatMap(\.photoIds)))
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

    /// Month sections in the chosen order, filtered by the search.
    var sections: [Section] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let sorted = cards.sorted { order == .lastEdited ? $0.date > $1.date : $0.created > $1.created }
        let shown = query.isEmpty ? sorted : sorted.filter { card in
            dateText(card).lowercased().contains(query)
                || Self.detailText(card).lowercased().contains(query)
                || card.photoIds.contains { names[$0]?.lowercased().contains(query) == true }
        }
        var sections: [Section] = []
        let calendar = Calendar.current
        for card in shown {
            let date = order == .lastEdited ? card.date : card.created
            let key = calendar.dateComponents([.year, .month], from: date)
            let id = "\(key.year ?? 0)-\(key.month ?? 0)"
            if sections.last?.id == id {
                sections[sections.count - 1] = Section(id: id, title: sections[sections.count - 1].title, cards: sections[sections.count - 1].cards + [card])
            } else {
                sections.append(Section(id: id, title: date.formatted(.dateTime.month(.wide).year()), cards: [card]))
            }
        }
        return sections
    }

    /// "Oct 3, 2026 at 11:20 AM": the date the page is sorted by, so a card
    /// sits under the month its own date says.
    func dateText(_ card: Card) -> String {
        (order == .lastEdited ? card.date : card.created).formatted(date: .abbreviated, time: .shortened)
    }

    /// "4 photos · 1:1".
    static func detailText(_ card: Card) -> String {
        [MacInflect.string("^[\(card.photoIds.count) photo](inflect: true)", comment: "Mac Collages: photos in a collage"),
         card.recipe.aspectPreset?.displayName ?? String(localized: "Custom", comment: "Collage aspect ratio that matches no preset")]
            .joined(separator: " · ")
    }

    /// Draws a card from its photos' thumbnails, off the main actor; again
    /// only when its recipe changed.
    func draw(_ card: Card) async {
        guard drawn[card.id] != card.recipe, let template = CollageTemplateCatalog.template(id: card.recipe.templateID) else { return }
        var thumbnails: [Int: CGImage] = [:]
        for (index, cell) in card.recipe.cells.enumerated() {
            guard let id = cell.assetID else { continue }
            if let image = await thumbnail(id) { thumbnails[index] = image }
            guard !Task.isCancelled else { return }
        }
        let recipe = card.recipe
        let box = MacCollagePictures(images: thumbnails)
        guard !Task.isCancelled else { return }
        // The card's own size at 2× (147 pt tall), not more.
        let size = CollageGeometry.outputSize(ratio: recipe.aspectRatio, longEdge: 440)
        let picture = await Task.detached(priority: .utility) {
            MacCollageImageBox(image: CollageCompositor.render(recipe: recipe, template: template, images: box.images, pixelSize: size))
        }.value.image
        guard !Task.isCancelled else { return }
        pictures[card.id] = picture
        drawn[card.id] = recipe
    }

    /// A card scrolled away gives its picture back; it is drawn again when it returns.
    func forget(_ card: Card) {
        pictures[card.id] = nil
        drawn[card.id] = nil
    }

    private func thumbnail(_ id: String) async -> CGImage? {
        #if DEBUG
        if MacDemoLibrary.isOn { return MacDemoLibrary.picture(for: id) }
        #endif
        return await MacViewerThumbnail.load(id, side: 160, dependencies: dependencies)
    }

    /// Remove from Collages: the record only; the exported picture stays.
    /// False when the record could not be deleted (the card stays).
    func remove(_ card: Card) async -> Bool {
        let store = store
        let id = card.id
        let removed = await Task.detached(priority: .userInitiated) { (try? store.delete(id: id)) != nil }.value
        guard removed else { return false }
        cards.removeAll { $0.id == id }
        onChange?()
        pictures[id] = nil
        drawn[id] = nil
        return true
    }

    /// Told when the list of collages changed (the sidebar's count).
    var onChange: (() -> Void)?

    /// The collage's photos as editor origins: files here or Photos pictures
    /// (in the demo, its pictures as files). Nil when fewer than one is here.
    func origins(for card: Card) async -> (photos: [PhotoEditOrigin], names: [String: String])? {
        let ids = card.photoIds
        #if DEBUG
        if MacDemoLibrary.isOn {
            let urls = await Task.detached(priority: .userInitiated) { MacDemoLibrary.pictureFiles(for: ids) }.value
            let photos = zip(ids, urls).map { PhotoEditOrigin.fileCopy(FileCopyPhoto(photoId: $0.0, url: $0.1)) }
            return (photos, Dictionary(ids.map { ($0, names[$0] ?? $0) }, uniquingKeysWith: { first, _ in first }))
        }
        #endif
        let found = await MacPhotoOrigins.resolve(ids: ids, limit: 30, dependencies: dependencies)
        guard !found.photos.isEmpty else { return nil }
        return (found.photos.map(\.origin), Dictionary(found.photos.map { ($0.origin.id, $0.name) }, uniquingKeysWith: { first, _ in first }))
    }
}

/// The board's card grid (`MAC_Creations`).
enum MacCollagesMetrics {
    static let card = CGSize(width: 220, height: 147)
    static let radius: CGFloat = 12
    static let columnGap: CGFloat = 16
    static let rowGap: CGFloat = 20
    static let sectionGap: CGFloat = 24
    static let headerGap: CGFloat = 12
}

struct MacCollagesPage: View {
    @State private var model: MacCollagesModel
    /// Open in Collage (and Export…: `exports` true).
    let open: (MacCollagesModel.Card, [PhotoEditOrigin], [String: String], Bool) -> Void
    /// Show in Library: the exported picture when it is in Photos (first
    /// list), else the collage's photos (second).
    let showInLibrary: ([String], [String]) -> Void
    let newCollage: () -> Void
    @State private var removing: MacCollagesModel.Card?
    @State private var cannotOpen = false
    @State private var sharing: String?
    @State private var selected: String?
    @State private var removeFailed = false
    /// An Open or Export under way: a second one waits for it.
    @State private var openTask: Task<Void, Never>?
    @State private var opening: String?
    @State private var shareFailed = false

    init(dependencies: MacDependencies,
         open: @escaping (MacCollagesModel.Card, [PhotoEditOrigin], [String: String], Bool) -> Void,
         showInLibrary: @escaping ([String], [String]) -> Void, newCollage: @escaping () -> Void, changed: @escaping () -> Void,
         focus: String? = nil) {
        _selected = State(initialValue: focus)
        let model = MacCollagesModel(dependencies: dependencies)
        model.onChange = changed
        _model = State(initialValue: model)
        self.open = open
        self.showInLibrary = showInLibrary
        self.newCollage = newCollage
    }

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.loadFailed {
                ContentUnavailableView {
                    Label(String(localized: "Collages Couldn’t Be Read", comment: "Mac Collages: load failed"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text("Collages couldn’t be read from the library. Try again.", comment: "Mac Collages: load failed")
                } actions: {
                    Button(String(localized: "Try Again", comment: "Mac Collages")) { Task { await model.load() } }
                }
            } else if model.cards.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Collages", comment: "Mac Collages: empty"), systemImage: "square.grid.2x2")
                } description: {
                    Text("Select 2 to 9 photos and choose Image › Create › Collage…. Each collage you export is kept here to open again.",
                         comment: "Mac Collages: how to make one")
                }
            } else if model.sections.isEmpty {
                ContentUnavailableView.search(text: model.search)
            } else {
                grid
            }
        }
        // Return opens the selected collage.
        .background {
            Button("") {
                if let id = selected, let card = model.cards.first(where: { $0.id == id }) { openCard(card, exports: false) }
            }
            .keyboardShortcut(.defaultAction)
            .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        // The app's own look, said outright: the Collage page it comes back
        // from asks the window for dark, and that would otherwise linger here
        // (white text on the light ground).
        .preferredColorScheme(NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        .navigationTitle(String(localized: "Collages", comment: "Mac Collages: the page title"))
        .navigationSubtitle(MacInflect.string("^[\(model.cards.count) collage](inflect: true)", comment: "Mac Collages: how many"))
        .toolbar { toolbar }
        .searchable(text: $model.search, placement: .toolbar, prompt: Text("Search Collages", comment: "Mac Collages: the search field"))
        .task { await model.load() }
        .alert(String(localized: "Remove “\(removing.map(model.dateText) ?? "")” from Collages?", comment: "Mac Collages: confirm removing"),
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button(String(localized: "Remove", comment: "Mac Collages: confirm"), role: .destructive) {
                if let card = removing {
                    Task {
                        if await model.remove(card) { if selected == card.id { selected = nil } } else { removeFailed = true }
                    }
                }
                removing = nil
            }
            Button(String(localized: "Cancel", comment: "Mac Collages"), role: .cancel) { removing = nil }
        } message: {
            Text("The exported picture stays where it is. The way back into the collage goes, and this can’t be undone.", comment: "Mac Collages: what removing does")
        }
        .alert(String(localized: "The collage couldn’t be removed", comment: "Mac Collages: remove failed"), isPresented: $removeFailed) {
            Button(String(localized: "OK", comment: "Mac Collages")) {}
        } message: {
            Text("It is still in Collages. Try again.", comment: "Mac Collages: remove failed")
        }
        .onDisappear { openTask?.cancel() }
        .alert(String(localized: "The collage couldn’t be shared", comment: "Mac Collages: share failed"), isPresented: $shareFailed) {
            Button(String(localized: "OK", comment: "Mac Collages")) {}
        } message: {
            Text("Its photos couldn’t be read. Open it in Collage to see which.", comment: "Mac Collages: share failed")
        }
        // Delete asks to remove the selected collage.
        .onDeleteCommand {
            if let id = selected, let card = model.cards.first(where: { $0.id == id }) { removing = card }
        }
        .alert(String(localized: "This collage’s photos aren’t here", comment: "Mac Collages: open failed"), isPresented: $cannotOpen) {
            Button(String(localized: "OK", comment: "Mac Collages")) {}
        } message: {
            Text("Its photos were deleted, or their originals aren’t on this Mac or in Photos any more.", comment: "Mac Collages: why it can't open")
        }
    }

    private var grid: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: MacCollagesMetrics.sectionGap) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: MacCollagesMetrics.headerGap) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.title).font(.system(size: 15, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            Text(MacInflect.string("^[\(section.cards.count) collage](inflect: true)", comment: "Mac Collages: per month"))
                                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: MacCollagesMetrics.card.width, maximum: MacCollagesMetrics.card.width),
                                                     spacing: MacCollagesMetrics.columnGap, alignment: .topLeading)],
                                  alignment: .leading, spacing: MacCollagesMetrics.rowGap) {
                            ForEach(section.cards) { card in cardView(card) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        // Back from a collage: on its card, ringed.
        .onAppear { if let selected { proxy.scrollTo(selected, anchor: .center) } }
        }
    }

    private func cardView(_ card: MacCollagesModel.Card) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                MacTheme.fill2
                if let picture = model.pictures[card.id] {
                    Image(decorative: picture, scale: 1).resizable().scaledToFit()
                }
            }
            .frame(width: MacCollagesMetrics.card.width, height: MacCollagesMetrics.card.height)
            .clipShape(RoundedRectangle(cornerRadius: MacCollagesMetrics.radius))
            .overlay {
                if opening == card.id || sharing == card.id { ProgressView().controlSize(.small) }
            }
            .overlay {
                // Selection is the ring only (board: 3 pt accent).
                if selected == card.id {
                    RoundedRectangle(cornerRadius: MacCollagesMetrics.radius).strokeBorder(MacTheme.accent, lineWidth: 3)
                }
            }
            .task(id: card.recipe.templateID + String(card.creation.updatedAt)) { await model.draw(card) }
            .onDisappear { model.forget(card) }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.dateText(card)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(MacCollagesModel.detailText(card)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .frame(width: MacCollagesMetrics.card.width, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { openCard(card, exports: false) }
        // At once, not after the double-click wait.
        .simultaneousGesture(TapGesture().onEnded { selected = card.id })
        .contextMenu {
            // The menu's card is the selected one (its ring shows which).
            let _ = DispatchQueue.main.async { selected = card.id }
            Button(String(localized: "Open in Collage", comment: "Mac Collages: menu")) { openCard(card, exports: false) }
            Button(String(localized: "Show in Library", comment: "Mac Collages: menu")) {
                selected = card.id
                showInLibrary(card.creation.assetId.map { [$0] } ?? [], card.photoIds)
            }
            Divider()
            Button(String(localized: "Export…", comment: "Mac Collages: menu")) { openCard(card, exports: true) }
            Button(String(localized: "Share…", comment: "Mac Collages: menu")) { share(card) }
                .disabled(sharing != nil)
            Divider()
            Button(String(localized: "Remove from Collages…", comment: "Mac Collages: menu")) { removing = card }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Collage, \(model.dateText(card))", comment: "Mac Collages: VoiceOver for a card"))
        .accessibilityValue(MacCollagesModel.detailText(card))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: String(localized: "Open in Collage", comment: "Mac Collages: menu")) { openCard(card, exports: false) }
        .accessibilityIdentifier("collages.card.\(model.dateText(card))")
    }

    private func openCard(_ card: MacCollagesModel.Card, exports: Bool) {
        guard openTask == nil else { return }
        opening = card.id
        openTask = Task {
            defer { openTask = nil; opening = nil }
            let found = await model.origins(for: card)
            // Left the page meanwhile: nothing opens elsewhere.
            guard !Task.isCancelled else { return }
            guard let found else { cannotOpen = true; return }
            open(card, found.photos, found.names, exports)
        }
    }


    /// Share…: the collage drawn at 2048 px into a temporary file, then the
    /// system's share menu at the pointer.
    private func share(_ card: MacCollagesModel.Card) {
        sharing = card.id
        Task {
            defer { sharing = nil }
            guard let found = await model.origins(for: card) else { cannotOpen = true; return }
            let collage = MacCollageModel(photos: found.photos, names: found.names, placed: found.photos.count,
                                          photoLibrary: model.dependenciesPhotoLibrary, presetStore: CollagePresetStore(),
                                          restoring: card.creation)
            collage.longEdge = 2048
            guard let url = await collage.renderTemporaryFile() else { shareFailed = true; return }
            // The app's window even when another app is in front.
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible),
                  let view = window.contentView else { shareFailed = true; return }
            let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
            NSSharingServicePicker(items: [url]).show(relativeTo: NSRect(origin: point, size: CGSize(width: 1, height: 1)), of: view, preferredEdge: .minY)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            // The board's pill: the order's name, not just an icon.
            Menu {
                Picker(selection: $model.order) {
                    ForEach(MacCollagesModel.Order.allCases) { Text($0.title).tag($0) }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                Label(model.order.title, systemImage: "list.bullet").labelStyle(.titleAndIcon)
            }
            .help(String(localized: "Sort collages", comment: "Mac Collages toolbar"))
            .accessibilityIdentifier("collages.order")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(action: newCollage) {
                Label(String(localized: "New Collage", comment: "Mac Collages toolbar"), systemImage: "plus")
            }
            .help(String(localized: "New Collage from photos you select", comment: "Mac Collages toolbar"))
            .accessibilityIdentifier("collages.new")
        }
    }
}

extension MacCollagesModel {
    var dependenciesPhotoLibrary: PhotoLibraryService { dependencies.photoLibrary }
}

