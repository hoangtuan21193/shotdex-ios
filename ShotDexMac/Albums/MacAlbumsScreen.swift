import Photos
import SwiftUI

/// Collections › Albums (board `MAC_Collections`, FS-18.04 §1): the On This
/// Day card with Recently Viewed and Recently Shared beside it, then Pinned,
/// People and Pets, Smart Albums and My Albums as 135 covers with the name
/// under each. Sort By and Search Albums act on the albums; + makes one.
/// Every count and cover is read off the main actor.
struct MacAlbumsScreen: View {
    let photoMenu: MacPhotoMenu?
    let smartAlbums: [SmartAlbum]
    /// Opens a place: a sidebar row, or an album by id with its name.
    let open: (MacSidebarItem, String?) -> Void
    @Environment(MacDependencies.self) private var dependencies
    @State private var model = MacAlbumsModel()
    @AppStorage("macAlbumsSort") private var sort = MacAlbumsSort.custom
    @State private var search = ""
    @State private var renaming: AlbumSummary?
    @State private var newName = ""
    @State private var deleting: AlbumSummary?
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if search.isEmpty { hero }
                // Built once a render: sorting and filtering 300 albums is not free.
                let albums = albumTiles, smart = smartTiles
                let pinned = pinnedTiles(albums: albums, smart: smart), subjects = subjectTiles.filter { matches($0.title) }
                // Pinned and People and Pets share a row, as the board has them.
                if !pinned.isEmpty || !subjects.isEmpty {
                    HStack(alignment: .top, spacing: 24) {
                        if !pinned.isEmpty { section(String(localized: "Pinned", comment: "Mac Albums: pinned section"), count: nil, tiles: pinned) }
                        if !subjects.isEmpty {
                            section(String(localized: "People and Pets", comment: "Mac Albums: section"), count: nil, tiles: subjects)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }
                if !smart.isEmpty {
                    section(String(localized: "Smart Albums", comment: "Mac Albums: section"), count: search.isEmpty ? smartAlbums.count : smart.count, tiles: smart)
                }
                if !albums.isEmpty {
                    section(String(localized: "My Albums", comment: "Mac Albums: section"), count: search.isEmpty ? model.albums.count : albums.count, tiles: albums)
                } else if model.isLoaded, search.isEmpty, model.albums.isEmpty {
                    Text("Albums you make in Photos or with + appear here.", comment: "Mac Albums: no album yet")
                        .foregroundStyle(.secondary)
                }
                if !search.isEmpty, pinned.isEmpty, subjects.isEmpty, smart.isEmpty, albums.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(String(localized: "Albums", comment: "Mac Albums: window title"))
        .navigationSubtitle(subtitle)
        .searchable(text: $search, placement: .toolbar, prompt: Text("Search Albums", comment: "Mac Albums: search field"))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { } label: { Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left") }
                    .disabled(true)
                Button { } label: { Label(String(localized: "Forward", comment: "Mac toolbar"), systemImage: "chevron.right") }
                    .disabled(true)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker(String(localized: "Sort By", comment: "Mac Albums: sort menu"), selection: $sort) {
                        ForEach(MacAlbumsSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Label(sort.title, systemImage: "arrow.up.arrow.down").labelStyle(.titleAndIcon)
                }
                .fixedSize()
                .accessibilityLabel(String(localized: "Sort By", comment: "Mac Albums: sort menu"))
                .help(String(localized: "Sort My Albums", comment: "Mac Albums: sort menu tooltip"))
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(String(localized: "New Album…", comment: "Mac Albums: + menu")) { photoMenu?.requestAlbum(for: []) }
                        .disabled(photoMenu?.canAddToAlbums != true)
                        .help(photoMenu?.canAddToAlbums == true ? ""
                              : String(localized: "Allow full Photos access in System Settings › Privacy & Security › Photos to make albums.",
                                       comment: "Mac Albums: why New Album is off"))
                    Button(String(localized: "New Smart Album…", comment: "Mac Albums: + menu")) {
                        NotificationCenter.default.post(name: .macNewSmartAlbum, object: nil)
                    }
                } label: {
                    // The view's one prominent command (board `MAC_Collections`): an amber pill.
                    HStack(spacing: 3) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(MacTheme.onAccentFill)
                    .frame(width: MacAlbumsMetrics.plusSize.width, height: MacAlbumsMetrics.plusSize.height)
                    .background(MacTheme.accentFill, in: Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(String(localized: "New", comment: "Mac Albums: + menu"))
                .help(String(localized: "New Album or Smart Album", comment: "Mac Albums: + tooltip"))
            }
        }
        .task(id: "\(dependencies.photoLibrary.collectionChangeToken)-\(dependencies.photoLibrary.assetChangeToken)") {
            // A sync or an index run bumps the tokens in bursts: read once it settles.
            if model.isLoaded { try? await Task.sleep(for: .seconds(1)) }
            guard !Task.isCancelled else { return }
            await model.loadAlbums()
        }
        .task(id: "\(dependencies.photoLibrary.assetChangeToken)-\(smartAlbums.map { "\($0.id)\($0.query)" })") {
            if model.isLoaded { try? await Task.sleep(for: .seconds(1)) }
            guard !Task.isCancelled else { return }
            await model.loadRest(dependencies: dependencies, smartAlbums: smartAlbums)
        }
        .alert(String(localized: "Rename Album", comment: "Mac Albums: rename, title"),
               isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { album in
            TextField(String(localized: "Album Name", comment: "Mac Albums: rename field"), text: $newName)
            Button(String(localized: "Cancel", comment: "Mac Albums: rename, dismiss"), role: .cancel) {}
            Button(String(localized: "Rename", comment: "Mac Albums: rename, confirm")) { rename(album, to: newName) }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: { _ in
            Text("The album is renamed in Photos.", comment: "Mac Albums: rename, where")
        }
        .confirmationDialog(String(localized: "Delete “\(deleting?.title ?? "")”?", comment: "Mac Albums: delete album, title"),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { album in
            Button(String(localized: "Delete Album", comment: "Mac Albums: delete album, confirm"), role: .destructive) { delete(album) }
            Button(String(localized: "Cancel", comment: "Mac Albums: delete album, dismiss"), role: .cancel) {}
        } message: { _ in
            Text("The album goes from Photos on all your devices; its photos stay in the library.", comment: "Mac Albums: delete album, what happens")
        }
        .alert(String(localized: "Couldn’t Change the Album", comment: "Mac Albums: rename or delete failed"),
               isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(String(localized: "OK", comment: "Mac Albums: dismiss"), role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private var subtitle: String {
        let albums = String(AttributedString(localized: "^[\(model.albums.count) album](inflect: true)", comment: "Mac Albums subtitle: albums").characters)
        let smart = String(AttributedString(localized: "^[\(smartAlbums.count) smart album](inflect: true)", comment: "Mac Albums subtitle: smart albums").characters)
        return albums + " · " + smart
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { open(.onThisDay, nil) } label: {
                ZStack(alignment: .bottomLeading) {
                    MacAssetCover(assetId: model.onThisDay.cover, side: 600)
                        .frame(maxWidth: .infinity)
                        .frame(height: MacAlbumsMetrics.heroHeight)
                        .clipped()
                    LinearGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .clear, location: 0.7)],
                                   startPoint: .leading, endPoint: .trailing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("On This Day", comment: "Mac Albums: hero card label").font(.system(size: 11, weight: .semibold))
                        Text(Date().formatted(.dateTime.month(.wide).day())).font(.system(size: 22, weight: .bold))
                        Text(onThisDayLine).font(.system(size: 12))
                    }
                    .foregroundStyle(.white)
                    .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Open On This Day", comment: "Mac Albums: hero card, VoiceOver"))
            .accessibilityValue(onThisDayLine)
            if !model.recentlyViewed.isEmpty || !model.recentlyShared.isEmpty {
                VStack(spacing: 8) {
                    if !model.recentlyViewed.isEmpty {
                        recentStrip(String(localized: "Recently Viewed", comment: "Mac Albums: recents"), ids: model.recentlyViewed)
                    }
                    if !model.recentlyShared.isEmpty {
                        recentStrip(String(localized: "Recently Shared", comment: "Mac Albums: recents"), ids: model.recentlyShared)
                    }
                }
                .frame(width: MacAlbumsMetrics.recentsWidth)
            }
        }
    }

    private var onThisDayLine: String {
        guard model.onThisDay.count > 0 else {
            return String(localized: "Nothing from earlier years today", comment: "Mac Albums: On This Day card, empty")
        }
        return String(AttributedString(localized: "^[\(model.onThisDay.count) photo](inflect: true) from ^[\(model.onThisDay.years) year](inflect: true)",
                                       comment: "Mac Albums: On This Day card, 26 photos from 3 years").characters)
    }

    private func recentStrip(_ title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).frame(height: 16)
            HStack(spacing: 8) {
                // Pictures only, until the viewer gives them somewhere to open.
                ForEach(ids.prefix(4), id: \.self) { id in
                    MacAssetCover(assetId: id, side: 88)
                        .frame(width: MacAlbumsMetrics.recentThumb.width, height: MacAlbumsMetrics.recentThumb.height)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(height: MacAlbumsMetrics.recentsHeight)
        .background(MacTheme.card, in: RoundedRectangle(cornerRadius: MacAlbumsMetrics.radius))
        .accessibilityElement(children: .combine)
        .help(title)
    }

    // MARK: Sections

    private struct Tile: Identifiable {
        let id: String
        let title: String
        let cover: String?
        let symbol: String?
        let target: CollectionPinStore.Target?
        var isSmart = false
        /// Photos in it, when known.
        var count: Int?
        /// One of Photos' albums: it can be renamed and deleted.
        var album: AlbumSummary?
        let open: () -> Void
    }

    private func matches(_ title: String) -> Bool {
        search.isEmpty || title.localizedCaseInsensitiveContains(search)
    }

    private var albumTiles: [Tile] {
        model.sorted(sort).filter { matches($0.title) }.map { album in
            Tile(id: "album-" + album.id, title: album.title, cover: album.coverAssetId, symbol: nil, target: .album(album.id),
                 count: album.count, album: album, open: { open(.album(album.id), album.title) })
        }
    }

    private var smartTiles: [Tile] {
        smartAlbums.filter { matches($0.name) }.map { album in
            Tile(id: "smart-" + album.id, title: album.name, cover: model.smartCovers[album.id], symbol: nil, target: .smartAlbum(album.id),
                 isSmart: true, open: { open(.smartAlbum(album.id), nil) })
        }
    }

    private var subjectTiles: [Tile] {
        var tiles: [Tile] = []
        if let people = model.people {
            tiles.append(Tile(id: "people", title: MacSidebarItem.people.title, cover: people, symbol: nil, target: nil, open: { open(.people, nil) }))
        }
        if let pets = model.pets {
            tiles.append(Tile(id: "pets", title: MacSidebarItem.pets.title, cover: pets, symbol: nil, target: nil, open: { open(.pets, nil) }))
        }
        return tiles
    }

    private func pinnedTiles(albums: [Tile], smart: [Tile]) -> [Tile] {
        let byTarget = Dictionary((albums + smart).compactMap { tile in tile.target.map { ($0, tile) } }, uniquingKeysWith: { first, _ in first })
        return model.pins.pinned.compactMap { target -> Tile? in
            switch target {
            case .album, .smartAlbum: byTarget[target]
            case .duplicates:
                matches(MacSidebarItem.duplicates.title)
                    ? Tile(id: "duplicates", title: MacSidebarItem.duplicates.title, cover: nil, symbol: "square.on.square", target: target,
                           open: { open(.duplicates, nil) })
                    : nil
            }
        }
    }

    private func section(_ title: String, count: Int?, tiles: [Tile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 15, weight: .semibold))
                if let count { Text(count.formatted()).font(.system(size: 13)).foregroundStyle(.secondary).monospacedDigit() }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: MacAlbumsMetrics.cover, maximum: MacAlbumsMetrics.cover), spacing: 12, alignment: .top)],
                      alignment: .leading, spacing: 16) {
                ForEach(tiles) { tile($0) }
            }
        }
    }

    private func tile(_ tile: Tile) -> some View {
        Button(action: tile.open) {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if let symbol = tile.symbol {
                        ZStack {
                            RoundedRectangle(cornerRadius: MacAlbumsMetrics.radius).fill(MacTheme.fill2)
                            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(MacTheme.accent)
                        }
                        .overlay(RoundedRectangle(cornerRadius: MacAlbumsMetrics.radius).strokeBorder(MacTheme.separator))
                    } else {
                        MacAssetCover(assetId: tile.cover, side: MacAlbumsMetrics.cover * 2)
                            .clipShape(RoundedRectangle(cornerRadius: MacAlbumsMetrics.radius))
                            .overlay {
                                // Read, and nothing in it: say so, not a cover that never loads.
                                if tile.cover == nil, model.isLoaded {
                                    Text("No photos", comment: "Mac Albums: an empty album's cover").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                    }
                }
                .frame(width: MacAlbumsMetrics.cover, height: MacAlbumsMetrics.cover)
                .overlay(alignment: .topLeading) {
                    if let target = tile.target, model.pins.isPinned(target) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    // A smart album's mark (board): a gear in a dark disc.
                    if tile.isSmart {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(8)
                            .accessibilityHidden(true)
                    }
                }
                Text(tile.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .frame(width: MacAlbumsMetrics.cover, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.title)
        .accessibilityValue(accessibilityValue(tile))
        .accessibilityActions {
            if let target = tile.target {
                Button(model.pins.isPinned(target) ? String(localized: "Unpin", comment: "Mac Albums: tile menu")
                                                   : String(localized: "Pin", comment: "Mac Albums: tile menu")) {
                    model.pins.toggle(target)
                }
            }
        }
        .contextMenu {
            Button(String(localized: "Open", comment: "Mac Albums: tile menu"), action: tile.open)
            if let target = tile.target {
                Button(model.pins.isPinned(target) ? String(localized: "Unpin", comment: "Mac Albums: tile menu")
                                                   : String(localized: "Pin", comment: "Mac Albums: tile menu")) {
                    model.pins.toggle(target)
                }
            }
            if let album = tile.album {
                Divider()
                Button(String(localized: "Rename Album…", comment: "Mac Albums: tile menu")) {
                    newName = album.title
                    renaming = album
                }
                Button(String(localized: "Delete Album…", comment: "Mac Albums: tile menu"), role: .destructive) { deleting = album }
            }
            if tile.isSmart, case .smartAlbum(let id) = tile.target {
                Divider()
                // Edit, Rename, Duplicate, Delete (FS-06.08 §3c-Mac, AC-37).
                MacSmartAlbumActions(albumId: id)
            }
        }
    }

    /// "48 photos", "smart album", "pinned" — what the cover says to the eye.
    private func accessibilityValue(_ tile: Tile) -> String {
        var parts: [String] = []
        if tile.isSmart { parts.append(String(localized: "smart album", comment: "Mac Albums: VoiceOver, a smart album")) }
        if let count = tile.count {
            parts.append(String(AttributedString(localized: "^[\(count) photo](inflect: true)", comment: "Mac Albums: VoiceOver, how many").characters))
        }
        if let target = tile.target, model.pins.isPinned(target) {
            parts.append(String(localized: "pinned", comment: "Mac Albums: VoiceOver, a pinned album"))
        }
        return parts.joined(separator: ", ")
    }

    /// After the dialog that asked has gone: an alert presented while another
    /// closes is dropped.
    private func report(_ message: String) async {
        try? await Task.sleep(for: .milliseconds(350))
        failure = message
    }

    private func rename(_ album: AlbumSummary, to name: String) {
        let library = dependencies.photoLibrary
        Task {
            #if DEBUG
            // The demo's albums are names in memory: Photos is never asked.
            if MacDemoLibrary.isOn { await report(String(localized: "The demo library's albums can't be changed.", comment: "Mac Albums: demo")); return }
            #endif
            let id = album.id
            let found = await Task.detached(priority: .userInitiated) {
                MacCollectionBox(PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject)
            }.value
            guard let collection = found.collection else { return }
            do { try await library.renameAlbum(collection, to: name) } catch { await report(error.localizedDescription) }
        }
    }

    private func delete(_ album: AlbumSummary) {
        let library = dependencies.photoLibrary
        Task {
            #if DEBUG
            if MacDemoLibrary.isOn { await report(String(localized: "The demo library's albums can't be changed.", comment: "Mac Albums: demo")); return }
            #endif
            let id = album.id
            let found = await Task.detached(priority: .userInitiated) {
                MacCollectionBox(PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [id], options: nil).firstObject)
            }.value
            guard let collection = found.collection else { return }
            do { try await library.deleteAlbums([collection]) } catch { await report(error.localizedDescription) }
        }
    }
}

/// The board's numbers (`MAC_Collections`).
enum MacAlbumsMetrics {
    static let cover: CGFloat = 135
    static let radius: CGFloat = 12
    static let heroHeight: CGFloat = 150
    /// Recently Viewed and Recently Shared: two 71 cards beside the hero.
    static let recentsWidth: CGFloat = 240
    static let recentsHeight: CGFloat = 71
    static let recentThumb = CGSize(width: 44, height: 40)
    static let plusSize = CGSize(width: 48, height: 36)
}

/// My Albums' order (the toolbar's Sort By).
enum MacAlbumsSort: String, CaseIterable, Identifiable {
    case custom, name, size

    var id: String { rawValue }
    var title: String {
        switch self {
        case .custom: String(localized: "Custom Order", comment: "Mac Albums sort: the order arranged in Photos")
        case .name: String(localized: "Name", comment: "Mac Albums sort")
        case .size: String(localized: "Most Photos", comment: "Mac Albums sort: biggest album first")
        }
    }
}

/// What the Albums screen shows, read off the main actor.
@MainActor
@Observable
final class MacAlbumsModel {
    struct OnThisDay: Equatable { var count = 0; var years = 0; var cover: String? }

    private(set) var albums: [AlbumSummary] = []
    private(set) var smartCovers: [String: String] = [:]
    private(set) var onThisDay = OnThisDay()
    private(set) var people: String?
    private(set) var pets: String?
    private(set) var recentlyViewed: [String] = []
    private(set) var recentlyShared: [String] = []
    private(set) var isLoaded = false
    let pins = CollectionPinStore()

    /// My Albums in an order, sorted once per change rather than every render.
    @ObservationIgnored private var sortedCache: (sort: MacAlbumsSort, albums: [AlbumSummary])?

    func sorted(_ sort: MacAlbumsSort) -> [AlbumSummary] {
        if let cache = sortedCache, cache.sort == sort { return cache.albums }
        let result: [AlbumSummary] = switch sort {
        case .custom: albums
        case .name: albums.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .size: albums.sorted { $0.count > $1.count }
        }
        sortedCache = (sort, result)
        return result
    }

    /// Photos' albums: on album and library changes.
    func loadAlbums() async {
        let albums: [AlbumSummary]
        #if DEBUG
        if MacDemoLibrary.isOn { albums = MacDemoLibrary.albumSummaries() } else { albums = await Self.readAlbums() }
        #else
        albums = await Self.readAlbums()
        #endif
        guard !Task.isCancelled else { return }
        if albums != self.albums {
            self.albums = albums
            sortedCache = nil
        }
        isLoaded = true
    }

    /// On This Day, People and Pets, smart-album covers and the recents:
    /// the index's answers, on photo and smart-album changes.
    func loadRest(dependencies: MacDependencies, smartAlbums: [SmartAlbum]) async {
        let queries = dependencies.libraryQueries
        let calendar = Calendar.current, now = Date()
        let month = calendar.component(.month, from: now), day = calendar.component(.day, from: now)
        let otd = (try? await queries.assetIdsOnThisDay(month: month, day: day)) ?? []
        let people = (try? await queries.assetIdsWithFaces(limit: 1).first) ?? nil
        let pets = (try? await queries.assetIdsWithAnimals(limit: 1).first) ?? nil
        var covers: [String: String] = [:]
        for album in smartAlbums {
            if let first = try? await queries.gridItems(matching: album.query, sort: .dateTakenNewest, limit: 1).first {
                covers[album.id] = first.assetId
            }
        }
        let years = await Task.detached(priority: .utility) { () -> Int in
            let rows = (try? await queries.gridItems(matchingAll: [], restrictedTo: otd, sort: .dateTakenNewest)) ?? []
            return Set(rows.compactMap { $0.creationDateValue.map { calendar.component(.year, from: $0) } }).count
        }.value
        guard !Task.isCancelled else { return }
        smartCovers = covers
        onThisDay = OnThisDay(count: otd.count, years: years, cover: otd.first)
        self.people = people
        self.pets = pets
        recentlyViewed = dependencies.recentActivity.viewed
        recentlyShared = dependencies.recentActivity.shared
    }

    private static func readAlbums() async -> [AlbumSummary] {
        // Limited access lists the albums too (with the photos it may read).
        guard [.authorized, .limited].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite)) else { return [] }
        return await Task.detached(priority: .userInitiated) { PhotoLibraryService.fetchUserAlbumSummaries(includesEmpty: true) }.value
    }
}

/// A photo as a square cover, by id: the demo's picture, or Photos'
/// thumbnail fetched off the main actor. A grey ground until it arrives.
struct MacAssetCover: View {
    let assetId: String?
    /// Pixels to ask for (points × 2).
    let side: CGFloat
    @Environment(MacDependencies.self) private var dependencies
    @State private var image: CGImage?
    @State private var request: PHImageRequestID?

    var body: some View {
        ZStack {
            MacTheme.fill2
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            }
        }
        .task(id: assetId) {
            if let request { dependencies.photoLibrary.cancelThumbnailRequest(request) }
            request = nil
            image = nil
            guard let assetId else { return }
            if let picture = MacRootWindow.demoPicture?(assetId) { image = picture; return }
            let found = await Task.detached(priority: .utility) { MacAssetMap(PhotoLibraryService.fetchAssets(ids: [assetId])) }.value
            guard let asset = found.byId[assetId], !Task.isCancelled else { return }
            let library = dependencies.photoLibrary
            // Each delivery replaces the last: a quick degraded one, then the sharp one.
            // Local renditions only: a screenful of covers must not queue behind
            // the network gate (four at a time) and stay grey.
            request = library.requestThumbnail(for: asset, targetSize: CGSize(width: side, height: side), allowNetwork: false) { picture, _ in
                if let picture = picture?.cgImage(forProposedRect: nil, context: nil, hints: nil) { image = picture }
            }
        }
        .onDisappear {
            if let request { dependencies.photoLibrary.cancelThumbnailRequest(request) }
            request = nil
        }
    }
}

/// A fetched album handed back from a detached fetch (`PHAssetCollection` is
/// immutable once fetched).
struct MacCollectionBox: @unchecked Sendable {
    let collection: PHAssetCollection?
    init(_ collection: PHAssetCollection?) { self.collection = collection }
}

extension Notification.Name {
    /// Edit Smart Album… from Albums: the window opens its form, the album's id as the object.
    static let macEditSmartAlbum = Notification.Name("macEditSmartAlbum")
}
