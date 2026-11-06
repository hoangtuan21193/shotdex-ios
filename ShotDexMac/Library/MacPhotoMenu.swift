import AppKit
import GRDB
import Photos
import Quartz

/// The right-click menu on photos (board `MAC_ContextMenu`, FS-18.01b §4),
/// for the grid and the list alike: no shortcut column, rows that cannot
/// apply are left out. Built from one small read of where the photos live
/// (Photos, a folder, a server) and acts on the ids it was opened for.
///
/// Open, Edit, Get Info and Export come with their own screens (the viewer,
/// the editor, the inspector, the export sheet) and are not on it yet.
@MainActor
@Observable
final class MacPhotoMenu: NSObject {
    @ObservationIgnored private let dependencies: MacDependencies
    /// Move to Trash asked for these: the window runs its delete flow
    /// (`MacPhotoMenuHost`), which shows the prompts.
    var trashRequest: [String]?
    /// New Album… (empty) or New Album with Selection: the window asks for
    /// a name.
    var albumRequest: MacAlbumRequest?
    /// Why an album or favorite change did not happen: the window says it.
    var failure: String?
    /// Bumped when stars, flags or favorites changed: the list reads its
    /// details again.
    private(set) var marksGeneration = 0
    /// Photos whose every copy is on a drive or server not connected.
    @ObservationIgnored var offline: Set<String> = []

    /// Photos' own albums, read off the main actor when the library changes
    /// — never fetched while the menu opens.
    private(set) var albums: [Album] = []
    @ObservationIgnored private var quickLook: MacQuickLook?
    @ObservationIgnored private var quickLookTask: Task<Void, Never>?
    /// Photos access lets the app list and change albums.
    private var canUseAlbums = false

    /// The photos whose marks the last change touched: the list and tiles
    /// read just these again, not the whole library.
    private(set) var changedIds: [String] = []

    private func changed(_ ids: [String]) {
        changedIds = ids
        marksGeneration += 1
    }

    // MARK: For the inspector

    var canAddToAlbums: Bool { canUseAlbums }
    func marksChanged(_ ids: [String]) { changed(ids) }
    func requestAlbum(for ids: [String]) { newAlbum(ids, photosCount: ids.count) }

    func add(ids: [String], toAlbum albumId: String) {
        Task { add(await resolved(Facts(), ids: ids).photosAssetIds, toAlbum: albumId) }
    }

    func setFavorite(_ isFavorite: Bool, ids: [String]) {
        setFavorite(isFavorite, ids: ids, facts: Facts())
    }

    func share(_ ids: [String], with service: NSSharingService) {
        Task {
            let urls = await files(for: ids, facts: await resolved(Facts(), ids: ids))
            guard !urls.isEmpty else {
                failure = String(localized: "These photos couldn't be shared — they may still be downloading from iCloud.", comment: "Mac photo menu: Share found no file")
                return
            }
            service.perform(withItems: urls)
        }
    }
    private func trash(_ ids: [String]) { trashRequest = ids }
    private func newAlbum(_ ids: [String], photosCount: Int) { albumRequest = MacAlbumRequest(ids: ids, photosCount: photosCount) }

    struct Album: Sendable, Equatable {
        let id: String
        let title: String
    }

    /// A selection larger than this is not read as the menu opens (it
    /// would hold the click): its rows are all shown and each action reads
    /// what it needs off the main actor. Quick Look and Share, which write
    /// files for every photo, stop here too.
    static let readLimit = 500

    init(dependencies: MacDependencies) {
        self.dependencies = dependencies
        // Last session's shared files go — once a launch, not per window.
        MacPhotosExport.clearOnce()
        // The share services' sample file, written before the first menu.
        Task.detached(priority: .utility) { _ = Self.shareSample }
    }

    /// `facts` as read for the menu, or read now (off the main actor) for
    /// a selection too large to read as it opened.
    private func resolved(_ facts: Facts, ids: [String]) async -> Facts {
        guard !facts.isKnown else { return facts }
        let database = dependencies.database
        return await Task.detached(priority: .userInitiated) { Facts.read(ids, database: database) }.value
    }

    func loadAlbums() async {
        #if DEBUG
        if MacDemoLibrary.isOn {
            canUseAlbums = true
            albums = ["Kyoto Autumn", "Iceland 2026", "Portfolio", "Dolomites", "Street 2025", "Night Walks"]
                .map { Album(id: "demo-album-\($0)", title: $0) }
            return
        }
        #endif
        canUseAlbums = PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
        guard canUseAlbums else { albums = []; return }
        let read = await Task.detached(priority: .utility) {
            PhotoLibraryService.fetchUserAlbums().map { Album(id: $0.localIdentifier, title: $0.localizedTitle ?? "") }
                .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }.value
        // A newer read (the library changed again) wins.
        guard !Task.isCancelled else { return }
        albums = read
    }

    // MARK: Building

    /// The menu for `ids` (the selection, or the one photo right-clicked).
    func menu(for ids: [String]) -> NSMenu? {
        guard !ids.isEmpty else { return nil }
        let isLarge = ids.count > Self.readLimit
        let facts = isLarge ? Facts() : Facts.read(ids, database: dependencies.database)
        let menu = NSMenu()
        menu.autoenablesItems = false
        let allOffline = ids.allSatisfy(offline.contains)

        if !allOffline, !isLarge {
            menu.addItem(item(String(localized: "Quick Look", comment: "Mac photo menu"), id: "quickLook") { [weak self] in
                self?.showQuickLook(ids, facts: facts)
            })
        }
        menu.addItem(.separator())

        let marks = dependencies.photoMarks
        let single = ids.count == 1 ? ids[0] : nil
        let rating = NSMenuItem(title: MarkCopy.rating, action: nil, keyEquivalent: "")
        rating.identifier = NSUserInterfaceItemIdentifier("rating")
        rating.submenu = NSMenu()
        for stars in StarRating.range.reversed() {
            let row = item(PhotoMarkMenuTitles.rating(stars), id: "rating.\(stars)") { [weak self] in
                Task { await marks.apply(.rate(stars), to: ids); self?.changed(ids) }
            }
            row.state = single.map { marks.rating(for: $0, photosRating: facts.photosRatings[$0]) == stars } == true ? .on : .off
            row.setAccessibilityLabel(stars == 0 ? MarkCopy.noRating : MarkCopy.starsAccessibility(stars))
            rating.submenu?.addItem(row)
        }
        menu.addItem(rating)

        let flag = NSMenuItem(title: MarkCopy.flag, action: nil, keyEquivalent: "")
        flag.identifier = NSUserInterfaceItemIdentifier("flag")
        flag.submenu = NSMenu()
        flag.submenu?.autoenablesItems = false
        for (title, value, key) in [(MarkCopy.pick, PhotoFlag?.some(.pick), "pick"), (MarkCopy.reject, PhotoFlag?.some(.reject), "reject")] {
            let row = item(title, id: "flag.\(key)") { [weak self] in
                Task { await marks.apply(.flag(value), to: ids); self?.changed(ids) }
            }
            row.state = single.map { marks.flag(for: $0) == value } == true ? .on : .off
            flag.submenu?.addItem(row)
        }
        let clear = item(MarkCopy.clearFlag, id: "flag.clear") { [weak self] in
            Task { await marks.apply(.flag(nil), to: ids); self?.changed(ids) }
        }
        clear.isEnabled = single.map { marks.flag(for: $0) != nil } ?? true
        flag.submenu?.addItem(clear)
        menu.addItem(flag)

        // Favorite is Photos' own mark: only for photos that are in Photos.
        if isLarge || !facts.photosAssetIds.isEmpty {
            let allFavorite = !isLarge && facts.photosIds.allSatisfy(facts.favoriteIds.contains)
            let title = allFavorite ? String(localized: "Unfavorite", comment: "Mac photo menu: remove from Favorites")
                                    : String(localized: "Favorite", comment: "Mac photo menu: add to Favorites")
            menu.addItem(item(title, id: "favorite") { [weak self] in
                self?.setFavorite(!allFavorite, ids: ids, facts: facts)
            })
        }
        menu.addItem(.separator())

        // Albums are Photos' own: with no full access there is none to add to.
        if canUseAlbums, isLarge || !facts.photosAssetIds.isEmpty {
            menu.addItem(albumItem(ids, facts: facts))
        }
        if !allOffline, !isLarge {
            menu.addItem(shareItem(ids, facts: facts))
        }
        menu.addItem(.separator())

        // Show in Finder: the files on a connected folder or drive.
        if !allOffline, isLarge || !facts.fileCopies.isEmpty {
            menu.addItem(item(String(localized: "Show in Finder", comment: "Mac photo menu"), id: "showInFinder") { [weak self] in
                guard let self else { return }
                Task { self.showInFinder(await self.resolved(facts, ids: ids)) }
            })
            menu.addItem(.separator())
        }

        menu.addItem(item(String(localized: "Move to Trash", comment: "Mac photo menu"), id: "trash") { [weak self] in
            self?.trash(ids)
        })
        // No separator first or last, none doubled.
        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        for index in stride(from: menu.items.count - 1, to: 0, by: -1)
        where menu.items[index].isSeparatorItem && menu.items[index - 1].isSeparatorItem {
            menu.removeItem(at: index)
        }
        return menu
    }

    private func albumItem(_ ids: [String], facts: Facts) -> NSMenuItem {
        let album = NSMenuItem(title: String(localized: "Add to Album", comment: "Mac photo menu: submenu"), action: nil, keyEquivalent: "")
        album.identifier = NSUserInterfaceItemIdentifier("addToAlbum")
        let submenu = NSMenu()
        submenu.addItem(item(String(localized: "New Album with Selection", comment: "Mac photo menu: Add to Album"), id: "album.newWithSelection") { [weak self] in
            self?.newAlbum(ids, photosCount: facts.isKnown ? facts.photosAssetIds.count : ids.count)
        })
        submenu.addItem(item(String(localized: "New Album…", comment: "Mac photo menu: Add to Album, an empty album"), id: "album.new") { [weak self] in
            self?.newAlbum([], photosCount: 0)
        })
        if !albums.isEmpty {
            submenu.addItem(.separator())
            submenu.addItem(.sectionHeader(title: String(localized: "Albums", comment: "Mac photo menu: Add to Album, the list")))
            for entry in albums {
                submenu.addItem(item(entry.title, id: "album.\(entry.id)") { [weak self] in
                    guard let self else { return }
                    Task { self.add(await self.resolved(facts, ids: ids).photosAssetIds, toAlbum: entry.id) }
                })
            }
        }
        album.submenu = submenu
        return album
    }

    /// The share services for photo files; the files themselves are found
    /// (and Photos originals written out) only once one is picked.
    private func shareItem(_ ids: [String], facts: Facts) -> NSMenuItem {
        let share = NSMenuItem(title: String(localized: "Share", comment: "Mac photo menu: submenu"), action: nil, keyEquivalent: "")
        share.identifier = NSUserInterfaceItemIdentifier("share")
        let submenu = NSMenu()
        for service in Self.shareServices {
            let row = item(service.menuItemTitle, id: "share.\(service.title)") { [weak self] in
                guard let self else { return }
                Task {
                    let urls = await self.files(for: ids, facts: facts)
                    guard !urls.isEmpty else {
                        self.failure = String(localized: "These photos couldn't be shared — they may still be downloading from iCloud.", comment: "Mac photo menu: Share found no file")
                        return
                    }
                    service.perform(withItems: urls)
                }
            }
            row.image = service.image
            submenu.addItem(row)
        }
        share.submenu = submenu
        share.isEnabled = !submenu.items.isEmpty
        return share
    }

    /// A one-pixel JPEG: the services offered for a photo file are asked
    /// with a file that exists, before the real ones are written out.
    nonisolated private static let shareSample: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexShareSample.jpg")
        if !FileManager.default.fileExists(atPath: url.path),
           let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
           let image = context.makeImage(),
           let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
        return url
    }()

    /// Asked once: loading the sharing extensions costs a click its speed.
    static let shareServices = NSSharingService.sharingServices(forItems: [shareSample])

    private func item(_ title: String, id: String, perform: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(MacMenuAction.run(_:)), keyEquivalent: "")
        let action = MacMenuAction(perform)
        item.target = action
        item.representedObject = action
        item.identifier = NSUserInterfaceItemIdentifier("photoMenu.\(id)")
        item.setAccessibilityIdentifier("photoMenu.\(id)")
        return item
    }

    // MARK: Acting

    private func setFavorite(_ isFavorite: Bool, ids: [String], facts: Facts) {
        let photoLibrary = dependencies.photoLibrary, metadataStore = dependencies.metadataStore
        Task {
            let facts = await resolved(facts, ids: ids)
            var done = Array(facts.photosIds)
            #if DEBUG
            // The demo has no assets: its favorites are only rows.
            if MacDemoLibrary.isOn { done = ids }
            #endif
            let assetIds = facts.photosAssetIds, written = done
            guard !written.isEmpty else {
                failure = String(localized: "None of these photos are in Photos, so they can't be favorites.", comment: "Mac photo menu: Favorite on photos not in Photos")
                return
            }
            if !assetIds.isEmpty {
                let assets = await Task.detached(priority: .userInitiated) { PhotoLibraryService.fetchAssets(ids: assetIds) }.value
                if !assets.isEmpty {
                    do {
                        try await photoLibrary.setFavorite(isFavorite, for: assets)
                    } catch {
                        failure = error.localizedDescription
                        return
                    }
                }
            }
            await Task.detached(priority: .userInitiated) {
                try? metadataStore.updateFavorites(assetIds: written, isFavorite: isFavorite)
            }.value
            // Favorite is Photos' own: say what stayed as it was.
            let skipped = ids.count - written.count
            if skipped > 0 {
                failure = String(localized: "\(skipped) of these photos aren't in Photos, so they stay as they were.",
                                 comment: "Mac: favorite on a mix of Photos and folder photos (plural)")
            }
            changed(ids)
        }
    }

    func add(_ assetIds: [String], toAlbum albumId: String) {
        let photoLibrary = dependencies.photoLibrary
        Task {
            let (assets, collection) = await Task.detached(priority: .userInitiated) {
                (PhotoLibraryService.fetchAssets(ids: assetIds),
                 PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumId], options: nil).firstObject)
            }.value
            // The demo's albums are names only, and its photos have no assets.
            guard let collection, !assets.isEmpty else {
                #if DEBUG
                if MacDemoLibrary.isOn { return }
                #endif
                failure = collection == nil
                    ? String(localized: "The album is no longer in Photos.", comment: "Mac photo menu: Add to Album, album gone")
                    : String(localized: "None of these photos are in Photos, so they can't go into a Photos album.", comment: "Mac photo menu: Add to Album, no Photos assets")
                return
            }
            do { try await photoLibrary.addAssets(assets, to: collection) } catch { failure = error.localizedDescription }
        }
    }

    /// A new Photos album, with `ids`' Photos assets in it (none: empty).
    func createAlbum(named name: String, ids: [String]) {
        let photoLibrary = dependencies.photoLibrary, database = dependencies.database
        Task {
            #if DEBUG
            // Never a real album from the demo.
            if MacDemoLibrary.isOn {
                albums.append(Album(id: "demo-album-\(name)", title: name))
                return
            }
            #endif
            let assets = await Task.detached(priority: .userInitiated) {
                PhotoLibraryService.fetchAssets(ids: Facts.read(ids, database: database).photosAssetIds)
            }.value
            // A selection with nothing in Photos makes no empty album by surprise.
            guard ids.isEmpty || !assets.isEmpty else {
                failure = String(localized: "None of these photos are in Photos, so they can't go into a Photos album.", comment: "Mac photo menu: Add to Album, no Photos assets")
                return
            }
            do {
                let collection = try await photoLibrary.createAlbum(named: name)
                try await photoLibrary.addAssets(assets, to: collection)
            } catch {
                failure = error.localizedDescription
            }
            await loadAlbums()
        }
    }

    private func showInFinder(_ facts: Facts) {
        let roots = dependencies.folderRoots, copies = facts.fileCopies
        Task {
            let urls = await Task.detached(priority: .userInitiated) { Self.existingFiles(copies, roots: roots).map(\.url) }.value
            guard !urls.isEmpty else { NSSound.beep(); return }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    private func showQuickLook(_ ids: [String], facts: Facts) {
        let panel = quickLook ?? MacQuickLook()
        quickLook = panel
        quickLookTask?.cancel()
        // The first 50 (as Finder previews a large selection page by page):
        // each Photos one may be a download.
        let ids = Array(ids.prefix(50))
        quickLookTask = Task {
            let urls = await files(for: ids, facts: facts)
            guard !Task.isCancelled else { return }
            guard !urls.isEmpty else {
                failure = String(localized: "These photos couldn't be opened — they may still be downloading from iCloud.", comment: "Mac photo menu: Quick Look found no file")
                return
            }
            panel.show(urls)
        }
    }

    /// The copies whose file is there now (a drive may have gone).
    nonisolated private static func existingFiles(_ copies: [Facts.FileCopy], roots: FolderSourceRoots) -> [(photoId: String, url: URL)] {
        copies.compactMap { copy in
            roots.fileURL(sourceId: copy.sourceId, relativePath: copy.relativePath)
                .flatMap { FileManager.default.fileExists(atPath: $0.path) ? (copy.photoId, $0) : nil }
        }
    }

    /// A file for each photo: the copy on a connected folder or drive, else
    /// the Photos version (the edit, if it has one — as a drag out gives,
    /// FS-18.01b §5) written to a temporary file. Off the main actor.
    func files(for ids: [String], facts: Facts) async -> [URL] {
        let roots = dependencies.folderRoots, copies = facts.fileCopies
        let found = await Task.detached(priority: .userInitiated) { Self.existingFiles(copies, roots: roots) }.value
        var urls = found.map(\.url)
        // A photo whose file is not there falls back to its Photos copy.
        let covered = Set(found.map(\.photoId))
        let fromPhotos = facts.photosAssetIdsByPhoto.filter { !covered.contains($0.key) }.compactMap(\.value.first)
        if !fromPhotos.isEmpty { urls += await MacPhotosExport.write(assetIds: fromPhotos) }
        #if DEBUG
        // The demo's pictures, as files, so Quick Look and Share have one.
        if MacDemoLibrary.isOn, urls.isEmpty {
            urls = await Task.detached(priority: .userInitiated) { MacDemoLibrary.pictureFiles(for: ids) }.value
        }
        #endif
        return urls
    }

    // MARK: Facts

    /// Where the photos live: one indexed read of their copies and favorite
    /// flag. A selection of thousands is read in one statement per 900 ids.
    struct Facts: Sendable {
        struct FileCopy: Sendable {
            let photoId: String
            let sourceId: String
            let relativePath: String
        }

        /// False for a selection too large to read as the menu opened.
        var isKnown = false
        var fileCopies: [FileCopy] = []
        /// Photo id → its PHAsset ids (a merged photo may hold two).
        var photosAssetIdsByPhoto: [String: [String]] = [:]
        var favoriteIds: Set<String> = []
        /// Stars as the index last read them from Photos (FS-01.12).
        var photosRatings: [String: Int] = [:]

        var photosIds: Set<String> { Set(photosAssetIdsByPhoto.keys) }
        var photosAssetIds: [String] { photosAssetIdsByPhoto.values.flatMap { $0 } }

        nonisolated static func read(_ ids: [String], database: AppDatabase) -> Facts {
            var facts = Facts()
            // A failed read stays unknown: the rows show and each action reads again.
            do {
            try database.reader.read { db in
                for chunk in stride(from: 0, to: ids.count, by: 900).map({ Array(ids[$0..<min(ids.count, $0 + 900)]) }) {
                    let marks = databaseQuestionMarks(count: chunk.count)
                    let args = StatementArguments(chunk)
                    let copies = try Row.fetchCursor(db, sql: """
                        SELECT c.photoId, c.kind, c.sourceId, c.relativePath, c.photoKitId
                        FROM photo_copies c
                        WHERE c.photoId IN (\(marks)) AND c.isHidden = 0 AND c.missingSince IS NULL
                        """, arguments: args)
                    while let row = try copies.next() {
                        let photoId: String = row[0]
                        switch row[1] as String? {
                        case "photos":
                            if let assetId: String = row[4] { facts.photosAssetIdsByPhoto[photoId, default: []].append(assetId) }
                        case "file":
                            if let sourceId: String = row[2], let path: String = row[3] {
                                facts.fileCopies.append(FileCopy(photoId: photoId, sourceId: sourceId, relativePath: path))
                            }
                        default: break
                        }
                    }
                    let rows = try Row.fetchCursor(db, sql: "SELECT assetId, isFavorite, rating FROM photo_metadata WHERE assetId IN (\(marks))",
                                                   arguments: args)
                    while let row = try rows.next() {
                        let id: String = row[0]
                        if row[1] as Bool? == true { facts.favoriteIds.insert(id) }
                        if let rating: Int = row[2] { facts.photosRatings[id] = rating }
                    }
                }
            }
            } catch {
                return Facts()
            }
            facts.isKnown = true
            return facts
        }
    }
}

/// A name asked for a new album; `ids` empty for New Album….
struct MacAlbumRequest: Identifiable {
    let id = UUID()
    let ids: [String]
    /// How many of them are in Photos — the ones the album gets.
    let photosCount: Int
}

/// `None`, `★` … `★★★★★`, as the iOS rating menu.
enum PhotoMarkMenuTitles {
    static func rating(_ stars: Int) -> String {
        stars == 0 ? MarkCopy.noRating : String(repeating: "★", count: stars)
    }
}

/// A menu row's closure, kept alive by the row.
final class MacMenuAction: NSObject {
    private let perform: @MainActor () -> Void

    init(_ perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    @MainActor @objc func run(_ sender: Any?) { perform() }
}

/// Quick Look on photo files: the shared panel, fed from here.
@MainActor
final class MacQuickLook: NSObject, QLPreviewPanelDataSource {
    private var urls: [URL] = []
    private var keys: Any?

    func show(_ urls: [URL]) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
        // No view of ours owns the panel (no responder takes its control),
        // so Escape and Space, which close it in Finder, are caught here.
        if keys == nil {
            // Local monitors fire on the main thread.
            keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return event }
                    // Closed some other way (its button, ⌘W): the monitor goes.
                    guard panel.isVisible else { self.stopKeys(); return event }
                    // Only keys meant for the panel: a space typed in search stays.
                    guard panel.isKeyWindow, [53, 49].contains(event.keyCode) else { return event }
                    panel.orderOut(nil)
                    self.stopKeys()
                    return nil
                }
            }
        }
    }

    private func stopKeys() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    // QLPreviewPanel asks its data source on the main thread.
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { index < urls.count ? urls[index] as NSURL : nil }
    }
}

/// Photos' versions written to temporary files, for Quick Look and Share:
/// each in a folder of its own (two photos may share a name), all removed
/// at the next launch.
enum MacPhotosExport {
    nonisolated static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ShotDexShare", isDirectory: true)
    }

    /// Last launch's files, removed off the main actor — once, however many
    /// windows open (a second window must not take the first one's files).
    @MainActor static func clearOnce() {
        guard !hasCleared else { return }
        hasCleared = true
        let folder = folder
        Task.detached(priority: .background) { try? FileManager.default.removeItem(at: folder) }
    }

    @MainActor private static var hasCleared = false

    static func write(assetIds: [String]) async -> [URL] {
        let assets = await Task.detached(priority: .userInitiated) { PhotoLibraryService.fetchAssets(ids: assetIds) }.value
        var urls: [URL] = []
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            // The edit when there is one, else the original.
            guard let resource = resources.first(where: { $0.type == .fullSizePhoto || $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .photo || $0.type == .video }) else { continue }
            let own = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
            let url = own.appendingPathComponent(resource.originalFilename)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            do {
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
                urls.append(url)
            } catch {
                continue
            }
        }
        return urls
    }
}
