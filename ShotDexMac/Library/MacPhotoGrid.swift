import AppKit
import Photos
import SwiftUI

/// The Library grid on the Mac (board `Main`, FS-18 K3): an
/// `NSCollectionView` of square tiles in day sections, newest day first,
/// seven columns at 1440 wide. The rows come from the shared `LibraryModel`.
struct MacPhotoGrid: NSViewRepresentable {
    let items: [LibraryGridItem]
    let photoLibrary: PhotoLibraryService
    let asset: (String) -> PHAsset?
    /// A picture by asset id, for a library that is not Photos (the demo).
    var picture: ((String) -> CGImage?)? = nil
    /// The rows are already newest first (a smart album); the Library
    /// model keeps the newest at the end.
    var isNewestFirst = false
    /// Day sections with headers (the Library, board `Main`); off, one flat
    /// run of tiles (a smart album, board `MAC_SmartAlbum`, as on iOS).
    var showsDays = true
    /// Photos with a copy on a server (FS-19.07 §8): the drive glyph.
    var onServer: Set<String> = []
    /// The selected asset ids, each time the selection changes.
    var onSelection: ((Set<String>) -> Void)? = nil
    /// The model's id-list generation (`LibraryModel.contentGeneration`):
    /// when given, an unchanged number skips the update without comparing
    /// 55k ids on every SwiftUI pass.
    var generation: Int? = nil
    /// A PHAsset by newest-first position, from the model's non-blocking
    /// cache: a miss returns nil and resolves off the main actor. Without it
    /// `asset` is called, which fetches synchronously.
    var assetAt: ((Int) -> PHAsset?)? = nil
    /// Bumped when the cache resolved a chunk: tiles still without a
    /// picture ask again.
    var assetGeneration = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = MacGridMetrics.spacing
        layout.minimumLineSpacing = MacGridMetrics.spacing
        layout.sectionInset = NSEdgeInsets(top: 0, left: MacGridMetrics.sideInset, bottom: MacGridMetrics.sectionGap,
                                           right: MacGridMetrics.sideInset)
        layout.headerReferenceSize = NSSize(width: 0, height: MacGridMetrics.headerHeight)
        let collection = MacGridCollectionView()
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.backgroundColors = [.clear]
        collection.register(MacPhotoTile.self, forItemWithIdentifier: MacPhotoTile.identifier)
        collection.register(MacDayHeader.self, forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
                            withIdentifier: MacDayHeader.identifier)
        collection.dataSource = context.coordinator
        collection.delegate = context.coordinator
        context.coordinator.collection = collection
        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.photoLibrary = photoLibrary
        coordinator.asset = asset
        coordinator.picture = picture
        coordinator.onSelection = onSelection
        let glyphsChanged = coordinator.onServer != onServer
        coordinator.onServer = onServer
        coordinator.assetAt = assetAt
        coordinator.update(items, isNewestFirst: isNewestFirst, showsDays: showsDays, generation: generation,
                           forceReload: glyphsChanged)
        coordinator.assetsResolved(assetGeneration)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        weak var collection: NSCollectionView?
        var photoLibrary: PhotoLibraryService?
        var asset: (String) -> PHAsset? = { _ in nil }
        var assetAt: ((Int) -> PHAsset?)?
        private var lastGeneration: Int?
        private var lastAssetGeneration = 0
        /// The newest-first rows and day sections being built off the main
        /// actor; a newer update cancels it.
        private var buildTask: Task<Void, Never>?
        var picture: ((String) -> CGImage?)?
        var onServer: Set<String> = []
        var onSelection: ((Set<String>) -> Void)?
        /// Settings › General › Thumbnails (AC-67, AC-68); a change redraws the tiles on screen.
        private var fields = ThumbnailInfoFields.load()
        private var rows: [LibraryGridItem] = []
        private var sections: [PhotoGridSection] = []
        /// Videos per section, for the day header's words.
        private var sectionVideos: [Int] = []

        private var showsDays = true

        override init() {
            super.init()
            // Selector-based: the center drops it when the coordinator goes.
            NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                                   name: UserDefaults.didChangeNotification, object: nil)
        }

        /// Any default changing posts this, on whatever thread wrote it.
        @objc nonisolated private func defaultsChanged() {
            Task { @MainActor [weak self] in self?.reloadFieldsIfChanged() }
        }

        private func reloadFieldsIfChanged() {
            let loaded = ThumbnailInfoFields.load()
            guard loaded != fields, let collection else { return }
            fields = loaded
            // Text only: the pictures stay, nothing is fetched again.
            let side = MacGridMetrics.tileSide(contentWidth: collection.bounds.width)
            for case let tile as MacPhotoTile in collection.visibleItems() {
                guard let indexPath = collection.indexPath(for: tile) else { continue }
                let row = rows[sections[indexPath.section].range.lowerBound + indexPath.item]
                tile.showInfo(row, side: side, fields: fields, isOnServer: onServer.contains(row.assetId))
            }
        }

        func update(_ items: [LibraryGridItem], isNewestFirst: Bool, showsDays: Bool, generation: Int?, forceReload: Bool) {
            if let generation {
                guard forceReload || showsDays != self.showsDays || generation != lastGeneration else { return }
                lastGeneration = generation
            } else {
                let newestFirst = isNewestFirst ? items : Array(items.reversed())
                guard forceReload || showsDays != self.showsDays || newestFirst.map(\.assetId) != rows.map(\.assetId) else { return }
            }
            self.showsDays = showsDays
            // The model keeps the newest at the end (the iOS grid anchors at
            // the bottom); the Mac reads top-down, newest day first. The
            // reverse and the day sections (51 ms at 55k) are built off the
            // main actor; the click that changed the list never waits on them.
            buildTask?.cancel()
            buildTask = Task { [weak self] in
                let built = await Task.detached(priority: .userInitiated) {
                    let rows = isNewestFirst ? items : Array(items.reversed())
                    let sections = showsDays
                        ? PhotoGridSectionBuilder.sections(creationDates: rows.map(\.creationDateValue), granularity: .day)
                        : rows.isEmpty ? [] : [PhotoGridSection(kind: .undated, range: 0..<rows.count)]
                    let videos = sections.map { section in
                        rows[section.range].reduce(0) { $0 + (MediaKind(storedValue: $1.mediaType) == .video ? 1 : 0) }
                    }
                    return (rows, sections, videos)
                }.value
                guard let self, !Task.isCancelled else { return }
                (self.rows, self.sections, self.sectionVideos) = built
                self.collection?.reloadData()
            }
        }

        /// A chunk of assets resolved: tiles on screen that are still blank
        /// take their asset now.
        func assetsResolved(_ generation: Int) {
            guard generation != lastAssetGeneration, let collection else { return }
            lastAssetGeneration = generation
            let side = MacGridMetrics.tileSide(contentWidth: collection.bounds.width)
            for case let tile as MacPhotoTile in collection.visibleItems() where !tile.hasPicture {
                guard let indexPath = collection.indexPath(for: tile) else { continue }
                let index = sections[indexPath.section].range.lowerBound + indexPath.item
                guard index < rows.count, let asset = assetAt?(index) else { continue }
                let row = rows[index]
                tile.show(row, asset: asset, picture: nil, photoLibrary: photoLibrary, side: side,
                          fields: fields, isOnServer: onServer.contains(row.assetId))
            }
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int { sections.count }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            sections[section].range.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let tile = collectionView.makeItem(withIdentifier: MacPhotoTile.identifier, for: indexPath) as! MacPhotoTile
            let index = sections[indexPath.section].range.lowerBound + indexPath.item
            let row = rows[index]
            let picture = picture?(row.assetId)
            // The cache never blocks; the synchronous lookup is for grids
            // without one (a smart album).
            let asset = picture != nil ? nil : assetAt.map { $0(index) } ?? asset(row.assetId)
            tile.show(row, asset: asset, picture: picture, photoLibrary: photoLibrary,
                      side: MacGridMetrics.tileSide(contentWidth: collectionView.bounds.width),
                      fields: fields, isOnServer: onServer.contains(row.assetId))
            return tile
        }

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            reportSelection(collectionView)
        }

        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
            reportSelection(collectionView)
        }

        private func reportSelection(_ collectionView: NSCollectionView) {
            let ids = collectionView.selectionIndexPaths.compactMap { path -> String? in
                guard path.section < sections.count else { return nil }
                let index = sections[path.section].range.lowerBound + path.item
                return index < rows.count ? rows[index].assetId : nil
            }
            onSelection?(Set(ids))
        }

        func collectionView(_ collectionView: NSCollectionView, viewForSupplementaryElementOfKind kind: NSCollectionView.SupplementaryElementKind,
                            at indexPath: IndexPath) -> NSView {
            let header = collectionView.makeSupplementaryView(ofKind: kind, withIdentifier: MacDayHeader.identifier, for: indexPath) as! MacDayHeader
            let section = sections[indexPath.section]
            let videos = indexPath.section < sectionVideos.count ? sectionVideos[indexPath.section] : 0
            header.show(section, count: LibraryCountLine.text(shown: section.range.count, videos: videos, total: nil, isFiltered: false))
            return header
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> NSSize {
            let side = MacGridMetrics.tileSide(contentWidth: collectionView.bounds.width)
            return NSSize(width: side, height: side)
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            referenceSizeForHeaderInSection section: Int) -> NSSize {
            NSSize(width: 0, height: showsDays ? MacGridMetrics.headerHeight : 0)
        }

        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout,
                            insetForSectionAt section: Int) -> NSEdgeInsets {
            NSEdgeInsets(top: showsDays ? 0 : MacGridMetrics.flatTopInset, left: MacGridMetrics.sideInset,
                         bottom: MacGridMetrics.sectionGap, right: MacGridMetrics.sideInset)
        }
    }
}

/// Re-sizes the tiles whenever the width changes. The flow layout asks
/// for item sizes once; without this a scroller appearing after the first
/// layout leaves seven tiles too wide for the row, and it wraps at six.
final class MacGridCollectionView: NSCollectionView {
    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { collectionViewLayout?.invalidateLayout() }
    }
}

/// Grid numbers from board `Main` and FS-18 AC-30: seven columns of ~165pt at
/// 1440, 2pt gaps, 16pt from the content's edges.
enum MacGridMetrics {
    static let columns = 7
    static let spacing: CGFloat = 2
    static let sideInset: CGFloat = 16
    static let headerHeight: CGFloat = 44
    static let sectionGap: CGFloat = 12
    /// A flat grid's gap under the bar above it (board `MAC_SmartAlbum`).
    static let flatTopInset: CGFloat = 8

    static func tileSide(contentWidth: CGFloat) -> CGFloat {
        let usable = contentWidth - sideInset * 2 - spacing * CGFloat(columns - 1)
        return max(80, floor(usable / CGFloat(columns)))
    }
}

/// One tile: the photo filled square, its format top-left, EXIF bottom-right
/// over a shade (board `Main`).
final class MacPhotoTile: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MacPhotoTile")
    private let photo = NSView()
    private let badge = NSTextField(labelWithString: "")
    private let exif = NSTextField(labelWithString: "")
    /// File name and capture time, when Settings shows them: a line above the exposure.
    private let caption = NSTextField(labelWithString: "")
    /// "On server" (FS-19.07 §8): bottom-left, as on iOS.
    private let serverGlyph = NSImageView(image: NSImage(systemSymbolName: "externaldrive.fill.badge.checkmark",
                                                           accessibilityDescription: nil) ?? NSImage())
    private let shade = CAGradientLayer()
    private var requestId: PHImageRequestID?
    private weak var photoLibrary: PhotoLibraryService?
    private var assetId: String?
    /// One line of 11pt text 6pt off the bottom edge; two with a caption.
    private static let shadeHeight: CGFloat = 24
    private static let captionedShadeHeight: CGFloat = 46
    private var hasCaption = false
    /// The exposure line keeps clear of the server glyph only while it shows.
    private lazy var clearOfGlyph = exif.leadingAnchor.constraint(greaterThanOrEqualTo: serverGlyph.trailingAnchor, constant: 4)

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        photo.wantsLayer = true
        photo.layer?.contentsGravity = .resizeAspectFill
        photo.layer?.masksToBounds = true
        photo.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        // A layer-backed NSView is not flipped: y = 0 is the bottom edge, so
        // the dark end is the start point. Same 24pt band and 55% as iOS.
        shade.colors = [NSColor.black.withAlphaComponent(0.55).cgColor, NSColor.clear.cgColor]
        shade.startPoint = CGPoint(x: 0.5, y: 0)
        shade.endPoint = CGPoint(x: 0.5, y: 1)
        photo.layer?.addSublayer(shade)
        badge.font = .systemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.drawsBackground = true
        badge.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        exif.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        exif.textColor = .white
        exif.alignment = .right
        caption.font = .systemFont(ofSize: 10, weight: .semibold)
        caption.textColor = .white
        caption.alignment = .right
        // The time at the end always stays; a long name loses its front ("…04100.HEIC · 18:00").
        caption.lineBreakMode = .byTruncatingHead
        // Both lines keep their edge on a bright sky the shade barely darkens.
        for label in [caption, exif] {
            label.wantsLayer = true
            label.shadow = {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowBlurRadius = 2
                return shadow
            }()
        }
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        serverGlyph.contentTintColor = .white
        serverGlyph.symbolConfiguration = .init(pointSize: 11, weight: .semibold)
        for subview in [photo, badge, caption, exif, serverGlyph] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            photo.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            photo.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            photo.topAnchor.constraint(equalTo: view.topAnchor),
            photo.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            badge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            badge.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            exif.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            exif.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            exif.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
            caption.trailingAnchor.constraint(equalTo: exif.trailingAnchor),
            caption.bottomAnchor.constraint(equalTo: exif.topAnchor, constant: -1),
            caption.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 8),
            serverGlyph.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            serverGlyph.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = CGRect(x: 0, y: 0, width: view.bounds.width,
                             height: hasCaption ? Self.captionedShadeHeight : Self.shadeHeight)
        CATransaction.commit()
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 3 : 0
            view.layer?.borderColor = NSColor(MacTheme.accent).cgColor
        }
    }

    /// A picture is set or on its way; false while the asset is unresolved.
    private(set) var hasPicture = false

    func show(_ row: LibraryGridItem, asset: PHAsset?, picture: CGImage?, photoLibrary: PhotoLibraryService?, side: CGFloat,
              fields: ThumbnailInfoFields, isOnServer: Bool = false) {
        hasPicture = picture != nil || asset != nil
        // A reused tile drops a late result by its asset id, below.
        requestId = nil
        photo.layer?.contents = nil
        assetId = row.assetId
        self.photoLibrary = photoLibrary
        showInfo(row, side: side, fields: fields, isOnServer: isOnServer)
        let name = row.originalFilename ?? String(localized: "Photo", comment: "Mac grid: a photo with no file name")
        view.setAccessibilityLabel(isOnServer
            ? String(localized: "\(name), On server", comment: "Mac grid: VoiceOver label of a photo that is on a server")
            : name)
        if let picture {
            photo.layer?.contents = picture
            return
        }
        guard let asset, let photoLibrary else { return }
        let scale = view.window?.backingScaleFactor ?? 2
        let pixels = CGSize(width: side * scale, height: side * scale)
        let id = row.assetId
        requestId = photoLibrary.requestThumbnail(for: asset, targetSize: pixels, allowNetwork: false) { [weak self] image, _ in
            guard let self, self.assetId == id, let image else { return }
            self.photo.layer?.contents = image.cgImage
        }
    }

    /// Badge, caption, exposure line and server glyph — everything over the
    /// picture; Settings changing them redraws only this.
    func showInfo(_ row: LibraryGridItem, side: CGFloat, fields: ThumbnailInfoFields, isOnServer: Bool) {
        let format = MacPhotoTile.format(of: row.originalFilename)
        badge.stringValue = format.map { " \($0) " } ?? ""
        badge.isHidden = format == nil || !fields.showsFileTypeBadge
        clearOfGlyph.isActive = isOnServer
        let font = exif.font ?? .systemFont(ofSize: 11)
        exif.stringValue = ThumbnailInfoFields.fitted(
            fields.exposureFragments(for: row),
            width: { Double(($0 as NSString).size(withAttributes: [.font: font]).width) },
            within: ThumbnailInfoFields.room(side: Double(side), glyphWidth: isOnServer ? Double(serverGlyph.intrinsicContentSize.width) : nil))
        caption.stringValue = fields.caption(for: row) ?? ""
        caption.isHidden = caption.stringValue.isEmpty
        hasCaption = !caption.isHidden
        view.needsLayout = true
        serverGlyph.isHidden = !isOnServer
        shade.isHidden = exif.stringValue.isEmpty && caption.isHidden && !isOnServer
    }

    /// `HEIC`, `RAW`, `JPG`, `MOV` — the extension, RAW formats as one word.
    static func format(of filename: String?) -> String? {
        guard let ext = filename.map({ ($0 as NSString).pathExtension.uppercased() }), !ext.isEmpty else { return nil }
        let raw: Set<String> = ["ARW", "CR2", "CR3", "NEF", "RAF", "ORF", "RW2", "DNG", "PEF", "SRW"]
        if raw.contains(ext) { return "RAW" }
        return ext == "JPEG" ? "JPG" : ext
    }
}

/// "Monday, September 28" over the day's photos, count on the right.
final class MacDayHeader: NSView, NSCollectionViewElement {
    static let identifier = NSUserInterfaceItemIdentifier("MacDayHeader")
    private let title = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        count.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        count.textColor = .secondaryLabelColor
        for label in [title, count] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MacGridMetrics.sideInset + 4),
            title.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MacGridMetrics.sideInset),
            count.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `count`: "48 photos", "3 photos · 2 videos" — the toolbar line's words.
    func show(_ section: PhotoGridSection, count: String) {
        switch section.kind {
        case .date(let date): title.stringValue = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        case .undated: title.stringValue = String(localized: "No Date", comment: "Mac grid: header of photos with no capture date")
        }
        self.count.stringValue = count
    }
}
