import Photos
import SwiftUI

/// What opens a culling pass on the Mac (FS-18.02 §7): the photos in
/// capture order, where to start, and the place they came from.
struct MacCullRequest: Identifiable, Equatable {
    let id = UUID()
    /// Ordered and opened off the main actor (`make`): a pass can be 45k photos.
    let session: CullSession
    /// Each id's place in the pass.
    let positions: [String: Int]
    /// The place's name, for the title (`Culling · Kyoto`) and Back's tooltip.
    let placeTitle: String
    /// The grid's rows of the pass's photos: the exposure line under the loupe.
    let items: [String: LibraryGridItem]
    /// The index's camera, lens and stars of the pass's photos as the pass
    /// opened — a snapshot, so a mark elsewhere never redraws 45k tiles.
    let indexed: [String: LibraryTableQueries.Details]

    /// `rows` in capture order, opened at `startId` (Cull From Here) or the
    /// first photo with no flag in `flagged`. Pure: run it off the main actor.
    nonisolated static func make(rows: [LibraryGridItem], startId: String?, flagged: Set<String>,
                                 details: [String: LibraryTableQueries.Details], placeTitle: String) -> MacCullRequest {
        let session = CullSession.start(items: rows.map { CullSession.Item(id: $0.assetId, captureDate: $0.creationDateValue) },
                                         flagged: { flagged.contains($0) }, startId: startId)
        var positions: [String: Int] = [:]
        positions.reserveCapacity(session.ids.count)
        for (index, id) in session.ids.enumerated() { positions[id] = index }
        var indexed: [String: LibraryTableQueries.Details] = [:]
        for id in session.ids { if let found = details[id] { indexed[id] = found } }
        return MacCullRequest(session: session, positions: positions, placeTitle: placeTitle,
                              items: Dictionary(rows.map { ($0.assetId, $0) }, uniquingKeysWith: { first, _ in first }),
                              indexed: indexed)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Show ▾: which photos the pass visits — the grid and ← → both.
enum MacCullShow: String, CaseIterable, Identifiable {
    case all, unflagged, picks, rejected
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All", comment: "Mac culling: Show ▾ every photo of the pass")
        case .unflagged: MarkCopy.unflaggedFilter
        case .picks: MarkCopy.picksFilter
        case .rejected: MarkCopy.rejectedFilter
        }
    }

    func shows(_ flag: PhotoFlag?) -> Bool {
        switch self {
        case .all: true
        case .unflagged: flag == nil
        case .picks: flag == .pick
        case .rejected: flag == .reject
        }
    }
}

/// The pass (FS-01.12b, Mac tier D): one photo at a time in capture order.
/// Marks go to `PhotoMarks` one after another; the screen shows each mark
/// and moves on at once, and never waits for a write.
@MainActor
@Observable
final class MacCullModel {
    private(set) var session: CullSession
    /// The photos Show ▾ lets through, in pass order, and their places.
    private(set) var shownIds: [String] = []
    @ObservationIgnored private var shownPositions: [Int] = []
    private(set) var summary: CullSummary
    private(set) var rejectedIds: [String] = []
    /// Bumped when the Rejected change: Move N Rejected… reads its plan again.
    private(set) var rejectedGeneration = 0
    var show: MacCullShow = .all {
        didSet {
            refresh()
            showFirstIfHidden()
        }
    }
    /// The last mark could be taken back (Undo is off when not).
    private(set) var canUndo = false

    @ObservationIgnored let marks: PhotoMarks
    @ObservationIgnored let request: MacCullRequest
    /// Told which photos a write touched: the window's tiles and list follow.
    @ObservationIgnored var onChanged: ([String]) -> Void = { _ in }
    /// Flags set in this pass whose write has not landed yet: what the
    /// screen shows meanwhile (`nil` inside = cleared).
    @ObservationIgnored private var pendingFlags: [String: PhotoFlag?] = [:]
    /// Photos the pass had that left the library (moved to the Trash).
    @ObservationIgnored private var removed: Set<String> = []
    /// Writes, one after another: `P P X` lands in that order.
    @ObservationIgnored private var chain: Task<Void, Never>?
    /// Each mark of the pass, newest last: where it was set and the write
    /// that answers what it changed.
    @ObservationIgnored private var history: [Mark] = []

    private struct Mark {
        let index: Int
        let id: String
        /// For a flag: what it was before, shown again at once on undo.
        let flagBefore: PhotoFlag??
        let write: Task<MarkChange, Never>
    }

    init(request: MacCullRequest, marks: PhotoMarks) {
        self.marks = marks
        self.request = request
        self.session = request.session
        self.summary = CullSummary(ids: [], flag: { _ in nil })
        refresh()
    }

    var currentId: String? { session.currentId }

    /// The photo on screen is one Show ▾ lets through (else the loupe is empty).
    var isCurrentShown: Bool { shownPositions.binarySearch(session.index) != nil }

    /// The photo's place in the pass, 1-based (the tile's number).
    func number(of id: String) -> Int { (request.positions[id] ?? 0) + 1 }

    /// `Photo 37` of the counts: its place among the photos still in the library.
    var currentNumber: Int { session.index + 1 - removed.lazy.filter { (self.request.positions[$0] ?? .max) < self.session.index }.count }

    func flag(of id: String) -> PhotoFlag? {
        if let pending = pendingFlags[id] { return pending }
        return marks.flag(for: id)
    }

    /// A photo's stars and flag as the pass shows them: this session's
    /// writes, else the index as the pass opened (Photos' own stars
    /// included). Reads `version`, so a view redraws on a mark.
    func marks(for id: String) -> PhotoMarkSummary {
        _ = marks.version
        let summary = marks.summary(for: id, photosRating: request.indexed[id]?.rating)
        return PhotoMarkSummary(rating: summary.rating, flag: flag(of: id))
    }

    /// The counts, the shown photos and the Rejected, in one pass over the
    /// ids: on a change of marks or Show, never per frame.
    func refresh() {
        let show = show
        var shown: [String] = []
        var positions: [Int] = []
        var rejected: [String] = []
        var live: [String] = []
        live.reserveCapacity(session.ids.count)
        for (index, id) in session.ids.enumerated() where !removed.contains(id) {
            live.append(id)
            let flag = flag(of: id)
            if show.shows(flag) { shown.append(id); positions.append(index) }
            if flag == .reject { rejected.append(id) }
        }
        summary = CullSummary(ids: live, flag: flag(of:))
        // The grid diffs its ids only when the set really changed (a star changes none).
        if shown != shownIds { shownIds = shown }
        shownPositions = positions
        if rejected != rejectedIds {
            rejectedIds = rejected
            rejectedGeneration += 1
        }
    }

    private func showFirstIfHidden() {
        guard !isCurrentShown else { return }
        if let next = shownPositions.first(where: { $0 > session.index }) ?? shownPositions.last { session.move(to: next) }
    }

    func move(to id: String) {
        guard let index = request.positions[id] else { return }
        session.move(to: index)
    }

    /// ← →: the next or previous photo Show lets through; false at an end.
    @discardableResult
    func step(_ delta: Int) -> Bool {
        guard let next = neighbour(of: session.index, delta) else { return false }
        session.move(to: next)
        return true
    }

    /// The nearest shown place after (or before) `index`: a binary search,
    /// so a key repeat over 45k photos costs nothing.
    private func neighbour(of index: Int, _ delta: Int) -> Int? {
        let insertion = shownPositions.insertionIndex(of: index)
        if delta > 0 {
            let at = insertion < shownPositions.count && shownPositions[insertion] == index ? insertion + 1 : insertion
            return at < shownPositions.count ? shownPositions[at] : nil
        }
        return insertion > 0 ? shownPositions[insertion - 1] : nil
    }

    /// A mark on the photo on screen. A flag moves on when Advance After is
    /// on (FS-01.12b §5); stars stay, the second pass rates photo by photo.
    /// On the last photo it stays: the counts are in the title already.
    func apply(_ action: MarkKeyAction, advances: Bool, undoManager: UndoManager?) {
        guard let id = session.currentId, isCurrentShown else { NSSound.beep(); return }
        let index = session.index
        var flagBefore: PhotoFlag?? = nil
        if case .flag(let flag) = action {
            flagBefore = .some(self.flag(of: id))
            pendingFlags[id] = .some(flag)
            refresh()
        }
        let marks = marks
        let previous = chain
        let write = Task { @MainActor [weak self] in
            await previous?.value
            // Moved to the Trash while the write waited: no mark row for a photo that is gone.
            if self?.removed.contains(id) == true { return MarkChange(kind: .flag(previous: [:])) }
            return await marks.apply(action, to: [id])
        }
        chain = Task { @MainActor [weak self] in
            _ = await write.value
            guard let self else { return }
            if case .flag(let flag) = action, self.pendingFlags[id] == .some(flag) { self.pendingFlags[id] = nil }
            self.onChanged([id])
        }
        history.append(Mark(index: index, id: id, flagBefore: flagBefore, write: write))
        canUndo = true
        // NSUndoManager runs handlers on the thread that undoes: the main one (menu, ⌘Z, the button).
        undoManager?.registerUndo(withTarget: self) { model in MainActor.assumeIsolated { model.undoLast() } }
        undoManager?.setActionName(String(localized: "Mark", comment: "Mac culling: Edit › Undo Mark"))
        if case .flag = action, advances {
            if let next = neighbour(of: index, 1) {
                session.move(to: next)
            } else {
                // The end of the pass: nothing to move on to (the counts are in the title).
                NSSound.beep()
            }
        }
        // The photo left Show's filter (Unflagged, then P): on to the next it lets through.
        showFirstIfHidden()
    }

    /// Takes the last mark back and returns to its photo (FS-01.12b AC-1).
    /// Edit › Undo, ⌘Z and the toolbar's Undo all come here through the
    /// window's undo manager, which keeps the menu's Undo honest.
    func undoLast() {
        guard let step = history.popLast() else { return }
        canUndo = !history.isEmpty
        session.move(to: step.index)
        // The old flag shows at once, so a filtered Show keeps the photo the undo returned to.
        if let before = step.flagBefore {
            pendingFlags[step.id] = .some(before)
            refresh()
        }
        let marks = marks
        let previous = chain
        chain = Task { @MainActor [weak self] in
            await previous?.value
            let change = await step.write.value
            await marks.undo(change)
            if let before = step.flagBefore, self?.pendingFlags[step.id] == .some(before) { self?.pendingFlags[step.id] = nil }
            self?.onChanged(change.assetIds)
        }
    }

    /// Photos moved to the Trash from the pass leave it: counts, grid, ← →.
    /// Its undo goes too — nothing to give back to a photo that is gone.
    func prune(_ ids: Set<String>, undoManager: UndoManager?) {
        let mine = ids.filter { request.positions[$0] != nil }
        guard !mine.isEmpty else { return }
        removed.formUnion(mine)
        end(undoManager: undoManager)
        refresh()
        showFirstIfHidden()
    }

    /// The pass is closed: its undo goes with it.
    func end(undoManager: UndoManager?) {
        undoManager?.removeAllActions(withTarget: self)
        history = []
        canUndo = false
    }
}

private extension Array where Element == Int {
    /// The first place whose value is not below `value` (sorted ascending).
    func insertionIndex(of value: Int) -> Int {
        var low = 0, high = count
        while low < high {
            let middle = (low + high) / 2
            if self[middle] < value { low = middle + 1 } else { high = middle }
        }
        return low
    }

    func binarySearch(_ value: Int) -> Int? {
        let at = insertionIndex(of: value)
        return at < count && self[at] == value ? at : nil
    }
}

/// The culling page (board `MAC_Cull`, FS-18.02 §7): a page of the Library
/// window, not a window of its own. Loupe on the left, the pass's grid of
/// 360 on the right, the shortcut strip under the loupe; always dark.
struct MacCullPage: View {
    let request: MacCullRequest
    let menu: MacPhotoMenu?
    var picture: ((String) -> CGImage?)?
    var asset: (String) -> PHAsset?
    /// The library's last removal: photos moved to the Trash leave the pass.
    var removal: PhotoGridRemoval?
    /// Back: the photo the pass was on, for the grid to select.
    let close: (String?) -> Void

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.undoManager) private var undoManager
    @State private var model: MacCullModel?
    @State private var isGrid = false
    @State private var zoom: MacViewerZoom = .fit
    @AppStorage("macCullShowsShortcuts") private var showsShortcuts = true
    @AppStorage("macCullAdvancesAfter") private var advancesAfter = true
    /// What Move N Rejected… would do, read off the main actor.
    @State private var plan: MixedDeletionPlan?
    @FocusState private var hasKeys: Bool

    static let gridWidth: CGFloat = 360

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                MacTheme.Editor.background
            }
        }
        .background(MacTheme.Editor.background)
        .preferredColorScheme(.dark)
        .task {
            guard model == nil else { return }
            let made = MacCullModel(request: request, marks: dependencies.photoMarks)
            made.onChanged = { [menu] ids in menu?.marksChanged(ids) }
            model = made
        }
        .onDisappear { model?.end(undoManager: undoManager) }
    }

    @ViewBuilder
    private func content(_ model: MacCullModel) -> some View {
        HStack(spacing: 0) {
            if !isGrid {
                VStack(spacing: 0) {
                    loupe(model)
                    if showsShortcuts { MacCullShortcutStrip(advancesAfter: $advancesAfter, hide: { showsShortcuts = false }) }
                }
                MacTheme.Editor.hairline.frame(width: 1)
            }
            MacCullGrid(model: model, isWide: isGrid, picture: picture, open: { id in
                model.move(to: id)
                if isGrid { isGrid = false }
                hasKeys = true
            })
            // Its closures change with every window redraw; the grid itself follows the model.
            .equatable()
            .frame(width: isGrid ? nil : Self.gridWidth)
            .frame(maxWidth: isGrid ? .infinity : nil)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeys)
        .onAppear { hasKeys = true }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            if !model.step(press.key == .leftArrow ? -1 : 1), press.phase == .down { NSSound.beep() }
            return .handled
        }
        .onKeyPress(.escape) {
            if isGrid { isGrid = false } else { close(model.currentId) }
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            guard press.modifiers.isEmpty, let key = press.characters.first else { return .ignored }
            switch key {
            case "z": zoom = zoom == .fit ? .actual : .fit; return .handled
            case "g": isGrid.toggle(); return .handled
            default:
                // Key-down only: a held key marks once, not thirty times a second.
                guard let action = MarkKeyCommand.action(for: key) else { return .ignored }
                mark(model, action)
                return .handled
            }
        }
        .onChange(of: dependencies.photoMarks.version) { model.refresh() }
        .onChange(of: removal) { _, removal in if let removal { model.prune(removal.assetIds, undoManager: undoManager) } }
        .task(id: model.rejectedGeneration) { await readPlan(model.rejectedIds) }
        .navigationTitle(String(localized: "Culling · \(request.placeTitle)", comment: "Mac culling: window title, the place being culled"))
        .navigationSubtitle(subtitle(model))
        .toolbar { toolbar(model) }
        .focusedSceneValue(\.macCull, MacCullTarget(
            mark: { mark(model, $0) },
            moveRejected: { moveRejected(model) },
            showsShortcuts: $showsShortcuts))
    }

    private func loupe(_ model: MacCullModel) -> some View {
        VStack(spacing: 0) {
            if let id = model.currentId, model.isCurrentShown {
                MacViewerPhoto(id: id, zoom: zoom, picture: picture, asset: asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .simultaneousGesture(TapGesture().onEnded { hasKeys = true })
                MacCullInfoLine(id: id, marks: model.marks(for: id), item: request.items[id], details: request.indexed[id])
            } else {
                ContentUnavailableView {
                    Label(model.show == .unflagged ? String(localized: "Every Photo Is Flagged", comment: "Mac culling: the pass is done under Show Unflagged")
                                                   : String(localized: "No Photos", comment: "Mac culling: Show ▾ lets none through"),
                          systemImage: model.show == .unflagged ? "checkmark.circle" : "photo.on.rectangle")
                } description: {
                    Text(model.show == .unflagged
                         ? String(localized: "\(model.summary.picks) picks · \(model.summary.rejected) rejected.", comment: "Mac culling: done, the counts")
                         : String(localized: "No photo in this pass is \(model.show.title.lowercased()).", comment: "Mac culling: Show ▾ lets no photo through"))
                } actions: {
                    Button(String(localized: "Show All", comment: "Mac culling: back to every photo of the pass")) { model.show = .all }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// `Photo 37 of 240 · 52 picks · 120 rejected · 68 unflagged`.
    private func subtitle(_ model: MacCullModel) -> String {
        let summary = model.summary
        let position = String(localized: "Photo \(model.currentNumber) of \(summary.total)",
                              comment: "Mac culling subtitle: where the pass stands")
        let counts = String(localized: "\(summary.picks) picks · \(summary.rejected) rejected · \(summary.unflagged) unflagged",
                            comment: "Mac culling subtitle: the pass's counts")
        return position + " · " + counts
    }

    @ToolbarContentBuilder
    private func toolbar(_ model: MacCullModel) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { close(model.currentId) } label: { Label(String(localized: "Back", comment: "Mac culling: back to the place"), systemImage: "chevron.left") }
                .help(String(localized: "Back to \(request.placeTitle) (Esc)", comment: "Mac culling: Back's tooltip"))
        }
        ToolbarItem(placement: .principal) {
            Picker(String(localized: "View", comment: "Mac culling: Loupe or Grid"), selection: $isGrid) {
                Text("Loupe", comment: "Mac culling view: one photo large").tag(false)
                Text("Grid", comment: "Mac culling view: the pass as a grid").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 136)
            .help(String(localized: "Loupe or Grid (G)", comment: "Mac culling: view picker tooltip"))
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                // The same marks as the keys (P X 1–5), state shown on the glyphs.
                let marks = model.currentId.map { model.marks(for: $0) } ?? PhotoMarkSummary(rating: 0, flag: nil)
                Button { mark(model, .flag(.reject)) } label: {
                    Label(MarkCopy.reject, systemImage: marks.flag == .reject ? "xmark.circle.fill" : "xmark.circle")
                }
                .help(String(localized: "Reject (X)", comment: "Mac culling toolbar tooltip"))
                ForEach(1...5, id: \.self) { stars in
                    Button { mark(model, .rate(stars)) } label: {
                        Label(stars == 1 ? String(localized: "1 Star", comment: "Mac culling toolbar: one star")
                                         : String(localized: "\(stars) Stars", comment: "Mac culling toolbar: n stars (2–5)"),
                              systemImage: stars <= marks.rating ? "star.fill" : "star")
                    }
                    .help(String(localized: "\(stars) Stars (\(stars))", comment: "Mac culling toolbar tooltip: n stars and its key"))
                }
                Button { mark(model, .flag(.pick)) } label: {
                    Label(MarkCopy.pick, systemImage: marks.flag == .pick ? "flag.fill" : "flag")
                }
                .help(String(localized: "Pick (P)", comment: "Mac culling toolbar tooltip"))
            }
            .disabled(!model.isCurrentShown)
            Menu {
                Picker(String(localized: "Show", comment: "Mac culling: which photos the pass visits"), selection: Binding(get: { model.show }, set: { model.show = $0 })) {
                    ForEach(MacCullShow.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Text("Show \(model.show.title)", comment: "Mac culling toolbar: Show ▾ and its choice")
            }
            .help(String(localized: "Which photos the pass shows", comment: "Mac culling: Show ▾ tooltip"))
            Button {
                // Through the manager, so Edit › Undo loses the same entry.
                if let undoManager, undoManager.canUndo { undoManager.undo() } else { model.undoLast() }
            } label: {
                Label(String(localized: "Undo", comment: "Mac culling: undo the last mark"), systemImage: "arrow.uturn.backward")
            }
            .disabled(!model.canUndo)
            .help(String(localized: "Undo the last mark (⌘Z)", comment: "Mac culling: Undo tooltip"))
            // A text button, never the prominent one: the prominent button is never a delete (01 §3).
            Button { moveRejected(model) } label: {
                // Red words on the toolbar's glass, never a red fill.
                Text(rejectedTitle(model)).foregroundStyle(model.rejectedIds.isEmpty ? Color.secondary : MacTheme.redText)
            }
                .disabled(model.rejectedIds.isEmpty)
                .help(String(localized: "\(rejectedTitle(model)) (⌘⌫)", comment: "Mac culling: Move N Rejected… tooltip"))
        }
    }

    /// `Move 120 Rejected…`, named by where the files go (01b §1, AC-21).
    private func rejectedTitle(_ model: MacCullModel) -> String {
        // None yet: the Mac's usual verb, dimmed (FS-18.02 §7).
        if model.rejectedIds.isEmpty { return String(localized: "Move 0 Rejected…", comment: "Mac culling: Move N Rejected… with none rejected") }
        if let plan, plan.count == model.rejectedIds.count { return plan.commandName }
        var fallback = MixedDeletionPlan(photos: model.rejectedIds.map { _ in [.trash] }, selection: .rejected)
        fallback.trashName = MixedDeletionPlan.macTrashName
        return fallback.commandName
    }

    private func mark(_ model: MacCullModel, _ action: MarkKeyAction) {
        model.apply(action, advances: advancesAfter, undoManager: undoManager)
    }

    private func moveRejected(_ model: MacCullModel) {
        guard !model.rejectedIds.isEmpty, let menu else { NSSound.beep(); return }
        menu.moveToTrash(model.rejectedIds, selection: .rejected)
    }

    /// Which way the Rejected would go, for the button's verb: off the main actor.
    private func readPlan(_ ids: [String]) async {
        guard !ids.isEmpty else { plan = nil; return }
        // A burst of X keys reads once, after the last.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let queries = dependencies.sourceDeletion.makeQueries()
        let read = await Task.detached(priority: .utility) { try? queries.plan(photoIds: ids, selection: .rejected) }.value
        guard !Task.isCancelled, var read else { return }
        read.trashName = MixedDeletionPlan.macTrashName
        plan = read
    }
}

/// The culling page's way into the menu bar: Image's marks and Move to
/// Trash (⌘⌫) act on the pass; View shows or hides the shortcut strip.
struct MacCullTarget {
    var mark: (MarkKeyAction) -> Void
    var moveRejected: () -> Void
    var showsShortcuts: Binding<Bool>
}

extension FocusedValues {
    @Entry var macCull: MacCullTarget?
}

/// Under the loupe: what the photo was taken with, and its marks
/// (`Sony A7 IV · FE 24-70mm F2.8 GM II · 50 mm · f/2.8 · 1/500 s · ISO 200 · Sep 28, 8:32 PM · ★★★ · Unflagged`).
struct MacCullInfoLine: View {
    let id: String
    let marks: PhotoMarkSummary
    let item: LibraryGridItem?
    let details: LibraryTableQueries.Details?

    var body: some View {
        let facts = MetadataFormatter.metadataLine([
            details?.camera,
            details?.lens,
            item?.focalLength.flatMap(MetadataFormatter.focalLength),
            item?.aperture.flatMap(MetadataFormatter.aperture),
            item?.shutterSpeedDisplay,
            item?.iso.flatMap(MetadataFormatter.iso),
            item?.creationDateValue?.formatted(date: .abbreviated, time: .shortened),
        ])
        HStack(spacing: 6) {
            if let facts { Text(facts + " ·").lineLimit(1).truncationMode(.middle) }
            Text(markLine)
                .foregroundStyle(MacTheme.Editor.label)
                .accessibilityLabel(MarkCopy.accessibility(marks) ?? markLine)
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(MacTheme.Editor.secondaryText)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
    }

    /// `★★★☆☆ · Unflagged`.
    private var markLine: String {
        let flag = marks.flag.map { MarkCopy.flagWord($0) } ?? MarkCopy.unflaggedFilter
        let stars = MarkCopy.stars(marks.rating)
        return stars.isEmpty ? flag : stars + " · " + flag
    }
}

/// The key legend under the loupe (board): text, the Advance After switch
/// and Hide only — no delete in the bottom 60pt (MAC_STYLE).
struct MacCullShortcutStrip: View {
    @Binding var advancesAfter: Bool
    let hide: () -> Void

    private static let keys: [(String, String)] = [
        ("← →", String(localized: "Previous / Next", comment: "Mac culling shortcut strip")),
        ("0–5", String(localized: "Rating", comment: "Mac culling shortcut strip")),
        ("P", MarkCopy.pick),
        ("X", MarkCopy.reject),
        ("U", MarkCopy.clearFlag),
        ("Z", String(localized: "Zoom", comment: "Mac culling shortcut strip")),
        ("⌘Z", String(localized: "Undo", comment: "Mac culling shortcut strip")),
        ("G", String(localized: "Grid", comment: "Mac culling shortcut strip")),
        ("Esc", String(localized: "Back", comment: "Mac culling shortcut strip")),
    ]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(Self.keys)
            // A narrow window keeps the marks and drops the rest of the legend.
            strip(Array(Self.keys.prefix(5)))
            strip([])
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(MacTheme.Editor.panelSolid)
        .overlay(alignment: .top) { MacTheme.Editor.hairline.frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Keyboard shortcuts", comment: "Mac culling: the shortcut strip"))
    }

    private func strip(_ keys: [(String, String)]) -> some View {
        HStack(spacing: 16) {
            ForEach(keys, id: \.0) { key in
                HStack(spacing: 6) {
                    Text(key.0)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .foregroundStyle(MacTheme.Editor.label)
                        .background(MacTheme.Editor.keycapFill, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(MacTheme.Editor.keycapStroke))
                    Text(key.1).font(.system(size: 12)).foregroundStyle(MacTheme.Editor.secondaryText)
                }
                .fixedSize()
                .accessibilityElement(children: .combine)
            }
            if !keys.isEmpty { MacTheme.Editor.hairline.frame(width: 1, height: 20) }
            Toggle(String(localized: "Advance After", comment: "Mac culling: move on after a flag"), isOn: $advancesAfter)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(MacTheme.accentFill)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Editor.secondaryText)
                .fixedSize()
                .help(String(localized: "Move to the next photo after a flag", comment: "Mac culling: Advance After tooltip"))
            MacTheme.Editor.hairline.frame(width: 1, height: 20)
            Button(action: hide) {
                Text("Hide", comment: "Mac culling: hide the shortcut strip")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.Editor.label)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(MacTheme.fill, in: RoundedRectangle(cornerRadius: 6))
            }
                .buttonStyle(.plain)
                .help(String(localized: "Hide Shortcut Strip (remembered; View › Show Shortcut Strip brings it back)",
                             comment: "Mac culling: Hide's tooltip"))
        }
        .padding(.horizontal, 16)
    }
}

/// The pass as a grid (board): 108pt tiles, 4pt apart, the photo on
/// screen ringed white, rejected ones dimmed; its count under it.
struct MacCullGrid: View, Equatable {
    let model: MacCullModel
    /// G: the grid has the page; otherwise the 360 column beside the loupe.
    let isWide: Bool
    var picture: ((String) -> CGImage?)?
    let open: (String) -> Void

    static let tile: CGFloat = 108

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.isWide == rhs.isWide
    }

    var body: some View {
        let ids = model.shownIds
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("^[\(ids.count) photo](inflect: true)", comment: "Mac culling grid header: photos Show ▾ lets through")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MacTheme.Editor.secondaryText)
                Spacer(minLength: 0)
                Text("Capture Time", comment: "Mac culling grid header: the pass's fixed order, oldest first")
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.Editor.secondaryText)
                    .help(String(localized: "A pass goes through the shoot as it happened, oldest first",
                                 comment: "Mac culling: why the order is fixed"))
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
            ScrollViewReader { proxy in
                ScrollView {
                    // Beside the loupe, the board's three columns; with the page, as many as fit.
                    LazyVGrid(columns: isWide ? [GridItem(.adaptive(minimum: Self.tile, maximum: Self.tile), spacing: 4)]
                                              : Array(repeating: GridItem(.fixed(Self.tile), spacing: 4), count: 3),
                              alignment: .leading, spacing: 4) {
                        ForEach(ids, id: \.self) { id in
                            MacCullTile(id: id, number: model.number(of: id), marks: model.marks(for: id),
                                        isCurrent: id == model.currentId, picture: picture)
                                .onTapGesture(count: 2) { open(id) }
                                .simultaneousGesture(TapGesture().onEnded { model.move(to: id) })
                                .id(id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .onAppear { if let id = model.currentId { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: model.currentId) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            HStack {
                Text("\(model.summary.rejected) rejected in this pass", comment: "Mac culling grid footer")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MacTheme.Editor.secondaryText)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .overlay(alignment: .top) { MacTheme.Editor.hairline.frame(height: 1) }
        }
        .background(MacTheme.Editor.panel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Grid", comment: "Mac culling: the pass's grid"))
    }
}

struct MacCullTile: View {
    let id: String
    /// The photo's place in the pass, 1-based.
    let number: Int
    let marks: PhotoMarkSummary
    let isCurrent: Bool
    var picture: ((String) -> CGImage?)?
    @Environment(MacDependencies.self) private var dependencies
    @State private var image: CGImage?
    @State private var isCloud = false

    var body: some View {
        Rectangle().fill(MacTheme.fill)
            .overlay {
                if isCloud {
                    Image(systemName: "icloud.and.arrow.down").font(.system(size: 15)).foregroundStyle(MacTheme.Editor.secondaryText)
                } else if let image {
                    Image(decorative: image, scale: 2).resizable().scaledToFill()
                }
            }
            .frame(width: MacCullGrid.tile, height: MacCullGrid.tile)
            .clipped()
            .overlay { if marks.flag == .reject { MacTheme.Editor.rejectedShade } }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 4) {
                    if marks.flag == .pick { Image(systemName: "flag.fill") }
                    if marks.flag == .reject { Image(systemName: "xmark") }
                    if marks.rating > 0 { Text(MarkCopy.compactStars(marks.rating)) }
                }
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                .padding(.leading, 5)
                .padding(.bottom, 4)
            }
            .overlay(alignment: .topTrailing) {
                Text("\(number)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .padding(.trailing, 5)
                    .padding(.top, 4)
            }
            .overlay {
                Rectangle().strokeBorder(isCurrent ? Color.white : MacTheme.Editor.hairline, lineWidth: isCurrent ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .task(id: "\(id)-\(dependencies.cloudDownloads.finished.contains(id))") {
                isCloud = false
                // The asset is fetched off the main actor: a tile scrolling in never stalls a key.
                // A tile only flown past (fast scroll) asks for nothing.
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                let found = picture == nil
                    ? await Task.detached(priority: .utility) { PhotoLibraryService.fetchAssets(ids: [id]).first }.value
                    : nil
                guard !Task.isCancelled else { return }
                await MacThumbnail.load(id, side: MacCullGrid.tile, picture: picture, asset: { _ in found }, dependencies: dependencies,
                                        received: { image = $0 }, inCloud: { isCloud = true })
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }

    /// `Photo 37, 3 stars, Picked` (board).
    private var label: String {
        var parts = [String(localized: "Photo \(number)", comment: "Mac culling tile: its place in the pass")]
        if marks.rating > 0 { parts.append(MarkCopy.starsAccessibility(marks.rating)) }
        if let flag = marks.flag { parts.append(flag == .pick ? String(localized: "Picked", comment: "Mac culling tile: flag")
                                                             : String(localized: "Rejected", comment: "Mac culling tile: flag")) }
        return parts.joined(separator: ", ")
    }
}
