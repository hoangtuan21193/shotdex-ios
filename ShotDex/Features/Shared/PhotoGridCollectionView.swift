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
    /// Optional low-emphasis text rendered as a real footer after the final
    /// photo. Nil keeps the shared album grids unchanged.
    var trailingFooterText: String? = nil
    /// Optional on-display badge lookup: a cell missing exposure or source-file
    /// fields asks for a fresh row when it becomes visible, so tiles indexed
    /// mid-run fill in lazily instead of the whole grid reloading per photo.
    /// Nil (Album Detail) disables the lookup.
    var lazyMetadataProvider: ((String) async -> (any PhotoGridDisplayable)?)? = nil
    /// The list owner's latest in-place deletion (see `PhotoGridRemoval`). Set
    /// in the same update as the pruned `photos`; the grid animates those
    /// tiles out and skips the reload that `contentVersion`/count would cause.
    var removal: PhotoGridRemoval? = nil
    /// Builds the long-press context menu for one tile, as in Photos. `nil`
    /// (or a `nil` return) leaves the tile without a menu, in which case the
    /// long press falls back to entering selection mode.
    var contextMenuProvider: ((Item) -> UIMenu?)? = nil
    /// Drives the date scrubber drawn over the grid's right edge. The grid
    /// publishes its position and the date under the top of the viewport, and
    /// registers the jump closure the scrubber calls back.
    var scrubber: PhotoGridScrubberModel? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let coordinator = context.coordinator
        let collectionView = GridCollectionView(
            frame: .zero,
            collectionViewLayout: coordinator.makeLayout(density: columnCount)
        )
        // SwiftUI sizes the representable after creation, and UIKit settles the
        // safe area later still — the opening anchor re-applies until the user
        // takes over the scroll position.
        collectionView.onAnchorNeeded = { [weak coordinator] in
            coordinator?.anchorIfNeeded()
        }
        // A width change (device fold, Split View, rotation) can mean a
        // different column count for the same stored density — see
        // `Coordinator.resolvedColumns`.
        collectionView.onContentWidthChange = { [weak coordinator] in
            // Out of the layout pass: swapping the layout from inside
            // `layoutSubviews` re-enters UIKit's own layout.
            Task { @MainActor in
                coordinator?.reapplyLayoutIfColumnsChanged()
                coordinator?.refreshScrubberAfterLayout()
            }
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
        collectionView.register(
            UICollectionViewCell.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionFooter,
            withReuseIdentifier: Coordinator.footerReuseId
        )
        coordinator.collectionView = collectionView
        coordinator.installGestures(on: collectionView)
        scrubber?.scrollTo = { [weak coordinator] fraction in
            coordinator?.scrollToFraction(fraction)
        }
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
        coordinator.cancelHighlightPreheat()
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource,
        UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching,
        UIGestureRecognizerDelegate {

        static var headerReuseId: String { "PhotoGridHeader" }
        static var footerReuseId: String { "PhotoGridFooter" }

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
        private var appliedTrailingFooterText: String?
        /// List owners bump `contentVersion` for same-count identity/order
        /// changes. Album paging uses a stable version but changes count, so the
        /// coordinator only needs this scalar — never an O(n) id snapshot.
        private var appliedPhotoCount = 0
        private var appliedColumns = 0
        private var appliedJumpToken: Int?
        private var appliedRemovalToken: Int?
        private var appliedSelecting = false
        /// Membership snapshot for O(1) cell configuration. Selection order is
        /// owned by the screen/selection bar; the grid only needs membership.
        private var appliedSelectedIds: Set<String> = []
        /// Local-only, screen-sized detail rendition for the tile under the
        /// user's finger, warmed on highlight so the viewer's first frame is not
        /// an enlarged grid thumbnail. Only that one tile: preheating every
        /// visible cell queued up to 18 full-screen decodes on the image manager
        /// that also serves the thumbnails, and the sharp grid renditions sat
        /// behind them — the grid stayed soft for seconds after each scroll.
        private var highlightPreheat: (asset: PHAsset, requestId: PHImageRequestID)?

        // Pinch state
        private var transitionLayout: UICollectionViewTransitionLayout?
        private var transitionBaselineScale: CGFloat = 1
        private var transitionDelta = 0
        /// True from finish/cancel until UIKit's completion callback — no new
        /// interactive transition may start in that window (see handlePinch).
        private var isSettling = false

        // Swipe-select state
        private var swipeActivation = SwipeSelection.Activation.undecided
        /// Frozen once per gesture. Recomputing from the live selection would
        /// flip select→deselect after the first callback and make badges blink.
        private var shouldSelectOnSwipe: Bool?
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

            // An in-place deletion animates the tiles out and leaves the
            // scroll position alone. It consumes the version/count/section
            // change that came with it, so the reload branch below sees a
            // settled grid. Anything the note does not account for falls
            // through to that branch.
            if let removal = newParent.removal, removal.token != appliedRemovalToken {
                appliedRemovalToken = removal.token
                if !isInitial, applyRemoval(removal, newParent: newParent, in: collectionView) {
                    appliedContentVersion = newParent.contentVersion
                    appliedPhotoCount = newParent.photos.count
                    appliedCustomSections = newParent.sectionMode.customSections
                }
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
                    makeLayout(density: newParent.columnCount), animated: false
                ) { [weak self] _ in
                    // New cell sizes: re-request so a 1-column swap gets tall,
                    // aspect-correct renditions rather than stale square ones.
                    self?.reconfigureVisibleCells(collectionView)
                }
            }
            appliedColumns = newParent.columnCount

            let refreshed = appliedContentRefreshVersion != nil
                && newParent.contentRefreshVersion != appliedContentRefreshVersion
            // Screen-supplied sections can change while the photo count and
            // contentVersion stay put (a delete that empties one year). One
            // entry per group, so comparing them per update is cheap.
            let newCustomSections = newParent.sectionMode.customSections
            let sectionsChanged = newCustomSections != appliedCustomSections
            let footerChanged = newParent.trailingFooterText != appliedTrailingFooterText
            appliedCustomSections = newCustomSections
            // Re-anchoring stays gated on `contentReplaced` — a section-only
            // change must reload in place, not jump the scroll position.
            if contentReplaced || listChanged || sectionsChanged || footerChanged || isInitial {
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
            appliedTrailingFooterText = newParent.trailingFooterText

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
            // With a context menu installed, a press that is *not* already in
            // selection mode belongs to UIKit's own menu interaction — two
            // long presses on the same view would otherwise fight. Once
            // selecting, the press goes back to driving the range drag.
            longPressRecognizer?.isEnabled =
                newParent.contextMenuProvider == nil || newParent.isSelecting
            if !newParent.isSelecting, swipeActivation == .select {
                finishActiveSwipeSelection()
            }
        }

        /// Called by `GridCollectionView` on every layout/inset change until the
        /// user first touches the grid: the anchor computed in `makeUIView` ran
        /// against a zero frame and a zero safe area, so it needs re-applying as
        /// the real bounds and insets arrive.
        func anchorIfNeeded() {
            guard let collectionView else { return }
            collectionView.layoutIfNeeded()
            anchor(collectionView)
        }

        /// The user owns the scroll position from their first touch on. Stops
        /// the opening anchor from re-firing on a later inset change — entering
        /// selection mode grows the bottom inset, which would otherwise yank a
        /// user reading mid-grid down to the newest photos.
        private func endAnchorTracking() {
            (collectionView as? GridCollectionView)?.needsAnchor = false
        }

        private func anchor(_ collectionView: UICollectionView) {
            let target: CGFloat
            if parent.anchorsBottom {
                let bottom = collectionView.collectionViewLayout.collectionViewContentSize.height
                    - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
                target = max(bottom, -collectionView.adjustedContentInset.top)
            } else {
                target = -collectionView.adjustedContentInset.top
            }
            // Only move when it actually differs: `setContentOffset` triggers
            // another layout pass, which asks for the anchor again while
            // `needsAnchor` is still set — this is what breaks the loop.
            guard abs(collectionView.contentOffset.y - target) > 0.5 else { return }
            collectionView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        }

        /// A scroll position expressed as visible photo ids plus each tile's
        /// offset relative to the top of the viewport, so it survives a
        /// `reloadData` even when the list shifted (photos added or removed at
        /// either end) or the tile the user was looking at is itself gone.
        private struct PreservedScroll {
            struct Anchor {
                let assetId: String
                let offsetFromTileTop: CGFloat
            }
            /// Visible tiles top to bottom; the first one still in the list wins.
            let anchors: [Anchor]
            /// Flat index of the topmost visible tile. When every visible tile
            /// was deleted, the grid lands on whatever now occupies that spot
            /// instead of teleporting to the anchor end.
            let fallbackFlatIndex: Int
        }

        /// The spot to restore after a content replacement, or nil when the grid
        /// should re-anchor instead: nothing visible to key off, or the user was
        /// already parked at the end the grid anchors to — that's where newly
        /// added photos land, and staying there is what they expect.
        private func preservableScroll(_ collectionView: UICollectionView) -> PreservedScroll? {
            guard !isAtAnchorEnd(collectionView) else { return nil }
            let layout = collectionView.collectionViewLayout
            var anchors: [PreservedScroll.Anchor] = []
            var fallbackFlatIndex: Int?
            for indexPath in collectionView.indexPathsForVisibleItems.sorted() {
                guard let flatIndex = flatIndex(for: indexPath),
                      let frame = layout.layoutAttributesForItem(at: indexPath)?.frame
                else { continue }
                if fallbackFlatIndex == nil { fallbackFlatIndex = flatIndex }
                anchors.append(PreservedScroll.Anchor(
                    assetId: parent.photos[flatIndex].assetId,
                    offsetFromTileTop: collectionView.contentOffset.y - frame.minY
                ))
            }
            guard let fallbackFlatIndex else { return nil }
            return PreservedScroll(anchors: anchors, fallbackFlatIndex: fallbackFlatIndex)
        }

        /// False only when the new list is empty — every other case lands on
        /// a surviving visible tile, or on the tile now sitting where the
        /// topmost deleted one was.
        private func restoreScroll(
            _ preserved: PreservedScroll, in collectionView: UICollectionView
        ) -> Bool {
            guard !parent.photos.isEmpty else { return false }
            var indexById: [String: Int] = [:]
            for (index, photo) in parent.photos.enumerated() where indexById[photo.assetId] == nil {
                indexById[photo.assetId] = index
            }
            let target: (flatIndex: Int, offsetFromTileTop: CGFloat)
            if let survivor = preserved.anchors.lazy
                .compactMap({ anchor in indexById[anchor.assetId].map { ($0, anchor.offsetFromTileTop) } })
                .first {
                target = survivor
            } else {
                target = (
                    min(preserved.fallbackFlatIndex, parent.photos.count - 1),
                    preserved.anchors.first?.offsetFromTileTop ?? 0
                )
            }
            guard let indexPath = indexPath(forFlatIndex: target.flatIndex),
                  let frame = collectionView.collectionViewLayout
                    .layoutAttributesForItem(at: indexPath)?.frame
            else { return false }
            let minimum = -collectionView.adjustedContentInset.top
            let maximum = max(
                minimum,
                collectionView.collectionViewLayout.collectionViewContentSize.height
                    - collectionView.bounds.height + collectionView.adjustedContentInset.bottom
            )
            let offset = min(max(frame.minY + target.offsetFromTileTop, minimum), maximum)
            collectionView.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            return true
        }

        /// Parked at the end the grid anchors to. Bottom-anchored (Library):
        /// within one screen height of the bottom, where new photos land, so
        /// staying "at the newest" means following them. Top-anchored (albums,
        /// On This Day): only when actually at the top — these lists are short,
        /// so "within a screen of the top" was nearly always true and every
        /// reload snapped a user who had scrolled a few rows back to the start.
        private func isAtAnchorEnd(_ collectionView: UICollectionView) -> Bool {
            let height = collectionView.bounds.height
            guard height > 0 else { return true }
            guard parent.anchorsBottom else {
                return collectionView.contentOffset.y
                    + collectionView.adjustedContentInset.top <= 1
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

        /// Recomputes the scrubber's state after a layout pass. `scrollViewDidScroll`
        /// alone is not enough: a freshly laid-out grid has never scrolled, so the
        /// handle would stay untouchable until the user scrolled by hand first.
        /// Jumps the grid to `fraction` of its scrollable span, for the date
        /// scrubber. Ends anchor tracking first: the Library opens pinned to the
        /// newest photos and re-applies that anchor until the user takes over, so
        /// without this the grid snaps straight back to the bottom.
        func scrollToFraction(_ fraction: Double) {
            guard let collectionView else { return }
            endAnchorTracking()
            let span = collectionView.contentSize.height
                - collectionView.bounds.height
                + collectionView.adjustedContentInset.top
                + collectionView.adjustedContentInset.bottom
            guard span > 0 else { return }
            let y = -collectionView.adjustedContentInset.top + span * fraction
            collectionView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }

        func refreshScrubberAfterLayout() {
            guard parent.scrubber != nil else { return }
            // Out of the current layout pass: content size is only final once
            // UIKit has finished laying the sections out.
            Task { @MainActor [weak self] in
                guard let self, let collectionView = self.collectionView else { return }
                self.updateScrubber(collectionView)
            }
        }

        private func rebuildSections() {
            sections = Self.resolvedSections(
                for: parent, columns: resolvedColumns(parent.columnCount)
            )
            refreshScrubberAfterLayout()
        }

        private static func resolvedSections(
            for parent: PhotoGridCollectionView, columns: Int
        ) -> [ResolvedSection] {
            guard !parent.photos.isEmpty else { return [] }
            switch parent.sectionMode {
            case .flat:
                return [ResolvedSection(range: 0..<parent.photos.count, title: nil)]
            case .dates:
                let granularity = GridDensity.granularity(forColumns: columns)
                return PhotoGridSectionBuilder.sections(
                    creationDates: parent.photos.map(\.creationDateValue),
                    granularity: granularity
                ).map {
                    ResolvedSection(
                        range: $0.range,
                        title: dateTitle(for: $0.kind, granularity: granularity)
                    )
                }
            case .custom(let supplied):
                // The screen's sections and its photos arrive in the same
                // SwiftUI update, but clamp anyway: a momentarily stale pair
                // must degrade to fewer tiles, never to an item count that
                // indexes past the array.
                return supplied.compactMap { section in
                    let upper = min(section.range.upperBound, parent.photos.count)
                    guard section.range.lowerBound < upper else { return nil }
                    return ResolvedSection(
                        range: section.range.lowerBound..<upper, title: section.title
                    )
                }
            }
        }

        // MARK: In-place removal

        /// Animates `removal.assetIds` out of the grid when the new list is
        /// verifiably the old one minus those ids. Every check that fails
        /// returns false with nothing touched, and the caller reloads instead:
        /// a list that emptied, a pinch mid-transition, a note whose ids or
        /// order do not match the arrays, or a section shape UIKit could not
        /// be told about as pure deletions (a surviving section whose title or
        /// remaining count is not what the old one predicts).
        private func applyRemoval(
            _ removal: PhotoGridRemoval,
            newParent: PhotoGridCollectionView,
            in collectionView: UICollectionView
        ) -> Bool {
            let oldPhotos = parent.photos
            let newPhotos = newParent.photos
            guard !newPhotos.isEmpty, transitionLayout == nil, !isSettling else { return false }

            // Old flat indices of the removed tiles, and the order check: the
            // survivors must be the new list, in the same order.
            var removedFlatIndices: [Int] = []
            var survivorIndex = 0
            for (flatIndex, photo) in oldPhotos.enumerated() {
                if removal.assetIds.contains(photo.assetId) {
                    removedFlatIndices.append(flatIndex)
                } else {
                    guard survivorIndex < newPhotos.count,
                          newPhotos[survivorIndex].assetId == photo.assetId
                    else { return false }
                    survivorIndex += 1
                }
            }
            guard !removedFlatIndices.isEmpty, survivorIndex == newPhotos.count else { return false }

            let oldSections = sections
            var removedPerSection = [Int](repeating: 0, count: oldSections.count)
            var removedIndexPaths: [IndexPath] = []
            for flatIndex in removedFlatIndices {
                guard let indexPath = indexPath(forFlatIndex: flatIndex) else { return false }
                removedPerSection[indexPath.section] += 1
                removedIndexPaths.append(indexPath)
            }
            var emptiedSections = IndexSet()
            for (section, resolved) in oldSections.enumerated()
            where removedPerSection[section] == resolved.range.count {
                emptiedSections.insert(section)
            }
            // UIKit rejects item deletions inside a section that is itself
            // being deleted.
            removedIndexPaths.removeAll { emptiedSections.contains($0.section) }

            let newSections = Self.resolvedSections(
                for: newParent, columns: resolvedColumns(newParent.columnCount)
            )
            guard newSections.count == oldSections.count - emptiedSections.count else { return false }
            var newSection = 0
            for (section, resolved) in oldSections.enumerated() where !emptiedSections.contains(section) {
                guard newSections[newSection].range.count == resolved.range.count - removedPerSection[section],
                      newSections[newSection].title == resolved.title
                else { return false }
                newSection += 1
            }

            parent = newParent
            collectionView.performBatchUpdates {
                sections = newSections
                if !emptiedSections.isEmpty {
                    collectionView.deleteSections(emptiedSections)
                }
                if !removedIndexPaths.isEmpty {
                    collectionView.deleteItems(at: removedIndexPaths)
                }
            }
            return true
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
                switch granularity {
                case .day: return MetadataFormatter.dayHeader(date)
                case .month: return MetadataFormatter.monthHeader(date)
                case .year: return MetadataFormatter.yearHeader(date)
                }
            }
        }

        // MARK: Layout

        /// Width the cells actually get: the collection view minus whatever
        /// the adjusted content inset takes horizontally. Equal to the bounds
        /// width on a plain portrait iPhone; smaller wherever a horizontal
        /// safe area exists (iPhone Duo's vertical navigation, Split View),
        /// where measuring off the bounds would size a row too wide to fit.
        private var contentWidth: CGFloat {
            guard let collectionView else { return 0 }
            return max(
                0,
                collectionView.bounds.width
                    - collectionView.adjustedContentInset.left
                    - collectionView.adjustedContentInset.right
            )
        }

        /// Columns to draw for the stored density at the current width. Identity
        /// on compact width; scaled on a regular-width display (iPhone Duo's
        /// inner screen) so tiles keep their size instead of doubling.
        func resolvedColumns(_ density: Int) -> Int {
            guard let collectionView else { return GridDensity.clamped(density) }
            return GridDensity.columns(
                forDensity: density,
                width: contentWidth,
                isRegularWidth: collectionView.traitCollection.horizontalSizeClass == .regular
            )
        }

        /// The window grew or shrank enough to change the drawn column count —
        /// swap the layout. Never during a pinch: starting a layout change
        /// while an interactive transition is live corrupts UIKit's state.
        func reapplyLayoutIfColumnsChanged() {
            guard let collectionView, transitionLayout == nil, !isSettling,
                  contentWidth > 0
            else { return }
            let columns = resolvedColumns(parent.columnCount)
            guard (collectionView.collectionViewLayout as? GridFlowLayout)?.columns != columns
            else { return }
            parent.photoLibrary.stopCachingAllThumbnails()
            collectionView.setCollectionViewLayout(
                makeLayout(density: parent.columnCount), animated: false
            ) { [weak self] _ in
                guard let self else { return }
                let before = sections
                rebuildSections()
                if sections != before {
                    collectionView.reloadData()
                } else {
                    reconfigureVisibleCells(collectionView)
                }
            }
        }

        /// Flow layout, not compositional: `UICollectionViewTransitionLayout`
        /// (the pinch mechanic) only supports flow-style layouts —
        /// `startInteractiveTransition` with a compositional layout returns
        /// the target layout unwrapped and crashes on `transitionProgress`.
        /// A uniform square grid needs nothing compositional anyway, and
        /// pinned date headers exist here too
        /// (`sectionHeadersPinToVisibleBounds`).
        func makeLayout(density: Int) -> UICollectionViewFlowLayout {
            let layout = GridFlowLayout()
            layout.columns = resolvedColumns(density)
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
            let columns = (collectionViewLayout as? GridFlowLayout)?.columns
                ?? resolvedColumns(parent.columnCount)
            let width = contentWidth
            guard let flatIndex = flatIndex(for: indexPath) else {
                return Self.cellSize(width: width, columns: columns)
            }
            return itemSize(width: width, columns: columns, flatIndex: flatIndex)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForHeaderInSection section: Int
        ) -> CGSize {
            guard sections.indices.contains(section),
                  let title = sections[section].title, !title.isEmpty
            else { return .zero }
            return CGSize(width: contentWidth, height: 32)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout collectionViewLayout: UICollectionViewLayout,
            referenceSizeForFooterInSection section: Int
        ) -> CGSize {
            guard let lastSection = sections.indices.last, section == lastSection,
                  let text = parent.trailingFooterText, !text.isEmpty
            else { return .zero }
            return CGSize(width: contentWidth, height: 48)
        }

        /// Square cell side for a column count, floored to pixel precision so
        /// a row of N cells + gaps never exceeds the width (which would wrap).
        static func cellSize(width: CGFloat, columns: Int) -> CGSize {
            GridThumbnailTarget.cellSize(width: width, columns: columns)
        }

        /// Portrait cap for the 1-column aspect layout: a photo taller than
        /// this (relative to its width) is shown at this ratio so one frame
        /// never scrolls for pages. Landscape keeps its natural ratio.
        private static var oneColumnMaxAspect: CGFloat { 1.9 }

        /// One cell's point size. Square at every density except 1 column,
        /// where each cell takes the photo's own aspect ratio (full-width,
        /// natural height) — the Photos "one-up" look, scrolling vertically.
        /// Falls back to square when pixel dimensions are unknown.
        func itemSize(width: CGFloat, columns: Int, flatIndex: Int) -> CGSize {
            guard columns == 1 else { return Self.cellSize(width: width, columns: columns) }
            guard parent.photos.indices.contains(flatIndex),
                  let pixelWidth = parent.photos[flatIndex].pixelWidth,
                  let pixelHeight = parent.photos[flatIndex].pixelHeight,
                  pixelWidth > 0, pixelHeight > 0
            else { return CGSize(width: width, height: width) }
            let aspect = min(CGFloat(pixelHeight) / CGFloat(pixelWidth), Self.oneColumnMaxAspect)
            let scale = ActiveDisplay.scale
            let height = max(1, (width * aspect * scale).rounded(.down) / scale)
            return CGSize(width: width, height: height)
        }

        /// Cell width in points for the current committed layout — sizes
        /// thumbnail requests and gates the metadata line.
        private var cellPointWidth: CGFloat {
            Self.cellSize(
                width: contentWidth,
                columns: resolvedColumns(parent.columnCount)
            ).width
        }

        private var thumbnailTargetSize: CGSize {
            GridThumbnailTarget.thumbnailSize(cellPointWidth: cellPointWidth)
        }

        private var detailTargetSize: CGSize { ActiveDisplay.pixelSize() }

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
            // Per-item so a 1-column cell requests a rendition at its own
            // (tall) aspect, not a square that would crop in the frame.
            let columns = resolvedColumns(parent.columnCount)
            let size = itemSize(width: contentWidth, columns: columns, flatIndex: flatIndex)
            let scale = ActiveDisplay.scale
            let target = CGSize(width: size.width * scale, height: size.height * scale)
            cell.configure(
                item: item,
                asset: asset,
                cellWidth: size.width,
                targetSize: target,
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
            if kind == UICollectionView.elementKindSectionFooter {
                let view = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind, withReuseIdentifier: Self.footerReuseId, for: indexPath
                ) as! UICollectionViewCell
                view.contentConfiguration = UIHostingConfiguration {
                    GridTrailingFooter(text: parent.trailingFooterText ?? "")
                }
                .margins(.all, 0)
                return view
            }

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
            if flatIndex >= parent.photos.count - 30 {
                parent.onNearEnd()
            }
        }

        /// Touch-down on a tile: warm the screen-sized local rendition of that
        /// one asset so a tap opens the viewer on a sharp first frame. The
        /// request is left running through unhighlight — the tap that follows
        /// is what it is for — and replaced by the next highlight.
        func collectionView(
            _ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath
        ) {
            guard let flatIndex = flatIndex(for: indexPath),
                  let asset = parent.assetProvider(flatIndex, parent.photos[flatIndex]),
                  asset.mediaType == .image
            else { return }
            guard highlightPreheat?.asset.localIdentifier != asset.localIdentifier else { return }
            cancelHighlightPreheat()
            let requestId = parent.photoLibrary.requestBestLocalImage(
                for: asset, targetSize: detailTargetSize, contentMode: .aspectFit
            ) { _ in }
            highlightPreheat = (asset, requestId)
        }

        func cancelHighlightPreheat() {
            guard let highlightPreheat else { return }
            parent.photoLibrary.cancelThumbnailRequest(highlightPreheat.requestId)
            self.highlightPreheat = nil
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateScrubber(scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            endAnchorTracking()
            parent.onUserScroll()
        }

        /// Feeds the date scrubber: where the grid is, and which section title
        /// sits under the top of the viewport. Skipped while the user is
        /// dragging the handle, so the handle does not chase the scroll it is
        /// itself causing.
        func updateScrubber(_ scrollView: UIScrollView) {
            guard let scrubber = parent.scrubber else { return }
            let span = scrollView.contentSize.height
                - scrollView.bounds.height
                + scrollView.adjustedContentInset.top
                + scrollView.adjustedContentInset.bottom
            scrubber.isScrollable = span > 1
            guard !scrubber.isScrubbing else {
                scrubber.label = topVisibleSectionTitle(scrollView) ?? scrubber.label
                return
            }
            if span > 1 {
                let y = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
                scrubber.progress = min(max(Double(y / span), 0), 1)
            }
            scrubber.label = topVisibleSectionTitle(scrollView) ?? ""
        }

        /// Title of the section whose items are under the top edge of the
        /// viewport — nil when the grid has no headers at all.
        private func topVisibleSectionTitle(_ scrollView: UIScrollView) -> String? {
            guard let collectionView = scrollView as? UICollectionView,
                  !sections.isEmpty
            else { return nil }
            let probe = CGPoint(
                x: collectionView.adjustedContentInset.left + 8,
                y: collectionView.contentOffset.y
                    + collectionView.adjustedContentInset.top + 8
            )
            if let indexPath = collectionView.indexPathForItem(at: probe),
               sections.indices.contains(indexPath.section) {
                return sections[indexPath.section].title
            }
            // Between rows (or over a pinned header): fall back to the topmost
            // visible cell rather than showing nothing.
            return collectionView.indexPathsForVisibleItems
                .min()
                .flatMap { sections.indices.contains($0.section) ? sections[$0.section].title : nil }
        }

        func scrollViewDidEndDragging(
            _ scrollView: UIScrollView,
            willDecelerate decelerate: Bool
        ) {
            if !decelerate { upgradeVisibleThumbnails(scrollView) }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            upgradeVisibleThumbnails(scrollView)
        }

        /// The grid came to rest: tiles whose local final was only a small
        /// iCloud proxy now fetch the cell-sized rendition over the network.
        /// Never during a scroll, so flinging through the library still costs
        /// no downloads.
        private func upgradeVisibleThumbnails(_ scrollView: UIScrollView) {
            guard let collectionView = scrollView as? UICollectionView else { return }
            for cell in collectionView.visibleCells {
                (cell as? PhotoGridCell)?.upgradeThumbnailIfIdle()
            }
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

        // MARK: Context menu

        /// Photos' tile menu: a zoomed preview of the tile plus the actions
        /// that apply to a single photo. Suppressed while selecting, where a
        /// press means "extend the range" instead.
        func collectionView(
            _ collectionView: UICollectionView,
            contextMenuConfigurationForItemAt indexPath: IndexPath,
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard !parent.isSelecting,
                  let provider = parent.contextMenuProvider,
                  let flatIndex = flatIndex(for: indexPath)
            else { return nil }
            let item = parent.photos[flatIndex]
            return UIContextMenuConfiguration(identifier: item.assetId as NSString) {
                // No custom preview controller: UIKit lifts the cell itself,
                // which is the zoomed thumbnail Photos shows.
                nil
            } actionProvider: { _ in
                provider(item)
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
                endAnchorTracking()
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
                shouldSelectOnSwipe = true
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
                endAnchorTracking()
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
                to: makeLayout(density: target)
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
                    swipeActivation = SwipeSelection.activation(
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
                        shouldSelectOnSwipe = !appliedSelectedIds.contains(
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
                  let shouldSelect = shouldSelectOnSwipe,
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
            let delta = SwipeSelection.autoScrollDelta(
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
            shouldSelectOnSwipe = nil
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

/// Asks the coordinator to (re-)apply the opening anchor on every layout,
/// safe-area and adjusted-inset change until the user first touches the grid.
///
/// One shot is not enough: the representable is created with a zero frame,
/// and even at the first pass with real bounds UIKit has not necessarily
/// propagated the window safe area yet. The screens `.ignoresSafeArea()` and
/// let automatic content-inset adjustment clear the tab bar, so anchoring
/// against a not-yet-settled `adjustedContentInset` put the newest row behind
/// the tab bar — and the next unrelated `anchor()` (the full-library phase
/// replacing the first-paint slice) then shifted the whole grid by that
/// amount, which read as the grid re-flowing seconds after launch.
private final class GridCollectionView: UICollectionView {
    var onAnchorNeeded: (() -> Void)?
    /// Fired when the width available to cells changes (fold, Split View,
    /// rotation), so the coordinator can re-resolve the column count.
    var onContentWidthChange: (() -> Void)?
    private var reportedContentWidth: CGFloat = 0
    /// Cleared by the coordinator on the first user interaction — from then on
    /// the scroll position belongs to the user, not to the anchor.
    var needsAnchor = true

    override func layoutSubviews() {
        super.layoutSubviews()
        reportContentWidthIfChanged()
        requestAnchor()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        reportContentWidthIfChanged()
        requestAnchor()
    }

    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        reportContentWidthIfChanged()
        requestAnchor()
    }

    private func reportContentWidthIfChanged() {
        let width = bounds.width - adjustedContentInset.left - adjustedContentInset.right
        guard width > 0, width != reportedContentWidth else { return }
        reportedContentWidth = width
        onContentWidthChange?()
    }

    private func requestAnchor() {
        guard needsAnchor, bounds.height > 0 else { return }
        onAnchorNeeded?()
    }
}

// MARK: - Section header

/// Pinned section header: a compact glass capsule token, legible over
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
            .glassBackground(Capsule())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Low-priority informational footer shown only after the final grid item.
/// Tertiary system text adapts to Light/Dark Mode without competing with the
/// photos or the active-condition controls.
private struct GridTrailingFooter: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityLabel(text)
    }
}

// MARK: - Cell

/// One square grid cell, pure UIKit for scroll performance: thumbnail +
/// file-type badge + bottom metadata line over a gradient + video duration +
/// selection UI.
final class PhotoGridCell: UICollectionViewCell {
    static var reuseId: String { "PhotoGridCell" }

    /// Cells narrower than this hide the metadata line.
    private static var metadataMinCellWidth: CGFloat { 90 }

    private let imageView = UIImageView()
    private let gradient = CAGradientLayer()
    private let metadataLabel = UILabel()
    private let fileTypeBadge = UILabel()
    private let videoBadge = UILabel()
    private let selectionBorder = UIView()
    private let selectionBadge = UIImageView()

    private var requestId: PHImageRequestID?
    private var requestedAssetId: String?
    private var lastRequestedPixelWidth: CGFloat = 0
    /// The asset and pixel size of the current request, kept so the idle-time
    /// network upgrade asks for exactly what the local pass asked for.
    private var requestedAsset: PHAsset?
    private var requestedTargetSize: CGSize = .zero
    /// Next rung of the thumbnail ladder (see `PhotoLibraryService.requestThumbnail`)
    /// for a tile whose last final was undersized. Runs only while the grid is
    /// at rest; each rung is attempted once per configure, so an offline
    /// device does not retry the same tile at every scroll stop.
    private enum UpgradePass {
        case exactLocal
        case network
    }
    private var pendingUpgrade: UpgradePass?
    private var upgradeRequestId: PHImageRequestID?
    private weak var photoLibrary: PhotoLibraryService?
    /// Identity + in-flight lookup of the lazy badge fill: the fetch result
    /// only applies while the cell still shows the asset it was started for.
    private var configuredAssetId: String?
    private var badgeFetchTask: Task<Void, Never>?
    private var accessibilityMediaLabel = "Photo"
    private var accessibilityMetadataLine: String?
    private var accessibilityFileType: String?

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

        fileTypeBadge.font = .systemFont(ofSize: 9, weight: .bold)
        fileTypeBadge.textColor = .white
        fileTypeBadge.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        fileTypeBadge.layer.cornerRadius = 4
        fileTypeBadge.clipsToBounds = true
        fileTypeBadge.textAlignment = .center
        contentView.addSubview(fileTypeBadge)

        videoBadge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        videoBadge.textColor = .white
        videoBadge.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        videoBadge.layer.cornerRadius = 8
        videoBadge.clipsToBounds = true
        videoBadge.textAlignment = .center
        contentView.addSubview(videoBadge)

        selectionBorder.layer.borderWidth = 3
        selectionBorder.layer.borderColor = AppAccent.uiColor.cgColor
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
        let fileTypeSize = fileTypeBadge.intrinsicContentSize
        let fileTypeWidth = fileTypeBadge.isHidden
            ? 0
            : min(fileTypeSize.width + 10, contentView.bounds.width - 8)
        fileTypeBadge.frame = CGRect(
            x: 4, y: 4,
            width: max(0, fileTypeWidth), height: 16
        )

        let badgeSize = videoBadge.intrinsicContentSize
        let videoWidth = min(badgeSize.width + 10, contentView.bounds.width - 8)
        let videoX = contentView.bounds.width - videoWidth - 4
        // Dense grids cannot fit both labels on one line. Keep file type in
        // its promised top-left position and drop duration to the next row.
        let videoY: CGFloat = videoX < fileTypeBadge.frame.maxX + 4 ? 22 : 4
        videoBadge.frame = CGRect(
            x: videoX, y: videoY,
            width: max(0, videoWidth), height: 16
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
        imageView.alpha = 1
        requestedAssetId = nil
        requestedAsset = nil
        requestedTargetSize = .zero
        lastRequestedPixelWidth = 0
        pendingUpgrade = nil
        badgeFetchTask?.cancel()
        badgeFetchTask = nil
        configuredAssetId = nil
        fileTypeBadge.text = nil
        fileTypeBadge.isHidden = true
        accessibilityMetadataLine = nil
        accessibilityFileType = nil
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
        accessibilityMediaLabel = item.mediaType == 2 ? "Video" : "Photo"
        applyFileTypeBadge(
            displayOptions.showsFileTypeBadge ? item.fileTypeBadgeText : nil
        )

        // Item is missing exposure or source filename fields — typically a
        // tile the index run hasn't reached (or has filled since this list
        // loaded). Ask for a fresh row and update just this cell when it arrives.
        if let lazyMetadataProvider,
           Self.needsLazyMetadata(item, options: displayOptions, showsMetadataLine: showsBadge) {
            let assetId = item.assetId
            badgeFetchTask = Task { [weak self] in
                guard let fetched = await lazyMetadataProvider(assetId) else { return }
                guard let self, !Task.isCancelled,
                      self.configuredAssetId == assetId else { return }
                if showsBadge {
                    self.applyBadge(line: Self.metadataLine(for: fetched, options: displayOptions))
                }
                self.applyFileTypeBadge(
                    displayOptions.showsFileTypeBadge ? fetched.fileTypeBadgeText : nil
                )
            }
        }

        if let asset, asset.mediaType == .video {
            videoBadge.text = asset.duration > 0
                ? "▶ \(MetadataFormatter.duration(asset.duration))" : "▶"
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
        // Selected thumbnail dims slightly, iOS Photos style, so the accent
        // border and check read clearly over it.
        imageView.alpha = (isSelecting && isSelected) ? 0.82 : 1
        let base = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        if isSelected {
            // White check on an accent-filled disc, iOS Photos style. Palette:
            // layer 0 = check (white), layer 1 = filled circle (accent).
            selectionBadge.image = UIImage(systemName: "checkmark.circle.fill")
            selectionBadge.preferredSymbolConfiguration = base.applying(
                UIImage.SymbolConfiguration(
                    paletteColors: [.white, AppAccent.uiColor]
                )
            )
        } else {
            selectionBadge.image = UIImage(systemName: "circle")
            selectionBadge.preferredSymbolConfiguration = base
            selectionBadge.tintColor = .white
        }
    }

    /// Single write point for the metadata overlay (sync configure and the
    /// async lazy fill), so label, gradient, and accessibility stay in step.
    private func applyBadge(line: String?) {
        metadataLabel.text = line
        metadataLabel.isHidden = line == nil
        gradient.isHidden = line == nil
        accessibilityMetadataLine = line
        updateAccessibilityLabel()
    }

    private func applyFileTypeBadge(_ text: String?) {
        fileTypeBadge.text = text
        fileTypeBadge.isHidden = text == nil
        accessibilityFileType = text
        updateAccessibilityLabel()
        setNeedsLayout()
    }

    private func updateAccessibilityLabel() {
        isAccessibilityElement = true
        let components: [String?] = [
            accessibilityMediaLabel,
            accessibilityFileType.map { "file type \($0)" },
            accessibilityMetadataLine,
        ]
        accessibilityLabel = components.compactMap { $0 }.joined(separator: ", ")
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
            requestedAsset = nil
            requestedTargetSize = .zero
            lastRequestedPixelWidth = 0
            pendingUpgrade = nil
            return
        }
        let assetChanged = asset.localIdentifier != requestedAssetId
        let needsUpgrade = targetSize.width > lastRequestedPixelWidth * 1.4
        guard assetChanged || needsUpgrade else { return }
        cancelRequest()
        pendingUpgrade = nil
        // A sharp rendition of this exact size already delivered once: paint it
        // now instead of clearing to grey and letting opportunistic delivery
        // fade a soft preview in first. This is what keeps a `reloadData` (the
        // first-paint slice growing into the whole library) from softening
        // every visible tile — cells are reused for different tiles there, so
        // they all clear and re-request at once.
        requestedAssetId = asset.localIdentifier
        requestedAsset = asset
        requestedTargetSize = targetSize
        lastRequestedPixelWidth = targetSize.width
        if let cached = photoLibrary.cachedThumbnail(
            for: asset.localIdentifier, width: targetSize.width
        ) {
            // Right asset, right pixel size — nothing left to ask PhotoKit for.
            imageView.image = cached
            return
        }
        if assetChanged { imageView.image = nil }
        // First rung: PhotoKit's nearest ready-made rendition, local-only — the
        // same request the prefetcher warms, so a scrolled-into tile is
        // usually a cache hit. Scrolling never triggers iCloud downloads.
        requestId = photoLibrary.requestThumbnail(
            for: asset, targetSize: targetSize, resizeMode: .fast, allowNetwork: false
        ) { [weak self] image, delivery in
            guard let self, self.requestedAssetId == asset.localIdentifier else { return }
            if let image {
                self.imageView.image = image
            }
            guard delivery.isFinal else { return }
            self.requestId = nil
            // Nearest rendition came up short of the cell. Keep it on screen
            // and climb the ladder once the grid is not moving.
            if !delivery.isSharp {
                self.pendingUpgrade = .exactLocal
                self.upgradeThumbnailIfIdle()
            }
        }
    }

    /// Runs the pending ladder rung — exact local, then network — for a tile
    /// whose last final was undersized. Only while the grid is at rest: the
    /// coordinator calls it when scrolling stops, and a final callback calls
    /// it directly when the grid was already still.
    func upgradeThumbnailIfIdle() {
        guard let pass = pendingUpgrade, upgradeRequestId == nil,
              let asset = requestedAsset, let photoLibrary
        else { return }
        if let scrollView = superview as? UIScrollView,
           scrollView.isDragging || scrollView.isDecelerating {
            return
        }
        pendingUpgrade = nil
        let allowNetwork = pass == .network
        upgradeRequestId = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: requestedTargetSize,
            resizeMode: .exact,
            allowNetwork: allowNetwork
        ) { [weak self] image, delivery in
            guard let self, self.requestedAssetId == asset.localIdentifier else { return }
            // Opportunistic delivery repeats the proxy first; only a rendition
            // with the cell's pixels is worth repainting over what is shown.
            if let image, delivery.isSharp {
                self.imageView.image = image
            }
            guard delivery.isFinal else { return }
            self.upgradeRequestId = nil
            // Exact local still short: the on-device best is an Optimize
            // Storage proxy, so the last rung fetches the cell-sized rendition.
            if !delivery.isSharp, !allowNetwork {
                self.pendingUpgrade = .network
                self.upgradeThumbnailIfIdle()
            }
        }
    }

    private func cancelRequest() {
        if let requestId {
            photoLibrary?.cancelThumbnailRequest(requestId)
        }
        requestId = nil
        if let upgradeRequestId {
            photoLibrary?.cancelThumbnailRequest(upgradeRequestId)
        }
        upgradeRequestId = nil
    }

    /// Only real values — never placeholders like `ISO -- · --mm`.
    private static func metadataLine(
        for item: some PhotoGridDisplayable, options: GridMetadataDisplayOptions
    ) -> String? {
        let focalValue = options.showsEquivalentFocalLength
            ? (item.equivalentFocalLength ?? item.focalLength)
            : item.focalLength
        return MetadataFormatter.metadataLine([
            options.showsISO ? item.iso.flatMap(MetadataFormatter.iso) : nil,
            options.showsFocal ? focalValue.flatMap(MetadataFormatter.focalLength) : nil,
            options.showsAperture ? item.aperture.flatMap(MetadataFormatter.aperture) : nil,
            options.showsShutter ? item.shutterSpeedDisplay : nil,
            options.showsMegapixels ? item.megapixels.flatMap(MetadataFormatter.megapixels) : nil,
            options.showsFileSize ? item.fileSize.flatMap(MetadataFormatter.fileSize) : nil,
        ])
    }

    /// Whether the visible cell needs one lazy row refresh. A data check, not
    /// a formatted-line check: hidden display fields must not cause needless
    /// fetches for rows that are already filled.
    private static func needsLazyMetadata(
        _ item: some PhotoGridDisplayable,
        options: GridMetadataDisplayOptions,
        showsMetadataLine: Bool
    ) -> Bool {
        let needsOverlay = showsMetadataLine
            && item.iso == nil && item.aperture == nil && item.shutterSpeedDisplay == nil
            && item.focalLength == nil && item.equivalentFocalLength == nil
        let needsFileType = options.showsFileTypeBadge && item.originalFilename == nil
        return needsOverlay || needsFileType
    }
}

/// Snapshot of the Settings display toggles for the tile overlay (same
/// UserDefaults keys as the Settings screen's @AppStorage). Loaded once and
/// refreshed on the defaults-change notification instead of five defaults
/// reads per cell configure.
struct GridMetadataDisplayOptions: Equatable {
    var showsFileTypeBadge: Bool
    var showsISO: Bool
    var showsAperture: Bool
    var showsShutter: Bool
    var showsFocal: Bool
    var showsMegapixels: Bool
    var showsFileSize: Bool
    var showsEquivalentFocalLength: Bool

    static func load(from defaults: UserDefaults = .standard) -> GridMetadataDisplayOptions {
        func flag(_ key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) as? Bool ?? defaultValue
        }
        return GridMetadataDisplayOptions(
            showsFileTypeBadge: flag(SettingsKeys.showFileTypeBadge, default: true),
            showsISO: flag("display.showISO", default: true),
            showsAperture: flag("display.showAperture", default: true),
            showsShutter: flag("display.showShutter", default: false),
            showsFocal: flag("display.showFocal", default: true),
            showsMegapixels: flag("display.showMegapixels", default: false),
            showsFileSize: flag("display.showFileSize", default: false),
            showsEquivalentFocalLength: flag("display.focalStyleEquivalent", default: false)
        )
    }
}
