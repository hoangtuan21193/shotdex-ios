import Photos
import SwiftUI
import UIKit

/// UIKit-backed photo grid shared by every photo grid in the app — the SwiftUI
/// lazy grid could not survive this feature set at whole-library scale
/// (100k+ items): bottom-anchoring forced a full content-height estimate
/// (long black launch, tiles not rendering until first touch) and any column
/// change invalidated the entire lazy container (pinch lag, stale offsets
/// landing past the end of content).
///
/// UICollectionView is how Photos/Metapho do it:
/// - compositional layout: content size is row math, so opening anchored to
///   the bottom is O(1) — the grid renders instantly,
/// - pinch density via `UICollectionViewTransitionLayout` +
///   `startInteractiveTransition` — cells follow the fingers, UIKit
///   interpolates frames and content offset between the two layouts,
/// - `UICollectionViewDataSourcePrefetching` + `PHCachingImageManager`
///   prewarm thumbnails before they scroll on screen.
///
/// The SwiftUI-facing contract (flat photos array, flat-index callbacks,
/// `SwipeSelectEvent`) matches the old `DensityPhotoGrid`, so the screens'
/// selection/compare/delete logic is unchanged.
struct PhotoGridCollectionView<Item: PhotoGridDisplayable>: UIViewRepresentable {
    let photos: [Item]
    let assetProvider: (_ flatIndex: Int, _ item: Item) -> PHAsset?
    /// Sectioning + header contract: grid-grouped by date, one flat headerless
    /// section (non-date sorts), or screen-supplied groups.
    let sectionMode: PhotoGridSectionMode
    /// Library opens at the newest photos (bottom); albums open at the top.
    let anchorsBottom: Bool
    /// Bumped when the content is *replaced* (filter/sort/index run) —
    /// triggers reload + re-anchor. Count-only growth (album paging)
    /// reloads without re-anchoring.
    let contentVersion: Int
    /// Bumped when the same ordered list needs its visible tiles re-rendered
    /// (index run filled overlays) — reloads cells in place, never re-anchors,
    /// so the scroll position is preserved.
    let contentRefreshVersion: Int
    /// Bumped on Library-tab retap: scroll back to the newest photos.
    let jumpToNewestToken: Int
    @Binding var columnCount: Int
    let isSelecting: Bool
    let selectedIds: [String]
    /// Extra scrollable space under the grid (pre-iOS 26 floating chrome).
    let bottomInset: CGFloat
    let photoLibrary: PhotoLibraryService
    let onTap: (_ flatIndex: Int, _ item: Item) -> Void
    let onLongPress: (Item) -> Void
    let onSwipeEvent: (SwipeSelectEvent) -> Void
    /// Fired when cells near the end of the array display (album paging).
    let onNearEnd: () -> Void
    /// Fired on any user-initiated scroll (Library collapses the index panel).
    let onUserScroll: () -> Void
    /// Optional on-display badge lookup: a cell whose item carries no
    /// exposure fields asks for a fresh row when it becomes visible, so
    /// tiles indexed mid-run fill in lazily instead of the whole grid
    /// reloading per indexed photo. Nil (Album Detail) disables the lookup.
    var lazyMetadataProvider: ((String) async -> (any PhotoGridDisplayable)?)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let collectionView = GridCollectionView(
            frame: .zero,
            collectionViewLayout: coordinator.makeLayout(columns: columnCount)
        )
        // SwiftUI sizes the representable after creation — the bottom anchor
        // can only be applied once real bounds exist.
        collectionView.onFirstLayout = { [weak coordinator] in
            coordinator?.anchorAfterFirstLayout()
        }
        collectionView.backgroundColor = .systemBackground
        collectionView.contentInset.bottom = bottomInset
        collectionView.dataSource = coordinator
        collectionView.delegate = coordinator
        collectionView.prefetchDataSource = coordinator
        collectionView.register(PhotoGridCell.self, forCellWithReuseIdentifier: PhotoGridCell.reuseId)
        collectionView.register(
            UICollectionViewCell.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: Coordinator.headerReuseId
        )
        coordinator.collectionView = collectionView
        coordinator.installGestures(on: collectionView)
        coordinator.apply(self, isInitial: true)
        return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
        // Re-apply on change: the bottom inset grows in select mode (to clear
        // the full-width selection bar) and shrinks back on exit.
        if collectionView.contentInset.bottom != bottomInset {
            collectionView.contentInset.bottom = bottomInset
        }
        context.coordinator.apply(self, isInitial: false)
    }

    static func dismantleUIView(_ uiView: UICollectionView, coordinator: Coordinator) {
        coordinator.stopAllDetailPreheating()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource,
        UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching,
        UIGestureRecognizerDelegate {

        static var headerReuseId: String { "PhotoGridHeader" }

        var parent: PhotoGridCollectionView
        weak var collectionView: UICollectionView?

        /// Sections currently driving the layout/data source, header text
        /// already resolved. One titleless full-range section when flat.
        private var sections: [ResolvedSection] = []
        /// Last screen-supplied sections, so a section-only change is detected
        /// without the screen having to bump `contentVersion`.
        private var appliedCustomSections: [PhotoGridCustomSection] = []

        /// A section as the data source sees it. `title == nil` means the
        /// section draws no header.
        private struct ResolvedSection: Equatable {
            let range: Range<Int>
            let title: String?
        }
        private var appliedContentVersion: Int?
        private var appliedContentRefreshVersion: Int?
        /// List owners bump `contentVersion` for same-count identity/order
        /// changes. Album paging uses a stable version but changes count, so the
        /// coordinator only needs this scalar — never an O(n) id snapshot.
        private var appliedPhotoCount = 0
        private var appliedColumns = 0
        private var appliedJumpToken: Int?
        private var appliedSelecting = false
        /// Membership snapshot for O(1) cell configuration. Selection order is
        /// owned by the screen/bottom tray; the grid only needs membership.
        private var appliedSelectedIds: Set<String> = []
        /// Local-only, screen-sized detail renditions for cells currently on
        /// screen. Preheating before the tap avoids enlarging a grid thumbnail
        /// while the detail viewer waits for its first usable image.
        private final class DetailPreheatEntry {
            let asset: PHAsset
            var requestId: PHImageRequestID?
            var warmTask: Task<Void, Never>?

            init(asset: PHAsset) {
                self.asset = asset
            }
        }
        private var detailPreheatedByIndexPath: [IndexPath: DetailPreheatEntry] = [:]
        private let maximumDetailPreheatCount = 18

        // Pinch state
        private var transitionLayout: UICollectionViewTransitionLayout?
        private var transitionBaselineScale: CGFloat = 1
        private var transitionDelta = 0
        /// True from finish/cancel until UIKit's completion callback — no new
        /// interactive transition may start in that window (see handlePinch).
        private var isSettling = false

        // Swipe-select state
        private var swipeActivation = SwipeSelectionEngine.Activation.undecided
        /// Frozen once per gesture. Recomputing from the live selection would
        /// flip select→deselect after the first callback and make badges blink.
        private var swipeShouldSelect: Bool?
        private var swipeStartFlatIndex: Int?
        private var swipeLastFlatIndex: Int?
        /// Physical finger location in the window. Converted back into the
        /// collection's moving content coordinates on every auto-scroll frame.
        private var swipeWindowLocation: CGPoint?
        private var swipeAutoScrollDriver: GridDisplayLinkDriver?
        /// True while the long press that *entered* selection mode is still
        /// down and driving the range itself (see handleLongPress).
        private var isLongPressDragActive = false

        /// Settings display toggles, read once per change instead of five
        /// UserDefaults lookups per cell per (re)configure. Refreshing on the
        /// defaults notification also makes Settings toggles apply live.
        private var displayOptions = GridMetadataDisplayOptions.load()
        private var defaultsObserver: NSObjectProtocol?

        init(_ parent: PhotoGridCollectionView) {
            self.parent = parent
            super.init()
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let fresh = GridMetadataDisplayOptions.load()
                    guard fresh != self.displayOptions else { return }
                    self.displayOptions = fresh
                    if let collectionView = self.collectionView {
                        self.reconfigureVisibleCells(collectionView)
                    }
                }
            }
        }

        deinit {
            // Swift treats deinit as nonisolated even on an @MainActor UIKit
            // coordinator. UIViewRepresentable creates/destroys this object on
            // the main actor, so assert that isolation for display-link cleanup
            // instead of leaking an interrupted auto-scroll driver.
            MainActor.assumeIsolated {
                swipeAutoScrollDriver?.invalidate()
            }
            if let defaultsObserver {
                NotificationCenter.default.removeObserver(defaultsObserver)
            }
        }

        // MARK: Input diffing

        func apply(_ newParent: PhotoGridCollectionView, isInitial: Bool) {
            guard let collectionView else {
                parent = newParent
                return
            }

            let contentReplaced = newParent.contentVersion != appliedContentVersion
            // A replacement while the user is reading mid-grid (a photo imported
            // or deleted elsewhere) must not teleport them to the anchor end —
            // keep the tile they were looking at. Captured before `parent` and
            // the sections are swapped, so ids and frames are the on-screen ones.
            let preservedScroll = contentReplaced && !isInitial
                ? preservableScroll(collectionView)
                : nil

            parent = newParent
            let previousSelectedIds = appliedSelectedIds
            let newSelectedIds = Set(newParent.selectedIds)
            appliedSelectedIds = newSelectedIds
            // List owners make same-count identity/order changes explicit via
            // contentVersion; album paging/deletion changes count. This avoids
            // materializing every asset id on all SwiftUI update paths.
            let listChanged = newParent.photos.count != appliedPhotoCount
            let columnsChanged = newParent.columnCount != appliedColumns

            if columnsChanged, !isInitial, transitionLayout == nil {
                // External column change (other screen persisted a new
                // density) — swap without animation, cache is stale.
                parent.photoLibrary.stopCachingAllThumbnails()
                collectionView.setCollectionViewLayout(
                    makeLayout(columns: newParent.columnCount), animated: false
                )
            }
            appliedColumns = newParent.columnCount

            let refreshed = appliedContentRefreshVersion != nil
                && newParent.contentRefreshVersion != appliedContentRefreshVersion
            // Screen-supplied sections can change while the photo count and
            // contentVersion stay put (a delete that empties one year). One
            // entry per group, so comparing them per update is cheap.
            let newCustomSections = newParent.sectionMode.customSections
            let sectionsChanged = newCustomSections != appliedCustomSections
            appliedCustomSections = newCustomSections
            // Re-anchoring stays gated on `contentReplaced` — a section-only
            // change must reload in place, not jump the scroll position.
            if contentReplaced || listChanged || sectionsChanged || isInitial {
                rebuildSections()
                collectionView.reloadData()
                if contentReplaced || isInitial {
                    collectionView.layoutIfNeeded()
                    let restored = preservedScroll
                        .map { restoreScroll($0, in: collectionView) } ?? false
                    if !restored { anchor(collectionView) }
                }
                appliedContentVersion = newParent.contentVersion
                appliedPhotoCount = newParent.photos.count
            } else if refreshed {
                // Same list, overlays changed — re-render visible tiles in
                // place. No reloadData/anchor, so the scroll spot is kept.
                reconfigureVisibleCells(collectionView)
            }
            appliedContentRefreshVersion = newParent.contentRefreshVersion

            if let token = appliedJumpToken, token != newParent.jumpToNewestToken {
                anchor(collectionView)
            }
            appliedJumpToken = newParent.jumpToNewestToken

            let selectionModeChanged = newParent.isSelecting != appliedSelecting
            let changedSelectionIds = previousSelectedIds.symmetricDifference(newSelectedIds)
            if selectionModeChanged || !changedSelectionIds.isEmpty {
                appliedSelecting = newParent.isSelecting
                updateVisibleSelection(
                    collectionView,
                    changedIds: selectionModeChanged ? nil : changedSelectionIds
                )
            }
            // Pinch remains available in selection mode. It uses two touches
            // while swipe-select is capped at one, so selected ids can stay
            // intact while the user changes density.
            pinchRecognizer?.isEnabled = true
            swipeRecognizer?.isEnabled = newParent.isSelecting
            if !newParent.isSelecting, swipeActivation == .select {
                finishActiveSwipeSelection()
            }
        }

        /// Called by `GridCollectionView` the first time it lays out with
        /// real bounds — the anchor computed in `makeUIView` ran against a
        /// zero frame and would leave the grid at the top.
        func anchorAfterFirstLayout() {
            guard let collectionView else { return }
            collectionView.layoutIfNeeded()
            anchor(collectionView)
        }

        private func anchor(_ collectionView: UICollectionView) {
            guard parent.anchorsBottom else {
                collectionView.setContentOffset(
                    CGPoint(x: 0, y: -collectionView.adjustedContentInset.top), animated: false
                )
                return
            }
            let bottom = collectionView.collectionViewLayout.collectionViewContentSize.height
                - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
            collectionView.setContentOffset(
                CGPoint(x: 0, y: max(bottom, -collectionView.adjustedContentInset.top)),
                animated: false
            )
        }

        /// A scroll position expressed as a photo id plus that tile's offset
        /// relative to the top of the viewport, so it survives a `reloadData`
        /// even when the list shifted (photos added or removed at either end).
        private struct PreservedScroll {
            let assetId: String
            let offsetFromTileTop: CGFloat
        }

        /// The spot to restore after a content replacement, or nil when the grid
        /// should re-anchor instead: nothing visible to key off, or the user was
        /// already parked at the end the grid anchors to — that's where newly
        /// added photos land, and staying there is what they expect.
        private func preservableScroll(_ collectionView: UICollectionView) -> PreservedScroll? {
            guard !isNearAnchorEnd(collectionView) else { return nil }
            let layout = collectionView.collectionViewLayout
            for indexPath in collectionView.indexPathsForVisibleItems.sorted() {
                guard let flatIndex = flatIndex(for: indexPath),
                      let frame = layout.layoutAttributesForItem(at: indexPath)?.frame
                else { continue }
                return PreservedScroll(
                    assetId: parent.photos[flatIndex].assetId,
                    offsetFromTileTop: collectionView.contentOffset.y - frame.minY
                )
            }
            return nil
        }

        /// False when the anchor photo is gone from the new list (it was the
        /// deleted one) — the caller then falls back to the end anchor.
        private func restoreScroll(
            _ preserved: PreservedScroll, in collectionView: UICollectionView
        ) -> Bool {
            guard let flatIndex = parent.photos.firstIndex(
                where: { $0.assetId == preserved.assetId }
            ),
                let indexPath = indexPath(forFlatIndex: flatIndex),
                let frame = collectionView.collectionViewLayout
                    .layoutAttributesForItem(at: indexPath)?.frame
            else { return false }
            let minimum = -collectionView.adjustedContentInset.top
            let maximum = max(
                minimum,
                collectionView.collectionViewLayout.collectionViewContentSize.height
                    - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
            )
            let target = min(max(frame.minY + preserved.offsetFromTileTop, minimum), maximum)
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            return true
        }

        /// Within one screen height of the end the grid anchors to (bottom for
        /// Library, top for albums).
        private func isNearAnchorEnd(_ collectionView: UICollectionView) -> Bool {
            let height = collectionView.bounds.height
            guard height > 0 else { return true }
            guard parent.anchorsBottom else {
                return collectionView.contentOffset.y
                    + collectionView.adjustedContentInset.top <= height
            }
            let bottom = collectionView.collectionViewLayout.collectionViewContentSize.height
                - height + collectionView.adjustedContentInset.bottom
            return bottom - collectionView.contentOffset.y <= height
        }

        private func reconfigureVisibleCells(_ collectionView: UICollectionView) {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell,
                      let flatIndex = flatIndex(for: indexPath)
                else { continue }
                configure(cell, at: flatIndex)
            }
        }

        /// Updates only checkmark/border state. Re-running full `configure`
        /// during every swipe step cancels badge work and rewrites image-view
        /// state for all visible cells, which presents as thumbnail flicker.
        private func updateVisibleSelection(
            _ collectionView: UICollectionView,
            changedIds: Set<String>?
        ) {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell,
                      let flatIndex = flatIndex(for: indexPath)
                else { continue }
                let assetId = parent.photos[flatIndex].assetId
                guard changedIds?.contains(assetId) ?? true else { continue }
                cell.updateSelection(
                    isSelecting: parent.isSelecting,
                    isSelected: appliedSelectedIds.contains(assetId)
                )
            }
        }

        // MARK: Sections

        private func rebuildSections() {
            guard !parent.photos.isEmpty else {
                sections = []
                return
            }
            switch parent.sectionMode {
            case .flat:
                sections = [ResolvedSection(range: 0..<parent.photos.count, title: nil)]
            case .dates:
                let granularity = GridDensity.granularity(forColumns: parent.columnCount)
                sections = PhotoGridSectionBuilder.sections(
                    creationDates: parent.photos.map(\.creationDateValue),
                    granularity: granularity
                ).map {
                    ResolvedSection(
                        range: $0.range,
                        title: Self.dateTitle(for: $0.kind, granularity: granularity)
                    )
                }
            case .custom(let supplied):
                // The screen's sections and its photos arrive in the same
                // SwiftUI update, but clamp anyway: a momentarily stale pair
                // must degrade to fewer tiles, never to an item count that
                // indexes past the array.
                sections = supplied.compactMap { section in
                    let upper = min(section.range.upperBound, parent.photos.count)
                    guard section.range.lowerBound < upper else { return nil }
                    return ResolvedSection(
                        range: section.range.lowerBound..<upper, title: section.title
                    )
                }
            }
        }

        private func flatIndex(for indexPath: IndexPath) -> Int? {
            guard sections.indices.contains(indexPath.section) else { return nil }
            let flat = sections[indexPath.section].range.lowerBound + indexPath.item
            return parent.photos.indices.contains(flat) ? flat : nil
        }

        private func indexPath(forFlatIndex flatIndex: Int) -> IndexPath? {
            guard let section = sections.firstIndex(where: { $0.range.contains(flatIndex) })
            else { return nil }
            return IndexPath(
                item: flatIndex - sections[section].range.lowerBound, section: section
            )
        }

        private static func dateTitle(
            for kind: PhotoGridSection.Kind, granularity: PhotoGridDateGranularity
        ) -> String {
            switch kind {
            case .undated:
                return String(localized: "No Date")
            case .date(let date):
                return granularity == .day
                    ? FormatUtils.dayHeader(date)
                    : FormatUtils.monthHeader(date)
            }
        }

        // MARK: Layout

        /// Flow layout, not compositional: `UICollectionViewTransitionLayout`
        /// (the pinch mechanic) only supports flow-style layouts —
        /// `startInteractiveTransition` with a compositional layout returns
        /// the target layout unwrapped and crashes on `transitionProgress`.
        /// A uniform square grid needs nothing compositional anyway, and
        /// pinned date headers exist here too
        /// (`sectionHeadersPinToVisibleBounds`).
        func makeLayout(columns: Int) -> UICollectionViewFlowLayout {
            let layout = GridFlowLayout()
            layout.columns = GridDensity.clamped(columns)
            layout.minimumInteritemSpacing = 2
            layout.minimumLineSpacing = 2
            layout.sectionHeadersPinToVisibleBounds = parent.sectionMode.hasHeaders
            return layout
        }

        // MARK: UICollectionViewDelegateFlowLayout

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            sizeForItemAt indexPath: IndexPath
        ) -> CGSize {
            Self.cellSize(
                width: collectionView.bounds.width,
                columns: (collectionViewLayout as? GridFlowLayout)?.columns
                    ?? GridDensity.clamped(parent.columnCount)
            )
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> CGSize {
            guard sections.indices.contains(section),
                  let title = sections[section].title, !title.isEmpty
            else { return .zero }
            return CGSize(width: collectionView.bounds.width, height: 32)
        }

        /// Square cell side for a column count, floored to pixel precision so
        /// a row of N cells + gaps never exceeds the width (which would wrap).
        static func cellSize(width: CGFloat, columns: Int) -> CGSize {
            let spacing: CGFloat = 2
            let scale = UIScreen.main.scale
            let raw = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            let side = max(1, (raw * scale).rounded(.down) / scale)
            return CGSize(width: side, height: side)
        }

        /// Cell width in points for the current committed layout — sizes
        /// thumbnail requests and gates the metadata line.
        private var cellPointWidth: CGFloat {
            guard let collectionView else { return 0 }
            return Self.cellSize(
                width: collectionView.bounds.width,
                columns: GridDensity.clamped(parent.columnCount)
            ).width
        }

        private var thumbnailTargetSize: CGSize {
            // Match the physical display scale. Capping a 3x phone at 2x saved
            // decode memory but left one- and two-column thumbnails visibly
            // soft compared with Photos.
            let scale = UIScreen.main.scale
            let side = cellPointWidth * scale
            return CGSize(width: side, height: side)
        }

        private var detailTargetSize: CGSize {
            let scale = UIScreen.main.scale
            return CGSize(
                width: UIScreen.main.bounds.width * scale,
                height: UIScreen.main.bounds.height * scale
            )
        }

        // MARK: UICollectionViewDataSource

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            sections.count
        }

        func collectionView(
            _ collectionView: UICollectionView, numberOfItemsInSection section: Int
        ) -> Int {
            sections.indices.contains(section) ? sections[section].range.count : 0
        }

        func collectionView(
            _ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath
        ) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: PhotoGridCell.reuseId, for: indexPath
            ) as! PhotoGridCell
            if let flatIndex = flatIndex(for: indexPath) {
                configure(cell, at: flatIndex)
            }
            return cell
        }

        private func configure(_ cell: PhotoGridCell, at flatIndex: Int) {
            let item = parent.photos[flatIndex]
            let asset = parent.assetProvider(flatIndex, item)
            cell.configure(
                item: item,
                asset: asset,
                cellWidth: cellPointWidth,
                targetSize: thumbnailTargetSize,
                isSelecting: parent.isSelecting,
                isSelected: appliedSelectedIds.contains(item.assetId),
                photoLibrary: parent.photoLibrary,
                displayOptions: displayOptions,
                lazyMetadataProvider: parent.lazyMetadataProvider
            )
        }

        func collectionView(
            _ collectionView: UICollectionView,
            viewForSupplementaryElementOfKind kind: String,
            at indexPath: IndexPath
        ) -> UICollectionReusableView {
            let view = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind, withReuseIdentifier: Self.headerReuseId, for: indexPath
            ) as! UICollectionViewCell
            let title = sections.indices.contains(indexPath.section)
                ? sections[indexPath.section].title ?? ""
                : ""
            view.contentConfiguration = UIHostingConfiguration {
                GridSectionHeader(title: title)
            }
            .margins(.all, 0)
            return view
        }

        // MARK: Delegate

        func collectionView(
            _ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath
        ) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let flatIndex = flatIndex(for: indexPath) else { return }
            parent.onTap(flatIndex, parent.photos[flatIndex])
        }

        func collectionView(
            _ collectionView: UICollectionView,
            willDisplay cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard let flatIndex = flatIndex(for: indexPath) else { return }
            if let oldEntry = detailPreheatedByIndexPath.removeValue(forKey: indexPath) {
                cancelDecodedDetailPreheat(oldEntry)
                parent.photoLibrary.stopCachingDetailImages(
                    for: [oldEntry.asset],
                    targetSize: detailTargetSize
                )
            }
            let item = parent.photos[flatIndex]
            if let asset = parent.assetProvider(flatIndex, item),
               asset.mediaType == .image,
               detailPreheatedByIndexPath.count < maximumDetailPreheatCount {
                parent.photoLibrary.startCachingDetailImages(
                    for: [asset],
                    targetSize: detailTargetSize
                )
                let entry = DetailPreheatEntry(asset: asset)
                detailPreheatedByIndexPath[indexPath] = entry
                // Let fast-scrolling cells leave before starting a screen-sized
                // decode. Stable visible cells warm the shared decoded cache.
                scheduleDecodedDetailPreheat(entry, at: indexPath, delay: .milliseconds(180))
            }
            if flatIndex >= parent.photos.count - 30 {
                parent.onNearEnd()
            }
        }

        func collectionView(
            _ collectionView: UICollectionView,
            didEndDisplaying cell: UICollectionViewCell,
            forItemAt indexPath: IndexPath
        ) {
            guard let entry = detailPreheatedByIndexPath.removeValue(forKey: indexPath) else {
                return
            }
            cancelDecodedDetailPreheat(entry)
            parent.photoLibrary.stopCachingDetailImages(
                for: [entry.asset],
                targetSize: detailTargetSize
            )
        }

        func stopAllDetailPreheating() {
            let entries = Array(detailPreheatedByIndexPath.values)
            detailPreheatedByIndexPath.removeAll()
            for entry in entries {
                cancelDecodedDetailPreheat(entry)
            }
            parent.photoLibrary.stopCachingDetailImages(
                for: entries.map(\.asset),
                targetSize: detailTargetSize
            )
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            for entry in detailPreheatedByIndexPath.values {
                cancelDecodedDetailPreheat(entry)
            }
            parent.onUserScroll()
        }

        func scrollViewDidEndDragging(
            _ scrollView: UIScrollView,
            willDecelerate decelerate: Bool
        ) {
            if !decelerate { warmVisibleDetailProxies() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            warmVisibleDetailProxies()
        }

        private func warmVisibleDetailProxies() {
            for (indexPath, entry) in detailPreheatedByIndexPath {
                scheduleDecodedDetailPreheat(entry, at: indexPath, delay: .zero)
            }
        }

        private func scheduleDecodedDetailPreheat(
            _ entry: DetailPreheatEntry,
            at indexPath: IndexPath,
            delay: Duration
        ) {
            guard entry.requestId == nil, entry.warmTask == nil else { return }
            entry.warmTask = Task { @MainActor [weak self, weak entry] in
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled, let self, let entry,
                      self.detailPreheatedByIndexPath[indexPath] === entry
                else { return }
                entry.warmTask = nil
                entry.requestId = self.parent.photoLibrary.requestBestLocalImage(
                    for: entry.asset,
                    targetSize: self.detailTargetSize,
                    contentMode: .aspectFit
                ) { _ in }
            }
        }

        private func cancelDecodedDetailPreheat(_ entry: DetailPreheatEntry) {
            entry.warmTask?.cancel()
            entry.warmTask = nil
            if let requestId = entry.requestId {
                parent.photoLibrary.cancelThumbnailRequest(requestId)
            }
            entry.requestId = nil
        }

        // MARK: Prefetching

        func collectionView(
            _ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]
        ) {
            parent.photoLibrary.startCachingThumbnails(
                for: assets(at: indexPaths), targetSize: thumbnailTargetSize
            )
        }

        func collectionView(
            _ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]
        ) {
            // Do not resolve PHAssets merely to cancel prefetch: an async cache
            // miss here would start work for cells that are moving away. The
            // bounded PHCachingImageManager/cache naturally evicts these small
            // local thumbnails.
        }

        private func assets(at indexPaths: [IndexPath]) -> [PHAsset] {
            indexPaths.compactMap { indexPath in
                flatIndex(for: indexPath).flatMap { parent.assetProvider($0, parent.photos[$0]) }
            }
        }

        // MARK: Gestures

        private var pinchRecognizer: UIPinchGestureRecognizer?
        private var longPressRecognizer: UILongPressGestureRecognizer?
        private var swipeRecognizer: UIPanGestureRecognizer?

        func installGestures(on collectionView: UICollectionView) {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            collectionView.addGestureRecognizer(pinch)
            pinchRecognizer = pinch

            let longPress = UILongPressGestureRecognizer(
                target: self, action: #selector(handleLongPress(_:))
            )
            longPress.minimumPressDuration = 0.35
            collectionView.addGestureRecognizer(longPress)
            longPressRecognizer = longPress

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSwipeSelect(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            pan.isEnabled = false
            collectionView.addGestureRecognizer(pan)
            swipeRecognizer = pan
        }

        /// Swipe-select pan runs alongside the collection view's own pan;
        /// the direction lock decides which one wins per drag.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            let isSwipePinchPair =
                (gestureRecognizer === swipeRecognizer && other === pinchRecognizer)
                || (gestureRecognizer === pinchRecognizer && other === swipeRecognizer)
            return gestureRecognizer === swipeRecognizer || isSwipePinchPair
        }

        /// Long press enters selection mode *and*, without lifting, keeps
        /// driving the range under the finger.
        ///
        /// The swipe pan cannot do the drag part: it is only enabled once
        /// SwiftUI has re-applied with `isSelecting == true` (see `apply`), by
        /// which time this touch is already in flight — and UIKit never hands
        /// an in-flight touch to a recognizer enabled mid-sequence, so no
        /// `.began` would ever arrive. So the long press seeds the same
        /// swipe-select state machine and feeds it from its own `.changed`.
        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard let collectionView else { return }
            switch recognizer.state {
            case .began:
                guard let indexPath = collectionView.indexPathForItem(
                          at: recognizer.location(in: collectionView)
                      ),
                      let flatIndex = flatIndex(for: indexPath)
                else { return }
                // Only the press that *enters* selection mode takes over the
                // drag. Already selecting means the pan recognizer is live and
                // owns direction locking — hijacking a resting finger there
                // would turn ordinary vertical scrolling into a selection.
                let entersSelection = !parent.isSelecting
                parent.onLongPress(parent.photos[flatIndex])
                guard entersSelection else { return }
                isLongPressDragActive = true
                // No direction lock: the 0.35s hold already expressed intent,
                // so up/down drags select instead of scrolling.
                swipeActivation = .select
                swipeStartFlatIndex = flatIndex
                swipeShouldSelect = true
                swipeLastFlatIndex = nil
                collectionView.isScrollEnabled = false
                let location = recognizer.location(in: collectionView)
                swipeWindowLocation = collectionView.window.map {
                    collectionView.convert(location, to: $0)
                }
                parent.onSwipeEvent(.began)
                updateSwipeRange(at: location)
                startSwipeAutoScroll()
            case .changed:
                guard isLongPressDragActive else { return }
                swipeWindowLocation = collectionView.window.map {
                    recognizer.location(in: $0)
                }
                updateSwipeRange(at: recognizer.location(in: collectionView))
            case .ended, .cancelled, .failed:
                guard isLongPressDragActive else { return }
                finishActiveSwipeSelection()
            default:
                break
            }
        }

        // MARK: Pinch density (interactive layout transition)

        /// Cumulative scale (relative to the segment baseline) that maps to
        /// transition progress 1. Spreading (scale > 1) removes a column;
        /// pinching in adds one.
        private static var stepSpan: CGFloat { 0.35 }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard collectionView != nil else { return }
            switch recognizer.state {
            case .began:
                // A second finger may turn an in-progress one-finger selection
                // into a pinch. Close the selection gesture exactly once; the
                // selected ids remain untouched.
                finishActiveSwipeSelection()
                transitionBaselineScale = recognizer.scale
            case .changed:
                // While the previous segment's finish/cancel animation is
                // settling, ignore movement — starting a new interactive
                // transition before the completion callback fires corrupts
                // UIKit's transition state (returns the bare target layout,
                // which crashes on `transitionProgress`).
                guard !isSettling else {
                    transitionBaselineScale = recognizer.scale
                    return
                }
                guard transitionLayout != nil || beginSegment(recognizer.scale) else { return }
                guard let transitionLayout else { return }
                let progress = segmentProgress(scale: recognizer.scale)
                if progress >= 1 {
                    // Step committed mid-gesture — finish; the next segment
                    // can start once the settle completes (so one long pinch
                    // still walks through several densities, gated per step).
                    transitionLayout.transitionProgress = 1
                    finishSegment()
                    transitionBaselineScale = recognizer.scale
                } else if progress <= 0 {
                    // Fingers reversed past the segment start — cancel and
                    // allow a segment in the opposite direction.
                    cancelSegment()
                    transitionBaselineScale = recognizer.scale
                } else {
                    transitionLayout.transitionProgress = progress
                    transitionLayout.invalidateLayout()
                }
            case .ended, .cancelled, .failed:
                if let transitionLayout {
                    if transitionLayout.transitionProgress > 0.4 {
                        finishSegment()
                    } else {
                        cancelSegment()
                    }
                }
            default:
                break
            }
        }

        /// Starts an interactive transition toward ±1 column once the pinch
        /// direction is clear. Returns false while direction is ambiguous,
        /// the range end is reached, or the previous segment is settling.
        private func beginSegment(_ scale: CGFloat) -> Bool {
            guard let collectionView, transitionLayout == nil, !isSettling else { return false }
            let ratio = scale / transitionBaselineScale
            guard abs(ratio - 1) > 0.02 else { return false }
            // Spreading fingers = bigger cells = fewer columns.
            let delta = ratio > 1 ? -1 : 1
            let target = GridDensity.stepped(parent.columnCount, by: delta)
            guard target != parent.columnCount else { return false }
            transitionDelta = delta
            parent.photoLibrary.stopCachingAllThumbnails()
            let layout = collectionView.startInteractiveTransition(
                to: makeLayout(columns: target)
            ) { [weak self] completed, _ in
                self?.transitionDidEnd(committed: completed)
            }
            // Defensive: some layout classes (compositional) come back
            // unwrapped instead of as a real transition layout — driving
            // progress on those crashes. Commit the step instantly instead.
            guard layout.responds(
                to: #selector(setter: UICollectionViewTransitionLayout.transitionProgress)
            ) else {
                collectionView.finishInteractiveTransition()
                return false
            }
            transitionLayout = layout
            return true
        }

        private func segmentProgress(scale: CGFloat) -> CGFloat {
            let ratio = scale / transitionBaselineScale
            // Log-space so pinching feels symmetric in both directions.
            let signed = log(ratio) / Self.stepSpan
            let toward = transitionDelta == -1 ? signed : -signed
            return min(max(toward, 0), 1)
        }

        private func finishSegment() {
            guard let collectionView else { return }
            isSettling = true
            collectionView.finishInteractiveTransition()
            transitionLayout = nil
        }

        private func cancelSegment() {
            guard let collectionView else { return }
            isSettling = true
            collectionView.cancelInteractiveTransition()
            transitionLayout = nil
        }

        private func transitionDidEnd(committed: Bool) {
            guard let collectionView else { return }
            if committed {
                let newColumns = GridDensity.stepped(parent.columnCount, by: transitionDelta)
                appliedColumns = newColumns
                parent.columnCount = newColumns
                // Granularity may have flipped (day <-> month at 3/4) —
                // regroup and reload so headers and item counts match. A flip
                // that keeps the section count still changes the header text,
                // so compare the resolved sections, not just how many.
                // Screen-supplied sections resolve identically here, so they
                // are never re-grouped by a pinch.
                let before = sections
                rebuildSections()
                if sections != before {
                    collectionView.reloadData()
                }
                // Sharper thumbnails for the new cell size.
                reconfigureVisibleCells(collectionView)
            }
            transitionLayout = nil
            isSettling = false
        }

        // MARK: Swipe-select

        @objc private func handleSwipeSelect(_ recognizer: UIPanGestureRecognizer) {
            // The long press that opened selection mode is still down and owns
            // the range; a pan enabled mid-touch must not drive it too.
            guard !isLongPressDragActive, let collectionView else { return }
            switch recognizer.state {
            case .began:
                swipeActivation = .undecided
                resetSwipeState(keepingScrollEnabled: true)
            case .changed:
                let translation = recognizer.translation(in: collectionView)
                if swipeActivation == .undecided {
                    swipeActivation = SwipeSelectionEngine.activation(
                        translation: CGSize(width: translation.x, height: translation.y)
                    )
                    if swipeActivation == .select {
                        // Recover the touch-down point rather than using the
                        // location after UIKit's pan threshold. A fast swipe
                        // can cross a whole tile before `.began`.
                        let location = recognizer.location(in: collectionView)
                        let startPoint = CGPoint(
                            x: location.x - translation.x,
                            y: location.y - translation.y
                        )
                        guard let startPath = collectionView.indexPathForItem(at: startPoint),
                              let startIndex = flatIndex(for: startPath)
                        else {
                            swipeActivation = .scroll
                            return
                        }
                        swipeStartFlatIndex = startIndex
                        swipeShouldSelect = !appliedSelectedIds.contains(
                            parent.photos[startIndex].assetId
                        )
                        collectionView.isScrollEnabled = false
                        parent.onSwipeEvent(.began)
                        updateSwipeRange(at: startPoint)
                        startSwipeAutoScroll()
                    }
                }
                guard swipeActivation == .select else { return }
                swipeWindowLocation = recognizer.location(in: collectionView.window)
                updateSwipeRange(at: recognizer.location(in: collectionView))
            case .ended, .cancelled, .failed:
                finishActiveSwipeSelection()
            default:
                break
            }
        }

        private func updateSwipeRange(at location: CGPoint) {
            guard let collectionView,
                  let startIndex = swipeStartFlatIndex,
                  let shouldSelect = swipeShouldSelect,
                  let indexPath = collectionView.indexPathForItem(at: location),
                  let currentIndex = flatIndex(for: indexPath),
                  currentIndex != swipeLastFlatIndex
            else { return }
            swipeLastFlatIndex = currentIndex
            let range = min(startIndex, currentIndex)...max(startIndex, currentIndex)
            parent.onSwipeEvent(
                .changed(
                    rangeIds: parent.photos[range].map(\.assetId),
                    select: shouldSelect
                )
            )
        }

        private func startSwipeAutoScroll() {
            guard swipeAutoScrollDriver == nil else { return }
            let driver = GridDisplayLinkDriver { [weak self] in
                self?.handleSwipeAutoScrollFrame()
            }
            driver.start()
            swipeAutoScrollDriver = driver
        }

        private func handleSwipeAutoScrollFrame() {
            guard swipeActivation == .select,
                  let collectionView,
                  let window = collectionView.window,
                  let windowLocation = swipeWindowLocation
            else { return }
            let location = collectionView.convert(windowLocation, from: window)
            let delta = SwipeSelectionEngine.autoScrollDelta(
                locationY: location.y,
                visibleBounds: collectionView.bounds
            )
            guard delta != 0 else { return }
            let minimumY = -collectionView.adjustedContentInset.top
            let maximumY = max(
                minimumY,
                collectionView.collectionViewLayout.collectionViewContentSize.height
                    - collectionView.bounds.height
                    + collectionView.adjustedContentInset.bottom
            )
            let nextY = min(max(collectionView.contentOffset.y + delta, minimumY), maximumY)
            guard nextY != collectionView.contentOffset.y else { return }
            collectionView.setContentOffset(
                CGPoint(x: collectionView.contentOffset.x, y: nextY),
                animated: false
            )
            // Scrolling changes which tile sits under a stationary finger.
            updateSwipeRange(at: collectionView.convert(windowLocation, from: window))
        }

        private func resetSwipeState(keepingScrollEnabled: Bool) {
            swipeAutoScrollDriver?.invalidate()
            swipeAutoScrollDriver = nil
            swipeShouldSelect = nil
            swipeStartFlatIndex = nil
            swipeLastFlatIndex = nil
            swipeWindowLocation = nil
            if !keepingScrollEnabled {
                collectionView?.isScrollEnabled = true
            }
        }

        /// Ends only the gesture lifecycle, never the selection itself. Used
        /// both on touch-up and when a second finger promotes swipe to pinch.
        private func finishActiveSwipeSelection() {
            if swipeActivation == .select {
                parent.onSwipeEvent(.ended)
            }
            isLongPressDragActive = false
            swipeActivation = .undecided
            resetSwipeState(keepingScrollEnabled: false)
        }
    }
}

/// CADisplayLink retains its target. This small driver owns the link while its
/// callback captures the grid coordinator weakly, preventing an interrupted
/// selection gesture from keeping the whole collection view alive.
@MainActor
private final class GridDisplayLinkDriver {
    private let onFrame: @MainActor () -> Void
    private var displayLink: CADisplayLink?

    init(onFrame: @escaping @MainActor () -> Void) {
        self.onFrame = onFrame
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 30,
            maximum: 60,
            preferred: 60
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func invalidate() {
        displayLink?.invalidate()
        displayLink = nil
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func tick() {
        onFrame()
    }
}

// MARK: - Flow layout subclass

/// Flow layout tagged with its column count, so the sizing delegate can
/// serve the right cell size for *each* layout during an interactive
/// transition (UIKit asks both the old and the new layout).
private final class GridFlowLayout: UICollectionViewFlowLayout {
    var columns = 3
}

// MARK: - Collection view subclass

/// Fires a one-shot callback on the first layout pass with real bounds —
/// the representable is created with a zero frame, so the initial bottom
/// anchor must wait until SwiftUI has sized the view.
private final class GridCollectionView: UICollectionView {
    var onFirstLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.height > 0, let callback = onFirstLayout {
            onFirstLayout = nil
            callback()
        }
    }
}

// MARK: - Section header

/// Pinned section header: a compact glass capsule chip, legible over
/// scrolling photos without covering the full row width. Hosted in the
/// collection view's supplementary views via UIHostingConfiguration.
struct GridSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Cell

/// One square grid cell, pure UIKit for scroll performance: thumbnail +
/// bottom metadata line over a gradient + video badge + selection UI.
final class PhotoGridCell: UICollectionViewCell {
    static var reuseId: String { "PhotoGridCell" }

    /// Cells narrower than this hide the metadata line.
    private static var metadataMinCellWidth: CGFloat { 90 }

    private let imageView = UIImageView()
    private let gradient = CAGradientLayer()
    private let metadataLabel = UILabel()
    private let videoBadge = UILabel()
    private let selectionBorder = UIView()
    private let selectionBadge = UIImageView()

    private var requestId: PHImageRequestID?
    private var requestedAssetId: String?
    private var lastRequestedPixelWidth: CGFloat = 0
    private weak var photoLibrary: PhotoLibraryService?
    /// Identity + in-flight lookup of the lazy badge fill: the fetch result
    /// only applies while the cell still shows the asset it was started for.
    private var configuredAssetId: String?
    private var badgeFetchTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemBackground
        contentView.addSubview(imageView)

        gradient.colors = [
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.55).cgColor,
        ]
        contentView.layer.addSublayer(gradient)

        metadataLabel.font = .systemFont(ofSize: 10, weight: .medium)
        metadataLabel.textColor = .white
        contentView.addSubview(metadataLabel)

        videoBadge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        videoBadge.textColor = .white
        videoBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        videoBadge.layer.cornerRadius = 8
        videoBadge.clipsToBounds = true
        videoBadge.textAlignment = .center
        contentView.addSubview(videoBadge)

        selectionBorder.layer.borderWidth = 3
        selectionBorder.layer.borderColor = UIColor.tintColor.cgColor
        selectionBorder.isUserInteractionEnabled = false
        contentView.addSubview(selectionBorder)

        selectionBadge.preferredSymbolConfiguration = .init(pointSize: 18, weight: .semibold)
        selectionBadge.backgroundColor = .clear
        contentView.addSubview(selectionBadge)

        contentView.clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        selectionBorder.frame = contentView.bounds
        let labelHeight: CGFloat = 20
        metadataLabel.frame = CGRect(
            x: 6, y: contentView.bounds.height - labelHeight + 1,
            width: contentView.bounds.width - 12, height: labelHeight - 5
        )
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = CGRect(
            x: 0, y: contentView.bounds.height - 24,
            width: contentView.bounds.width, height: 24
        )
        CATransaction.commit()
        let badgeSize = videoBadge.intrinsicContentSize
        videoBadge.frame = CGRect(
            x: contentView.bounds.width - badgeSize.width - 14, y: 4,
            width: badgeSize.width + 10, height: 16
        )
        selectionBadge.frame = CGRect(
            x: contentView.bounds.width - 26, y: contentView.bounds.height - 26,
            width: 22, height: 22
        )
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cancelRequest()
        imageView.image = nil
        requestedAssetId = nil
        lastRequestedPixelWidth = 0
        badgeFetchTask?.cancel()
        badgeFetchTask = nil
        configuredAssetId = nil
    }

    func configure(
        item: some PhotoGridDisplayable,
        asset: PHAsset?,
        cellWidth: CGFloat,
        targetSize: CGSize,
        isSelecting: Bool,
        isSelected: Bool,
        photoLibrary: PhotoLibraryService,
        displayOptions: GridMetadataDisplayOptions,
        lazyMetadataProvider: ((String) async -> (any PhotoGridDisplayable)?)? = nil
    ) {
        self.photoLibrary = photoLibrary
        configuredAssetId = item.assetId
        badgeFetchTask?.cancel()
        badgeFetchTask = nil

        let showsBadge = cellWidth >= Self.metadataMinCellWidth
        let line = showsBadge ? Self.metadataLine(for: item, options: displayOptions) : nil
        applyBadge(line: line)

        // Item carries no exposure fields at all — typically a tile the
        // index run hasn't reached (or has filled since this list loaded).
        // Ask for a fresh row and update just this cell when it arrives.
        if showsBadge, let lazyMetadataProvider, Self.hasNoBadgeData(item) {
            let assetId = item.assetId
            badgeFetchTask = Task { [weak self] in
                guard let fetched = await lazyMetadataProvider(assetId) else { return }
                guard let self, !Task.isCancelled,
                      self.configuredAssetId == assetId else { return }
                self.applyBadge(line: Self.metadataLine(for: fetched, options: displayOptions))
            }
        }

        if let asset, asset.mediaType == .video {
            videoBadge.text = asset.duration > 0
                ? "▶ \(FormatUtils.duration(asset.duration))" : "▶"
            videoBadge.isHidden = false
        } else {
            videoBadge.isHidden = true
        }

        updateSelection(isSelecting: isSelecting, isSelected: isSelected)

        requestThumbnail(asset: asset, targetSize: targetSize)
        setNeedsLayout()
    }

    /// Lightweight swipe-select update. Deliberately leaves the thumbnail,
    /// metadata task and video badge untouched.
    func updateSelection(isSelecting: Bool, isSelected: Bool) {
        selectionBorder.isHidden = !(isSelecting && isSelected)
        selectionBadge.isHidden = !isSelecting
        selectionBadge.image = UIImage(
            systemName: isSelected ? "checkmark.circle.fill" : "circle"
        )
        selectionBadge.tintColor = isSelected ? .tintColor : .white
    }

    /// Single write point for the metadata overlay (sync configure and the
    /// async lazy fill), so label, gradient, and accessibility stay in step.
    private func applyBadge(line: String?) {
        metadataLabel.text = line
        metadataLabel.isHidden = line == nil
        gradient.isHidden = line == nil
        isAccessibilityElement = true
        accessibilityLabel = line.map { "Photo, \($0)" } ?? "Photo"
    }

    /// Requests the thumbnail sized to the cell. Re-requests only when the
    /// asset changed or the cell grew materially (density step to fewer
    /// columns) — the old image stays visible until the sharper one arrives.
    private func requestThumbnail(asset: PHAsset?, targetSize: CGSize) {
        guard let asset, let photoLibrary else {
            cancelRequest()
            imageView.image = nil
            // Clear the request identity too: the asset is only missing because
            // its chunk is still resolving, and leaving the id set would make
            // the re-configure that follows look like "same asset, nothing to
            // do" — the tile would stay grey until it was reused.
            requestedAssetId = nil
            lastRequestedPixelWidth = 0
            return
        }
        let assetChanged = asset.localIdentifier != requestedAssetId
        let needsUpgrade = targetSize.width > lastRequestedPixelWidth * 1.4
        guard assetChanged || needsUpgrade else { return }
        cancelRequest()
        if assetChanged { imageView.image = nil }
        requestedAssetId = asset.localIdentifier
        lastRequestedPixelWidth = targetSize.width
        // Local-only: scrolling the grid must never trigger iCloud downloads.
        requestId = photoLibrary.requestThumbnail(
            for: asset, targetSize: targetSize, allowNetwork: false
        ) { [weak self] image in
            guard let self, self.requestedAssetId == asset.localIdentifier else { return }
            if let image {
                self.imageView.image = image
            }
        }
    }

    private func cancelRequest() {
        if let requestId {
            photoLibrary?.cancelThumbnailRequest(requestId)
        }
        requestId = nil
    }

    /// Only real values — never placeholders like `ISO -- · --mm`.
    private static func metadataLine(
        for item: some PhotoGridDisplayable, options: GridMetadataDisplayOptions
    ) -> String? {
        let focalValue = options.focalStyleEquivalent
            ? (item.equivalentFocalLength ?? item.focalLength)
            : item.focalLength
        return FormatUtils.metadataLine([
            options.showISO ? item.iso.flatMap(FormatUtils.iso) : nil,
            options.showFocal ? focalValue.flatMap(FormatUtils.focalLength) : nil,
            options.showAperture ? item.aperture.flatMap(FormatUtils.aperture) : nil,
            options.showShutter ? item.shutterSpeedDisplay : nil,
            options.showMegapixels ? item.megapixels.flatMap(FormatUtils.megapixels) : nil,
            options.showFileSize ? item.fileSize.flatMap(FormatUtils.fileSize) : nil,
        ])
    }

    /// True when the item carries none of the overlay's exposure fields —
    /// the trigger for the lazy on-display lookup. A data check, not a
    /// formatted-line check: display toggles hiding all fields must not
    /// cause fetches for rows that are already filled.
    private static func hasNoBadgeData(_ item: some PhotoGridDisplayable) -> Bool {
        item.iso == nil && item.aperture == nil && item.shutterSpeedDisplay == nil
            && item.focalLength == nil && item.equivalentFocalLength == nil
    }
}

/// Snapshot of the Settings display toggles for the tile overlay (same
/// UserDefaults keys as the Settings screen's @AppStorage). Loaded once and
/// refreshed on the defaults-change notification instead of five defaults
/// reads per cell configure.
struct GridMetadataDisplayOptions: Equatable {
    var showISO: Bool
    var showAperture: Bool
    var showShutter: Bool
    var showFocal: Bool
    var showMegapixels: Bool
    var showFileSize: Bool
    var focalStyleEquivalent: Bool

    static func load(from defaults: UserDefaults = .standard) -> GridMetadataDisplayOptions {
        func flag(_ key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? defaultValue
        }
        return GridMetadataDisplayOptions(
            showISO: flag("display.showISO", default: true),
            showAperture: flag("display.showAperture", default: true),
            showShutter: flag("display.showShutter", default: false),
            showFocal: flag("display.showFocal", default: true),
            showMegapixels: flag("display.showMegapixels", default: false),
            showFileSize: flag("display.showFileSize", default: false),
            focalStyleEquivalent: flag("display.focalStyleEquivalent", default: false)
        )
    }
}
