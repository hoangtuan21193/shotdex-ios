import AppKit
import Photos
import SwiftUI

/// The Library as a table (board `MAC_LibraryList`, FS-18.02 §3, ⌘2): a
/// thumbnail and eleven columns, 28pt rows, zebra stripes. A header click
/// sorts and a second one reverses it; columns resize, move, and hide from
/// the header's right-click menu, and keep that between launches. Rows come
/// from the same `LibraryModel` as the grid, newest first.
struct MacPhotoTable: NSViewRepresentable {
    let items: [LibraryGridItem]
    /// `LibraryModel.rowsGeneration`: an unchanged number skips the update.
    let generation: Int
    /// Camera, lens, rating, source (`LibraryTableQueries`), read off-main.
    let details: [String: LibraryTableQueries.Details]
    /// Bumped each time `details` is read again (a rating changed, say).
    var detailsGeneration = 0
    let photoLibrary: PhotoLibraryService
    /// A PHAsset by newest-first position, from the model's non-blocking cache.
    let assetAt: (Int) -> PHAsset?
    var assetGeneration = 0
    var picture: ((String) -> CGImage?)? = nil
    /// The library's own order for the columns it can sort by (Date, Focal,
    /// Aperture, Shutter, ISO): the grid keeps the same order.
    let sort: SortOption
    let setSort: (SortOption) -> Void
    var onSelection: ((Set<String>) -> Void)?
    /// The right-click menu for these photos (board `MAC_ContextMenu`).
    var contextMenu: (([String]) -> NSMenu?)? = nil
    /// Selected when the list appears (the grid's selection, after ⌘2).
    var initialSelection: Set<String> = []

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Whatever it is offered: asking the scroll view for a fitting size
    /// lays the whole table out on every SwiftUI pass.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let table = MacLibraryTableView()
        table.contextMenu = { [weak coordinator = context.coordinator] row in coordinator?.menu(forRow: row) }
        table.style = .fullWidth
        table.rowHeight = 28
        table.intercellSpacing = NSSize(width: 6, height: 0)
        // Zebra in `rowAlt` (DESIGN.md §10b), drawn by MacTableRowView.
        table.usesAlternatingRowBackgroundColors = false
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        for column in MacTableColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.width = column.width
            tableColumn.minWidth = column == .thumbnail ? 28 : 40
            tableColumn.headerCell.alignment = column.isNumeric ? .right : .left
            if column != .thumbnail {
                tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: column.ascendsFirst)
            } else {
                tableColumn.resizingMask = []
            }
            table.addTableColumn(tableColumn)
        }
        table.headerView?.frame.size.height = 28
        table.headerView?.menu = context.coordinator.headerMenu(for: table)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        // Widths, order and hidden columns outlive the window.
        table.autosaveName = "MacLibraryTable"
        table.autosaveTableColumns = true
        context.coordinator.table = table
        context.coordinator.pendingSelection = initialSelection
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = true
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.photoLibrary = photoLibrary
        coordinator.assetAt = assetAt
        coordinator.picture = picture
        coordinator.setSort = setSort
        coordinator.onSelection = onSelection
        coordinator.contextMenu = contextMenu
        coordinator.update(items, generation: generation, details: details, detailsGeneration: detailsGeneration, sort: sort)
        coordinator.assetsResolved(assetGeneration)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        weak var table: NSTableView?
        var photoLibrary: PhotoLibraryService?
        var assetAt: (Int) -> PHAsset? = { _ in nil }
        var picture: ((String) -> CGImage?)?
        var setSort: (SortOption) -> Void = { _ in }
        var onSelection: ((Set<String>) -> Void)?
        /// Newest first, then sorted by a column the library cannot sort by.
        private var rows: [LibraryGridItem] = []
        /// Each row's position in the library's newest-first order, for the
        /// asset cache (-1: not found) — nil while the rows are in that order.
        private var libraryIndex: [Int]?
        /// The library's rows as last handed over (oldest first): every
        /// rebuild starts from these, never from the sorted `rows`.
        private var items: [LibraryGridItem] = []
        private var details: [String: LibraryTableQueries.Details] = [:]
        private var lastGeneration: Int?
        private var lastDetailsGeneration = -1
        private var lastAssetGeneration = 0
        /// The library's order last seen: a change from elsewhere (Filter and
        /// Sort) ends a local sort, so the table and the grid agree.
        private var librarySort: SortOption?
        /// A local sort on Name, Camera, Lens, Rating, Source or Size — kept
        /// in the defaults, so a trip to the grid and back finds it again.
        private var localSort: NSSortDescriptor? = Coordinator.savedLocalSort() {
            didSet {
                let defaults = UserDefaults.standard
                if let localSort, let key = localSort.key {
                    defaults.set([key, localSort.ascending ? "ascending" : "descending"], forKey: Self.localSortKey)
                } else {
                    defaults.removeObject(forKey: Self.localSortKey)
                }
            }
        }
        private static let localSortKey = "mac.library.localSort"

        private static func savedLocalSort() -> NSSortDescriptor? {
            guard let saved = UserDefaults.standard.stringArray(forKey: localSortKey), saved.count == 2,
                  let column = MacTableColumn(rawValue: saved[0]), column.sortOption(ascending: true) == nil else { return nil }
            return NSSortDescriptor(key: column.rawValue, ascending: saved[1] == "ascending")
        }

        /// The window is switching to the grid: 55k rows and their details
        /// are let go off the main actor, not in the switch.
        func tearDown() {
            buildTask?.cancel()
            table?.dataSource = nil
            table?.delegate = nil
            let dead = (rows, items, details, libraryIndex)
            rows = []; items = []; details = [:]; libraryIndex = nil
            Task.detached(priority: .utility) { _ = dead }
        }
        private var buildTask: Task<Void, Never>?
        /// Selected once the first rows are in.
        var pendingSelection: Set<String> = []

        func update(_ items: [LibraryGridItem], generation: Int, details: [String: LibraryTableQueries.Details],
                    detailsGeneration: Int, sort: SortOption) {
            if let librarySort, librarySort != sort, localSort != nil { localSort = nil }
            librarySort = sort
            guard generation != lastGeneration || detailsGeneration != lastDetailsGeneration else {
                showSortIndicator(for: sort)
                return
            }
            lastGeneration = generation
            lastDetailsGeneration = detailsGeneration
            self.items = items
            self.details = details
            rebuild()
            showSortIndicator(for: sort)
        }

        /// The reverse and any local sort (55k rows) run off the main actor;
        /// a newer rebuild makes an older one stop and its result go unused.
        private func rebuild() {
            let items = items, sort = localSort, details = details
            buildTask?.cancel()
            buildTask = Task { [weak self] in
                let work = Task.detached(priority: .userInitiated) { () -> ([LibraryGridItem], [Int]?)? in
                    let newestFirst = Array(items.reversed())
                    guard let sort else { return (newestFirst, nil) }
                    let order = MacTableColumn.sortedOrder(newestFirst, by: sort, details: details)
                    guard !Task.isCancelled else { return nil }
                    return (order.map { newestFirst[$0] }, order)
                }
                let built = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                guard let self, !Task.isCancelled, let built else { return }
                var selected = self.selectedIds()
                if selected.isEmpty { selected = self.pendingSelection }
                self.pendingSelection = []
                // The old 55k rows are let go off the main actor: freeing them
                // here was a visible part of a sort.
                let old = (self.rows, self.libraryIndex)
                (self.rows, self.libraryIndex) = built
                Task.detached(priority: .utility) { _ = old }
                self.table?.reloadData()
                self.restoreSelection(selected)
            }
        }

        /// The asset for a row from the model's cache — nil unless it is that
        /// row's photo (the cache may already hold a newer list mid-rebuild).
        private func asset(forRow row: Int) -> PHAsset? {
            let position = libraryIndex.map { row < $0.count ? $0[row] : -1 } ?? row
            guard position >= 0, row < rows.count, let asset = assetAt(position),
                  asset.localIdentifier == rows[row].assetId else { return nil }
            return asset
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row < rows.count, let column = MacTableColumn(rawValue: tableColumn.identifier.rawValue) else { return nil }
            let item = rows[row]
            let cell = (tableView.makeView(withIdentifier: column.identifier, owner: nil) as? MacTableCell) ?? MacTableCell(column: column)
            switch column {
            case .thumbnail:
                cell.showThumbnail(for: item, picture: picture?(item.assetId), asset: asset(forRow: row), photoLibrary: photoLibrary)
            case .rating:
                let stars = details[item.assetId]?.rating ?? 0
                cell.show(column.text(for: item, details: details[item.assetId]), symbol: nil,
                          spoken: String(localized: "\(stars) of 5 stars", comment: "Mac list view: a rating, VoiceOver"))
            default:
                cell.show(column.text(for: item, details: details[item.assetId]),
                          symbol: column == .source ? MacTableColumn.sourceSymbol(details[item.assetId]?.sourceKind) : nil)
            }
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let view = (tableView.makeView(withIdentifier: MacTableRowView.identifier, owner: nil) as? MacTableRowView) ?? {
                let view = MacTableRowView()
                view.identifier = MacTableRowView.identifier
                return view
            }()
            view.isOddRow = !row.isMultiple(of: 2)
            view.needsDisplay = true
            return view
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            onSelection?(selectedIds())
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key,
                  let column = MacTableColumn(rawValue: key) else { return }
            if let option = column.sortOption(ascending: descriptor.ascending) {
                // The library sorts these itself (in SQL); the grid follows. A
                // local order goes at once — the library may already be in
                // this order and then nothing reloads.
                let hadLocal = localSort != nil
                localSort = nil
                librarySort = option
                setSort(option)
                if hadLocal { rebuild() }
            } else {
                localSort = descriptor
                rebuild()
            }
        }

        /// The header shows the library's order as long as no local sort is on.
        func showSortIndicator(for sort: SortOption) {
            guard let table else { return }
            // A library order no column shows (Date Added, say) shows no arrow.
            let descriptors = localSort.map { [$0] }
                ?? MacTableColumn.column(for: sort).map { [NSSortDescriptor(key: $0.0.rawValue, ascending: $0.1)] } ?? []
            if table.sortDescriptors != descriptors { table.sortDescriptors = descriptors }
        }

        /// A chunk of assets resolved: thumbnails on screen still without a
        /// picture ask again — in place, no cell is rebuilt.
        func assetsResolved(_ generation: Int) {
            guard generation != lastAssetGeneration, let table else { return }
            lastAssetGeneration = generation
            guard picture == nil else { return }
            let visible = table.rows(in: table.visibleRect)
            guard visible.length > 0, let column = table.tableColumns.firstIndex(where: { $0.identifier == MacTableColumn.thumbnail.identifier })
            else { return }
            for row in visible.location..<NSMaxRange(visible) where row < rows.count {
                guard let cell = table.view(atColumn: column, row: row, makeIfNecessary: false) as? MacTableCell, !cell.hasPicture,
                      let asset = asset(forRow: row) else { continue }
                cell.showThumbnail(for: rows[row], picture: nil, asset: asset, photoLibrary: photoLibrary)
            }
        }

        var contextMenu: (([String]) -> NSMenu?)?

        /// A right-click on a selected row acts on the selection; on any
        /// other row it selects that one alone first, as Finder.
        func menu(forRow row: Int) -> NSMenu? {
            guard let table, let contextMenu, row >= 0, row < rows.count else { return nil }
            if !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            let ids = table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].assetId : nil }
            return contextMenu(ids)
        }

        private func selectedIds() -> Set<String> {
            guard let table else { return [] }
            return Set(table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].assetId : nil })
        }

        private func restoreSelection(_ ids: Set<String>) {
            guard let table, !ids.isEmpty else { return }
            let indexes = IndexSet(rows.indices.filter { ids.contains(rows[$0].assetId) })
            table.selectRowIndexes(indexes, byExtendingSelection: false)
        }

        /// Right-click on the header: every column but the thumbnail, ticked
        /// while shown (FS-18.02 §3).
        func headerMenu(for table: NSTableView) -> NSMenu {
            let menu = NSMenu()
            for column in MacTableColumn.allCases where column != .thumbnail {
                let item = NSMenuItem(title: column.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = column.rawValue
                menu.addItem(item)
            }
            menu.delegate = self
            return menu
        }

        @objc private func toggleColumn(_ sender: NSMenuItem) {
            guard let key = sender.representedObject as? String,
                  let column = table?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(key)) else { return }
            column.isHidden.toggle()
            // A local order by a column no longer shown would have no arrow:
            // it goes, and the library's order is back.
            if column.isHidden, localSort?.key == key {
                localSort = nil
                rebuild()
                if let librarySort { showSortIndicator(for: librarySort) }
            }
        }
    }
}

extension MacPhotoTable.Coordinator: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            guard let key = item.representedObject as? String else { continue }
            item.state = table?.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(key))?.isHidden == false ? .on : .off
        }
    }
}

/// The table's columns, in the board's order.
enum MacTableColumn: String, CaseIterable {
    case thumbnail, name, date, camera, lens, focal, aperture, shutter, iso, rating, source, size

    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }

    var title: String {
        switch self {
        case .thumbnail: ""
        case .name: String(localized: "Name", comment: "Mac list view column")
        case .date: String(localized: "Date", comment: "Mac list view column")
        case .camera: String(localized: "Camera", comment: "Mac list view column")
        case .lens: String(localized: "Lens", comment: "Mac list view column")
        case .focal: String(localized: "Focal", comment: "Mac list view column")
        case .aperture: String(localized: "Aperture", comment: "Mac list view column")
        case .shutter: String(localized: "Shutter", comment: "Mac list view column")
        case .iso: String(localized: "ISO", comment: "Mac list view column")
        case .rating: String(localized: "Rating", comment: "Mac list view column")
        case .source: String(localized: "Source", comment: "Mac list view column")
        case .size: String(localized: "Size", comment: "Mac list view column")
        }
    }

    /// Board widths at 1440.
    var width: CGFloat {
        switch self {
        case .thumbnail: 28
        case .name: 120
        case .date: 156
        case .camera: 152
        case .lens: 146
        case .focal: 62
        case .aperture: 64
        case .shutter: 64
        case .iso: 50
        case .rating: 72
        case .source: 132
        case .size: 70
        }
    }

    var isNumeric: Bool { [.focal, .aperture, .shutter, .iso, .size].contains(self) }

    /// A first click on Date, ISO, Focal, Rating or Size shows the largest
    /// first, as Finder does for dates and sizes.
    var ascendsFirst: Bool { ![.date, .iso, .focal, .rating, .size].contains(self) }

    func sortOption(ascending: Bool) -> SortOption? {
        switch self {
        case .date: ascending ? .dateTakenOldest : .dateTakenNewest
        case .focal: ascending ? .focalLengthAscending : .focalLengthDescending
        case .aperture: ascending ? .apertureAscending : .apertureDescending
        case .shutter: ascending ? .shutterSpeedFastest : .shutterSpeedSlowest
        case .iso: ascending ? .isoAscending : .isoDescending
        default: nil
        }
    }

    static func column(for sort: SortOption) -> (MacTableColumn, Bool)? {
        for column in allCases {
            if column.sortOption(ascending: true) == sort { return (column, true) }
            if column.sortOption(ascending: false) == sort { return (column, false) }
        }
        return nil
    }

    func text(for item: LibraryGridItem, details: LibraryTableQueries.Details?) -> String {
        switch self {
        case .thumbnail: ""
        case .name: item.originalFilename ?? ""
        case .date: item.creationDateValue.map { Self.dateFormatter.string(from: $0) } ?? ""
        case .camera: details?.camera ?? ""
        case .lens: details?.lens ?? ""
        case .focal: item.focalLength.flatMap { Self.oneDecimal.string(from: NSNumber(value: $0)) }.map { "\($0) mm" } ?? ""
        case .aperture: item.aperture.flatMap { Self.twoDecimals.string(from: NSNumber(value: $0)) }.map { "f/\($0)" } ?? ""
        case .shutter: item.shutterSpeedDisplay.map { "\($0) s" } ?? ""
        // No grouping: "ISO 12800" is read as one number, not 12,800.
        case .iso: item.iso.map(String.init) ?? ""
        case .rating: details.map { MacStarText.text($0.rating) } ?? ""
        case .source: details?.sourceName ?? ""
        case .size: item.fileSize.map { Self.bytes.string(fromByteCount: Int64($0)) } ?? ""
        }
    }

    // One formatter each, made once: a cell is configured on every scroll
    // and every sort, and a formatter per cell was most of a sort's cost.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = false
        return formatter
    }()
    private static let oneDecimal: NumberFormatter = decimals(1)
    private static let twoDecimals: NumberFormatter = decimals(2)
    private static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static func decimals(_ digits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = digits
        formatter.minimumFractionDigits = 0
        return formatter
    }

    static func sourceSymbol(_ kind: String?) -> String? {
        switch kind {
        case "photos": "photo.on.rectangle"
        case "drive": "externaldrive"
        case "server": "server.rack"
        case .some: "folder"
        case nil: nil
        }
    }

    /// Name, Camera, Lens, Rating, Source and Size are sorted here; the rest
    /// come sorted from the library. Returns positions in `rows`, keys built
    /// once (not per comparison) so 55k rows sort in milliseconds.
    nonisolated static func sortedOrder(_ rows: [LibraryGridItem], by descriptor: NSSortDescriptor,
                                        details: [String: LibraryTableQueries.Details]) -> [Int] {
        guard let key = descriptor.key, let column = MacTableColumn(rawValue: key) else { return Array(rows.indices) }
        let ascending = descriptor.ascending
        func order<T: Comparable>(_ keys: [T?]) -> [Int] {
            rows.indices.sorted { a, b in
                switch (keys[a], keys[b]) {
                case let (x?, y?): x == y ? a < b : (ascending ? x < y : x > y)
                case (_?, nil): true
                case (nil, _?): false
                default: a < b
                }
            }
        }
        switch column {
        case .name: return order(rows.map { $0.originalFilename?.localizedLowercase })
        case .camera: return order(rows.map { details[$0.assetId]?.camera?.localizedLowercase })
        case .lens: return order(rows.map { details[$0.assetId]?.lens?.localizedLowercase })
        case .rating: return order(rows.map { details[$0.assetId]?.rating })
        case .source: return order(rows.map { details[$0.assetId]?.sourceName?.localizedLowercase })
        case .size: return order(rows.map { $0.fileSize })
        default: return Array(rows.indices)
        }
    }
}

/// "★★★★·" — filled stars then dots to five, as on the board.
enum MacStarText {
    static func text(_ stars: Int) -> String {
        let stars = max(0, min(5, stars))
        return String(repeating: "★", count: stars) + String(repeating: "·", count: 5 - stars)
    }
}

/// A row: amber (`accentFill`) while the table has the focus, grey `rowSel`
/// when it does not (FS-18.02 §3, DESIGN.md §10b) — never the system blue.
final class MacTableRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("MacTableRow")

    /// Its place in the table, for the zebra (odd rows tinted, as the board).
    var isOddRow = false

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isOddRow, !isSelected else { return }
        NSColor(MacTheme.rowAlternate).setFill()
        bounds.fill()
    }

    /// Radius 6; a run of selected rows reads as one block, rounded only at
    /// its ends.
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 6, dy: 0)
        (isEmphasized ? NSColor(MacTheme.accentFill) : NSColor(MacTheme.rowSelection)).setFill()
        let radius: CGFloat = 6
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        path.fill()
        // Square off the edge that meets a selected neighbour.
        if isPreviousRowSelected { NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: radius).fill() }
        if isNextRowSelected { NSRect(x: rect.minX, y: rect.maxY - radius, width: rect.width, height: radius).fill() }
    }

    override var isFlipped: Bool { true }

    /// White (light) or black (dark) text on amber, as `onAccentFill` says.
    override var interiorBackgroundStyle: NSView.BackgroundStyle {
        isSelected && isEmphasized ? .emphasized : .normal
    }
}

/// One cell: a 20pt thumbnail, or 13pt text (tabular for numbers) with an
/// optional glyph in front (the Source column). Text cells draw themselves —
/// no text field, no subviews: a sort redraws every visible cell, and ~400
/// text fields laid out and drawn made that a visible stall.
final class MacTableCell: NSTableCellView {
    /// A plain layer: NSImageView would repaint over contents set on it.
    private let thumb = NSView()
    private var column: MacTableColumn = .name
    private var text = ""
    private var symbol: String?
    private var assetId: String?
    private var requestId: PHImageRequestID?
    /// A picture is set or requested.
    private(set) var hasPicture = false
    private var font = NSFont.systemFont(ofSize: 13)
    private weak var photoLibrary: PhotoLibraryService?

    convenience init(column: MacTableColumn) {
        self.init(frame: .zero)
        // Set before the table sees it, so it goes back to the reuse queue.
        identifier = column.identifier
        self.column = column
        // Digits tabular wherever a column of them is read down: date and
        // the numbers. Rating's stars are 12pt, as the board.
        font = switch column {
        case .rating: .systemFont(ofSize: 12)
        case .date: .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        default: column.isNumeric ? .monospacedDigitSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 13)
        }
        if column == .thumbnail {
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 3
            thumb.layer?.masksToBounds = true
            thumb.layer?.contentsGravity = .resizeAspectFill
            addSubview(thumb)
            updatePlaceholder()
        }
    }

    /// The empty thumbnail's grey, again when the appearance changes (a
    /// CGColor does not follow it by itself).
    private func updatePlaceholder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            thumb.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if column == .thumbnail { updatePlaceholder() }
    }

    override var isFlipped: Bool { true }

    /// Off screen: its thumbnail request stops, its picture goes.
    override func prepareForReuse() {
        super.prepareForReuse()
        if let requestId { photoLibrary?.cancelThumbnailRequest(requestId) }
        requestId = nil
        assetId = nil
        thumb.layer?.contents = nil
    }

    override func layout() {
        super.layout()
        if column == .thumbnail {
            thumb.frame = NSRect(x: 4, y: (bounds.height - 20) / 2, width: 20, height: 20)
        }
    }

    /// White (light) or black (dark) on the amber of a focused selection.
    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { if backgroundStyle != oldValue { needsDisplay = true } }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard column != .thumbnail else { return }
        let onAccent = backgroundStyle == .emphasized
        let color: NSColor = onAccent ? NSColor(MacTheme.onAccentFill) : .labelColor
        var x: CGFloat = 2
        if let symbol, let glyph = Self.glyph(symbol, onAccent: onAccent) {
            glyph.draw(in: NSRect(x: 2, y: (bounds.height - 14) / 2, width: 14, height: 14))
            x = 22
        }
        let paragraph = column.isNumeric ? Self.trailing : Self.leading
        let attributed: NSAttributedString
        if column == .rating {
            // Stars in the text colour, the empty places dimmer.
            let stars = text.prefix { $0 == "★" }
            let string = NSMutableAttributedString(string: String(stars), attributes: [.foregroundColor: color])
            string.append(NSAttributedString(string: String(text.dropFirst(stars.count)),
                                             attributes: [.foregroundColor: onAccent ? color.withAlphaComponent(0.6) : NSColor.secondaryLabelColor]))
            string.addAttributes([.font: font, .kern: 0.5, .paragraphStyle: paragraph], range: NSRange(location: 0, length: string.length))
            attributed = string
        } else {
            attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let rect = NSRect(x: x, y: (bounds.height - lineHeight) / 2, width: max(0, bounds.width - x - 2), height: lineHeight)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private static let leading = paragraph(.left)
    private static let trailing = paragraph(.right)

    private static func paragraph(_ alignment: NSTextAlignment) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingMiddle
        return style
    }

    /// Each source glyph tinted once — amber, or the on-accent colour inside
    /// a focused selection — never made in `draw`.
    private static var glyphs: [String: NSImage] = [:]

    private static func glyph(_ symbol: String, onAccent: Bool) -> NSImage? {
        let key = "\(symbol)-\(onAccent)"
        if let image = glyphs[key] { return image }
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) else { return nil }
        let image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { frame in
            base.draw(in: frame)
            (onAccent ? NSColor(MacTheme.onAccentFill) : NSColor(MacTheme.accent)).set()
            frame.fill(using: .sourceAtop)
            return true
        }
        glyphs[key] = image
        return image
    }

    func show(_ text: String, symbol: String?, spoken: String? = nil) {
        guard text != self.text || symbol != self.symbol else { return }
        self.text = text
        self.symbol = symbol
        setAccessibilityLabel(spoken ?? text)
        needsDisplay = true
    }

    override func accessibilityRole() -> NSAccessibility.Role? { column == .thumbnail ? .image : .staticText }
    override func accessibilityValue() -> Any? { column == .thumbnail || column == .rating ? nil : text }

    func showThumbnail(for item: LibraryGridItem, picture: CGImage?, asset: PHAsset?, photoLibrary: PhotoLibraryService?) {
        assetId = item.assetId
        // A reused cell lets go of the row it showed before.
        if let requestId { self.photoLibrary?.cancelThumbnailRequest(requestId) }
        requestId = nil
        self.photoLibrary = photoLibrary
        thumb.layer?.contents = nil
        setAccessibilityLabel(item.originalFilename)
        hasPicture = picture != nil || asset != nil
        if let picture {
            thumb.layer?.contents = picture
            return
        }
        guard let asset, let photoLibrary else { return }
        let id = item.assetId
        let scale = window?.backingScaleFactor ?? 2
        requestId = photoLibrary.requestThumbnail(for: asset, targetSize: CGSize(width: 20 * scale, height: 20 * scale),
                                                  allowNetwork: false) { [weak self] image, _ in
            guard let self, self.assetId == id, let image else { return }
            self.thumb.layer?.contents = image.cgImage
        }
    }
}

/// The list's table: a right-click asks the coordinator for the photo menu.
final class MacLibraryTableView: NSTableView {
    var contextMenu: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = self.row(at: convert(event.locationInWindow, from: nil))
        return contextMenu?(row) ?? super.menu(for: event)
    }
}
