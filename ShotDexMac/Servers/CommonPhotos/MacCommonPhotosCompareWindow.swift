import GRDB
import ImageIO
import SwiftUI

/// What the index shows of one copy on a server source: its preview and the
/// capture date it read (FS-19.08 §6d). Nil when no source holds the copy,
/// or the index has not reached it.
enum MacCommonPhotosPreview {
    struct Indexed: Sendable {
        let image: CGImage?
        let captured: Date?
    }

    static func load(serverPath: String, sources: [(source: SourceStore.Source, connection: FileServer)],
                     database: AppDatabase, maxPixelSize: Int) async -> Indexed? {
        guard let holder = sources.first(where: { CommonPhotosSelection.contains($0.connection.folder, serverPath) }) else { return nil }
        let root = ServerUploadPath.normalizedFolder(holder.connection.folder)
        let relative = root.isEmpty ? serverPath : String(serverPath.dropFirst(root.count + 1))
        let key = FolderSourceIndexer.pathKey(relative)
        let sourceId = holder.source.id
        let found = try? await database.reader.read { db -> (copyId: String, captured: Int?)? in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT c.id, m.creationDate FROM photo_copies c LEFT JOIN photo_metadata m ON m.assetId = c.photoId
                WHERE c.sourceId = ? AND c.relativePathKey = ? AND c.missingSince IS NULL
                """, arguments: [sourceId, key]) else { return nil }
            return (row["id"], row["creationDate"])
        }
        guard let found = found ?? nil else { return nil }
        let url = FolderThumbnails.standard.url(copyId: found.copyId)
        let image = await Task.detached {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                                                                   kCGImageSourceCreateThumbnailFromImageAlways: true] as CFDictionary)
        }.value
        return Indexed(image: image, captured: found.captured.map { Date(timeIntervalSince1970: TimeInterval($0)) })
    }
}


/// The Compare window's state (FS-19.08 §6d): the sheet's scan, the row
/// shown, and what each side has loaded. One for the app; the sheet that
/// opens the window sets it, and clears it when it closes.
@MainActor
@Observable
final class MacCommonPhotosCompareModel {
    let scan: CommonPhotosScanModel
    let database: AppDatabase
    let sources: [(source: SourceStore.Source, connection: FileServer)]
    private(set) var compare: CommonPhotosCompare
    /// What the two sides of the row shown have loaded, by copy path; only
    /// those two are kept.
    private(set) var previews: [String: MacCommonPhotosPreview.Indexed] = [:]
    /// Sides of the row shown that the index has no picture of.
    private(set) var notIndexed: Set<String> = []
    var zoom = Zoom.fit

    enum Zoom: String, CaseIterable, Identifiable {
        case fit, actual
        var id: Self { self }
    }

    /// The index's preview, 400 pixels on its long edge: 100% shows it at
    /// that size until the whole file is read (§6d, not indexed).
    static let previewPixels = FolderThumbnails.longEdge

    init(scan: CommonPhotosScanModel, database: AppDatabase,
         sources: [(source: SourceStore.Source, connection: FileServer)], showing rowId: String) {
        self.scan = scan
        self.database = database
        self.sources = sources
        compare = CommonPhotosCompare(rowIds: scan.rows.map(\.id), showing: rowId)
    }

    var row: CommonPhotosScanModel.Row? { compare.currentId.flatMap { id in scan.rows.first { $0.id == id } } }

    var copies: [CommonPhotosCompare.Copy] {
        guard let id = compare.currentId, let photo = scan.photo(forRow: id) else { return [] }
        return CommonPhotosCompare.copies(of: photo, folders: scan.folders)
    }

    /// The two sides: the first folder's copy, and the one the popup picks.
    var sides: [CommonPhotosCompare.Copy] {
        let all = copies
        guard all.count > 1 else { return all }
        return [all[0], all[min(compare.rightCopy, all.count - 1)]]
    }

    /// What `loadSides` runs for: the row and the right side picked.
    var sidesKey: String { "\(compare.currentId ?? "")|\(compare.rightCopy)" }

    /// The row can be checked or unchecked: a Copy skips what is already
    /// in the destination, so that row is no choice (as in the sheet).
    var canChoose: Bool {
        guard let row else { return false }
        if case .alreadyThere? = row.landing, scan.action == .copy { return false }
        return true
    }

    func show(_ rowId: String) {
        compare = CommonPhotosCompare(rowIds: scan.rows.map(\.id), showing: rowId)
    }

    func next() { compare.next() }
    func previous() { compare.previous() }

    func pickRight(_ index: Int) { compare.rightCopy = index }

    /// The list under the window changed: follow it.
    func listChanged() { compare.update(rowIds: scan.rows.map(\.id)) }

    func setIncluded(_ included: Bool) {
        guard canChoose, let id = compare.currentId else { return }
        scan.setIncluded(included, rows: [id])
    }

    /// Loads the two sides of the row shown and lets go of every other.
    /// A cancelled load (the row changed) writes nothing.
    func loadSides() async {
        let paths = Set(sides.map(\.path))
        previews = previews.filter { paths.contains($0.key) }
        notIndexed = notIndexed.intersection(paths)
        for side in sides where previews[side.path] == nil && !notIndexed.contains(side.path) {
            let indexed = await MacCommonPhotosPreview.load(serverPath: side.path, sources: sources, database: database,
                                                            maxPixelSize: Self.previewPixels)
            guard !Task.isCancelled else { return }
            if let indexed, indexed.image != nil {
                previews[side.path] = indexed
            } else {
                notIndexed.insert(side.path)
            }
        }
    }
}

/// FS-19.08 §6d, board `MAC_CommonPhotosCompare`: two copies of a Same photo
/// side by side. Tier D: always dark. ↑↓ step through the rows (←→ too when
/// the picture fits), Esc closes; the bar below says the SHA-256 they share.
struct MacCommonPhotosCompareWindow: View {
    static let id = "commonPhotosCompare"
    static let size = CGSize(width: 1180, height: 760)

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model = dependencies.commonPhotosCompare, let row = model.row {
                MacCommonPhotosCompareContent(model: model, row: row, close: { dismiss() })
            } else {
                ContentUnavailableView(String(localized: "Nothing to Compare", comment: "Common photos compare window: no row"),
                                       systemImage: "rectangle.split.2x1",
                                       description: Text("Choose a photo in Find Common Photos and press Space.",
                                                         comment: "Common photos compare window: how to open it"))
            }
        }
        .frame(minWidth: 860, idealWidth: Self.size.width, minHeight: 560, idealHeight: Self.size.height)
        .background(MacTheme.Editor.background)
        .preferredColorScheme(.dark)
        .tint(MacTheme.Editor.accent)
        // Out here, so it runs when the rows empty too.
        .onChange(of: dependencies.commonPhotosCompare?.scan.rows.map(\.id)) { dependencies.commonPhotosCompare?.listChanged() }
        .onExitCommand { dismiss() }
    }
}

private struct MacCommonPhotosCompareContent: View {
    @Bindable var model: MacCommonPhotosCompareModel
    let row: CommonPhotosScanModel.Row
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                ForEach(Array(model.sides.enumerated()), id: \.offset) { index, side in
                    pane(side, isRight: index == 1)
                }
            }
            .background(MacTheme.Editor.hairline)
            proofBar
        }
        .navigationTitle(String(localized: "Compare — \(row.name)", comment: "Common photos compare window title"))
        .navigationSubtitle(String(localized: "\(model.compare.position.index.formatted()) of \(model.compare.position.count.formatted())",
                                   comment: "Common photos compare window subtitle: which row"))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.previous() } label: { Image(systemName: "chevron.up") }
                    .keyboardShortcut(.upArrow, modifiers: [])
                    .help(String(localized: "Previous Row (↑)", comment: "Common photos compare: toolbar"))
                    .accessibilityLabel(String(localized: "Previous Row", comment: "Common photos compare: toolbar"))
                Button { model.next() } label: { Image(systemName: "chevron.down") }
                    .keyboardShortcut(.downArrow, modifiers: [])
                    .help(String(localized: "Next Row (↓)", comment: "Common photos compare: toolbar"))
                    .accessibilityLabel(String(localized: "Next Row", comment: "Common photos compare: toolbar"))
            }
            ToolbarItemGroup {
                Picker(String(localized: "Zoom", comment: "Common photos compare: zoom"), selection: $model.zoom) {
                    Text("Fit", comment: "Common photos compare: zoom to fit").tag(MacCommonPhotosCompareModel.Zoom.fit)
                        .help(String(localized: "Fit in each side", comment: "Common photos compare: zoom tooltip"))
                    Text("100%", comment: "Common photos compare: actual size").tag(MacCommonPhotosCompareModel.Zoom.actual)
                        .help(String(localized: "Actual size", comment: "Common photos compare: zoom tooltip"))
                }
                .pickerStyle(.segmented)
                Toggle(isOn: Binding(get: { row.isIncluded }, set: { model.setIncluded($0) })) {
                    Text(model.scan.action == .move
                         ? String(localized: "Include in Move", comment: "Common photos compare: the row's checkbox, Move")
                         : String(localized: "Include in Copy", comment: "Common photos compare: the row's checkbox, Copy"))
                }
                .toggleStyle(.checkbox)
                .disabled(!model.canChoose)
                .help(String(localized: "Unchecked: left out of this set from now on.", comment: "Common photos compare: checkbox tooltip"))
            }
        }
        .focusable()
        .focusEffectDisabled()
        // ←→ step too while the picture fits; at 100% they scroll it.
        .onKeyPress(.rightArrow) { guard model.zoom == .fit else { return .ignored }; model.next(); return .handled }
        .onKeyPress(.leftArrow) { guard model.zoom == .fit else { return .ignored }; model.previous(); return .handled }
        .task(id: model.sidesKey) { await model.loadSides() }
    }

    private func pane(_ side: CommonPhotosCompare.Copy, isRight: Bool) -> some View {
        VStack(spacing: 0) {
            ZStack {
                MacTheme.Editor.background
                if let image = model.previews[side.path]?.image {
                    let picture = Image(decorative: image, scale: 1)
                    if model.zoom == .fit {
                        picture.resizable().scaledToFit().padding(16)
                    } else {
                        ScrollView([.horizontal, .vertical]) { picture }
                    }
                } else if model.notIndexed.contains(side.path) {
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.title).foregroundStyle(MacTheme.Editor.secondaryText)
                        Text("No preview yet", comment: "Common photos compare: the copy is not in the index")
                            .foregroundStyle(MacTheme.Editor.secondaryText)
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(side.place), \(side.name)")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    if isRight, model.copies.count > 2 {
                        Picker(selection: Binding(get: { model.compare.rightCopy }, set: { model.pickRight($0) })) {
                            ForEach(Array(model.copies.enumerated().dropFirst()), id: \.offset) { index, copy in
                                Text(copy.place).tag(index)
                            }
                        } label: { EmptyView() }
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityLabel(String(localized: "Copy to Compare", comment: "Common photos compare: which copy the right side shows"))
                    } else {
                        Text(side.place).fontWeight(.semibold).lineLimit(1)
                    }
                    Text(side.name).foregroundStyle(MacTheme.Editor.secondaryText).lineLimit(1).truncationMode(.middle)
                }
                .font(.body)
                Text(meta(side)).font(.caption).foregroundStyle(MacTheme.Editor.secondaryText).monospacedDigit().lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 20)
            .background(MacTheme.Editor.panel)
        }
        .background(MacTheme.Editor.background)
    }

    /// "2.9 MB · Jun 1, 2025 at 4:12 PM · SHA-256 1c3e8a02".
    private func meta(_ side: CommonPhotosCompare.Copy) -> String {
        var parts = [side.size.formatted(.byteCount(style: .file))]
        if let date = model.previews[side.path]?.captured { parts.append(date.formatted(date: .abbreviated, time: .shortened)) }
        parts.append("SHA-256 " + String(row.sha256.prefix(8)))
        return parts.joined(separator: " · ")
    }

    /// Status only (MAC_STYLE: nothing actionable in the bottom 60pt).
    private var proofBar: some View {
        HStack(spacing: 12) {
            Label(String(localized: "Same bytes — SHA-256 matches", comment: "Common photos compare: the proof"),
                  systemImage: "checkmark")
                .foregroundStyle(.green)
                .fontWeight(.semibold)
            Text(row.sha256).font(.caption.monospaced()).foregroundStyle(MacTheme.Editor.secondaryText)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 0)
            Text("↑↓ next row · Esc close", comment: "Common photos compare: keys").font(.caption)
                .foregroundStyle(MacTheme.Editor.secondaryText)
        }
        .padding(.horizontal, 20)
        .frame(height: 40)
        .background(MacTheme.Editor.panel)
    }
}
