import Photos
import SwiftUI
import UIKit

/// UIKit-backed photo grid shared by Library and Album Detail — the SwiftUI
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
    /// False renders one flat grid without date headers (non-date sorts).
    let isDateSectioned: Bool
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
        context.coordinator.apply(self, isInitial: false)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource,
        UICollectionViewDelegateFlowLayout, UICollectionViewDataSourcePrefetching,
        UIGestureRecognizerDelegate {

        static var headerReuseId: String { "PhotoGridHeader" }

        var parent: PhotoGridCollectionView
        weak var collectionView: UICollectionView?

        /// Sections currently driving the layout/data source. One synthetic
        /// full-range section when not date-sectioned.
        private var sections: [PhotoGridSection] = []
        private var appliedContentVersion: Int?
        private var appliedContentRefreshVersion: Int?
        /// Ordered asset ids last handed to the collection view. Drives the
        /// reload decision: any change to the list (not just its count) forces
        /// a full `reloadData`, so the rendered cells never lag the snapshot
        /// `didSelectItemAt` taps against.
        private var appliedIds: [String] = []
        private var appliedColumns = 0
        private var appliedJumpToken: Int?
        private var appliedSelecting = false
        private var appliedSelectedIds: [String] = []

        // Pinch state
        private var transitionLayout: UICollectionViewTransitionLayout?
        private var transitionBaselineScale: CGFloat = 1
        private var transitionDelta = 0
        /// True from finish/cancel until UIKit's completion callback — no new
        /// interactive transition may start in that window (see handlePinch).
        private var isSettling = false

        // Swipe-select state
        private var swipeActivation = SwipeSelectionEngine.Activation.undecided
        private var swipeStartId: String?

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
            if let defaultsObserver {
                NotificationCenter.default.removeObserver(defaultsObserver)
            }
        }

        // MARK: Input diffing

        func apply(_ newParent: PhotoGridCollectionView, isInitial: Bool) {
            parent = newParent
            guard let collectionView else { return }

            let contentReplaced = newParent.contentVersion != appliedContentVersion
            let newIds = newParent.photos.map(\.assetId)
            let listChanged = newIds != appliedIds
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
            if contentReplaced || listChanged || isInitial {
                rebuildSections()
                collectionView.reloadData()
                if contentReplaced || isInitial {
                    collectionView.layoutIfNeeded()
                    anchor(collectionView)
                }
                appliedContentVersion = newParent.contentVersion
                appliedIds = newIds
            } else if refreshed {
                // Same list, overlays changed — re-render visible tiles in
                // place. No reloadData/anchor, so the scroll spot is kept.
                rebuildSections()
                reconfigureVisibleCells(collectionView)
            }
            appliedContentRefreshVersion = newParent.contentRefreshVersion

            if let token = appliedJumpToken, token != newParent.jumpToNewestToken {
                anchor(collectionView)
            }
            appliedJumpToken = newParent.jumpToNewestToken

            if newParent.isSelecting != appliedSelecting
                || newParent.selectedIds != appliedSelectedIds {
                appliedSelecting = newParent.isSelecting
                appliedSelectedIds = newParent.selectedIds
                reconfigureVisibleCells(collectionView)
            }
            pinchRecognizer?.isEnabled = !newParent.isSelecting
            swipeRecognizer?.isEnabled = newParent.isSelecting
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

        private func reconfigureVisibleCells(_ collectionView: UICollectionView) {
            for indexPath in collectionView.indexPathsForVisibleItems {
                guard let cell = collectionView.cellForItem(at: indexPath) as? PhotoGridCell,
                      let flatIndex = flatIndex(for: indexPath)
                else { continue }
                configure(cell, at: flatIndex)
            }
        }

        // MARK: Sections

        private func rebuildSections() {
            guard parent.isDateSectioned, !parent.photos.isEmpty else {
                sections = parent.photos.isEmpty
                    ? []
                    : [PhotoGridSection(kind: .undated, range: 0..<parent.photos.count)]
                return
            }
            sections = PhotoGridSectionBuilder.sections(
                creationDates: parent.photos.map(\.creationDateValue),
                granularity: GridDensity.granularity(forColumns: parent.columnCount)
            )
        }

        private func flatIndex(for indexPath: IndexPath) -> Int? {
            guard sections.indices.contains(indexPath.section) else { return nil }
            let flat = sections[indexPath.section].range.lowerBound + indexPath.item
            return parent.photos.indices.contains(flat) ? flat : nil
        }

        private func headerTitle(for section: PhotoGridSection) -> String? {
            guard parent.isDateSectioned else { return nil }
            switch section.kind {
            case .undated:
                return String(localized: "No Date")
            case .date(let date):
                let granularity = GridDensity.granularity(forColumns: parent.columnCount)
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
            layout.sectionHeadersPinToVisibleBounds = parent.isDateSectioned
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
            parent.isDateSectioned
                ? CGSize(width: collectionView.bounds.width, height: 32)
                : .zero
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
            // 2x is indistinguishable at grid-cell size; 3x devices would pay
            // 2.25x the decode/memory cost for nothing.
            let scale = min(UIScreen.main.scale, 2)
            let side = cellPointWidth * scale
            return CGSize(width: side, height: side)
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
                isSelected: parent.selectedIds.contains(item.assetId),
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
                ? headerTitle(for: sections[indexPath.section]) ?? ""
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

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            parent.onUserScroll()
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
            parent.photoLibrary.stopCachingThumbnails(
                for: assets(at: indexPaths), targetSize: thumbnailTargetSize
            )
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
            gestureRecognizer === swipeRecognizer
        }

        @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began,
                  let collectionView,
                  let indexPath = collectionView.indexPathForItem(
                      at: recognizer.location(in: collectionView)
                  ),
                  let flatIndex = flatIndex(for: indexPath)
            else { return }
            parent.onLongPress(parent.photos[flatIndex])
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
                // regroup and reload so headers and item counts match.
                let before = sections.count
                rebuildSections()
                if sections.count != before {
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
            guard let collectionView else { return }
            switch recognizer.state {
            case .began:
                swipeActivation = .undecided
                swipeStartId = nil
            case .changed:
                let translation = recognizer.translation(in: collectionView)
                if swipeActivation == .undecided {
                    swipeActivation = SwipeSelectionEngine.activation(
                        translation: CGSize(width: translation.x, height: translation.y)
                    )
                    if swipeActivation == .select {
                        collectionView.isScrollEnabled = false
                        parent.onSwipeEvent(.began)
                    }
                }
                guard swipeActivation == .select else { return }
                let location = recognizer.location(in: collectionView)
                guard let indexPath = collectionView.indexPathForItem(at: location),
                      let flatIndex = flatIndex(for: indexPath)
                else { return }
                let currentId = parent.photos[flatIndex].assetId
                if swipeStartId == nil {
                    swipeStartId = currentId
                }
                guard let startId = swipeStartId,
                      let startIndex = parent.photos.firstIndex(where: { $0.assetId == startId })
                else { return }
                let range = min(startIndex, flatIndex)...max(startIndex, flatIndex)
                let rangeIds = parent.photos[range].map(\.assetId)
                // Starting on an already-selected tile deselects the range.
                let select = !parent.selectedIds.contains(startId)
                parent.onSwipeEvent(.changed(rangeIds: rangeIds, select: select))
            case .ended, .cancelled, .failed:
                if swipeActivation == .select {
                    parent.onSwipeEvent(.ended)
                    collectionView.isScrollEnabled = true
                }
                swipeActivation = .undecided
                swipeStartId = nil
            default:
                break
            }
        }
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

/// Pinned date header: a compact glass capsule chip, legible over
/// scrolling photos without covering the full row width. Hosted in the
/// collection view's supplementary views via UIHostingConfiguration;
/// On This Day renders its own headers.
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
/// Mirrors the SwiftUI `PhotoGridTile` (which On This Day still uses).
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

        selectionBorder.isHidden = !(isSelecting && isSelected)
        selectionBadge.isHidden = !isSelecting
        selectionBadge.image = UIImage(
            systemName: isSelected ? "checkmark.circle.fill" : "circle"
        )
        selectionBadge.tintColor = isSelected ? .tintColor : .white

        requestThumbnail(asset: asset, targetSize: targetSize)
        setNeedsLayout()
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
