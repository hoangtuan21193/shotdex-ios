import Photos
import SwiftUI
import UIKit

/// The Media panel's grid (FS-12.09 §3–§5): a `UICollectionView` over the
/// library's lazy fetch result rather than a SwiftUI grid over an array —
/// 55,000 items are an index into PhotoKit here, never a list of objects —
/// and a UIKit view because the hold-to-drag that will live on it has to be
/// a recognizer on the scroll view itself (SwiftUI gestures die inside a
/// `UIScrollView`'s hosted content).
///
/// Thumbnails go through `PhotoLibraryService` like every other grid in the
/// app: the cell's own size times the screen scale, the fast local rendition
/// while scrolling, and a prefetch window of a screen either side.
struct VideoMediaGridView: UIViewRepresentable {
    let library: VideoMediaLibrary
    /// Changes whenever the fetch does, so the grid reloads.
    let revision: Int
    let metrics: VideoMediaGridMetrics
    /// How many times each library item is in the video (FS-12.09 §4).
    var uses: [String: Int] = [:]
    /// Select's picks: their 1-based numbers by library id.
    var pickNumbers: [String: Int] = [:]
    var bottomInset: CGFloat = 0
    let onTap: (PHAsset) -> Void
    /// VoiceOver's Insert at Playhead and Select actions (§7) — the
    /// gestures' stand-ins.
    var onInsert: ((PHAsset) -> Void)?
    var onSelect: ((PHAsset) -> Void)?
    /// The hold-drag (§5), in window coordinates: lifted from a cell…
    var onDragBegan: ((PHAsset, CGPoint, CGRect, UIImage?) -> Void)?
    /// …moved — true when the seam under the finger changed…
    var onDragMoved: ((CGPoint) -> Bool)?
    /// …and let go.
    var onDragEnded: (() -> Void)?
    /// The pointer over a cell (iPad, FS-12.17b §6): the asset, how far
    /// across the cell, and the cell's thumbnail — nil when it leaves.
    var onSkim: ((PHAsset, Double, CGImage?) -> Void)?
    var onSkimEnd: (() -> Void)?
    /// Skimming shows nothing in the cells while the project plays.
    var isSkimPaused = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.showsHorizontalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.register(VideoMediaGridCell.self, forCellWithReuseIdentifier: VideoMediaGridCell.reuseIdentifier)
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.accessibilityIdentifier = "videoMediaGrid"
        context.coordinator.collectionView = view
        // Hold 0.3 s with the finger still (< 10pt) to lift a cell; moving
        // first is a scroll. A UIKit recognizer on the scroll view itself:
        // SwiftUI gestures never fire inside a UIScrollView's hosted
        // content (FS-12.09 §5).
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHold(_:)))
        hold.minimumPressDuration = VideoMediaGridView.holdDuration
        hold.allowableMovement = VideoMediaGridView.holdSlop
        hold.delegate = context.coordinator
        view.addGestureRecognizer(hold)
        // A pointer resting on a video skims it (FS-12.17b §6).
        let hover = UIHoverGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHover(_:)))
        view.addGestureRecognizer(hover)
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        let metricsChanged = coordinator.parent.metrics != metrics
        let usesChanged = coordinator.parent.uses != uses || coordinator.parent.pickNumbers != pickNumbers
        coordinator.parent = self
        view.contentInset.bottom = bottomInset
        view.verticalScrollIndicatorInsets.bottom = bottomInset
        if coordinator.shownRevision != revision {
            coordinator.shownRevision = revision
            coordinator.resetCaching()
            view.reloadData()
        } else if metricsChanged {
            view.collectionViewLayout.invalidateLayout()
        }
        #if DEBUG
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak coordinator] in coordinator?.debugSkimIfAsked() }
        #endif
        if usesChanged {
            // Marks only: the visible cells are re-marked in place, nothing
            // reloads and no thumbnail is asked for again.
            for case let cell as VideoMediaGridCell in view.visibleCells {
                cell.mark(uses: cell.assetID.flatMap { uses[$0] } ?? 0)
                cell.markPick(cell.assetID.flatMap { pickNumbers[$0] })
            }
        }
    }

    /// The hold that lifts a cell, and how far the finger may drift first.
    static let holdDuration: TimeInterval = 0.3
    static let holdSlop: CGFloat = 10

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.resetCaching()
    }

    @MainActor
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout,
        UIGestureRecognizerDelegate {
        var parent: VideoMediaGridView
        weak var collectionView: UICollectionView?
        var shownRevision = -1
        /// The assets PhotoKit is keeping warm, and at what size.
        private var cachedRange: Range<Int> = 0..<0
        private var cachedSize: CGSize = .zero

        init(_ parent: VideoMediaGridView) {
            self.parent = parent
        }

        private var library: VideoMediaLibrary { parent.library }

        private func cellSide(_ collectionView: UICollectionView) -> CGFloat {
            parent.metrics.cellSide(width: collectionView.bounds.width)
        }

        private func thumbnailSize(_ collectionView: UICollectionView) -> CGSize {
            let scale = collectionView.traitCollection.displayScale
            let side = cellSide(collectionView) * max(1, scale)
            return CGSize(width: side, height: side)
        }

        // MARK: Data source

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection _: Int) -> Int {
            library.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: VideoMediaGridCell.reuseIdentifier,
                for: indexPath
            ) as! VideoMediaGridCell
            guard let asset = library.asset(at: indexPath.item) else {
                cell.clear()
                return cell
            }
            cell.show(asset, index: indexPath.item)
            cell.actions = (
                insert: { [weak self] in self?.parent.onInsert?(asset) },
                select: { [weak self] in self?.parent.onSelect?(asset) }
            )
            cell.mark(uses: parent.uses[asset.localIdentifier] ?? 0)
            cell.markPick(parent.pickNumbers[asset.localIdentifier])
            let id = asset.localIdentifier
            let library = library.photoLibrary
            let target = thumbnailSize(collectionView)
            if let cached = library.cachedThumbnail(for: id, width: target.width) {
                cell.imageView.image = cached
            } else {
                cell.requestID = library.requestThumbnail(
                    for: asset,
                    targetSize: target,
                    resizeMode: .fast,
                    allowNetwork: false
                ) { [weak cell] image, _ in
                    guard let cell, cell.assetID == id, let image else { return }
                    cell.imageView.image = image
                }
            }
            return cell
        }

        // MARK: Layout

        func collectionView(
            _ collectionView: UICollectionView,
            layout _: UICollectionViewLayout,
            sizeForItemAt _: IndexPath
        ) -> CGSize {
            let side = cellSide(collectionView)
            return CGSize(width: side, height: side)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout _: UICollectionViewLayout,
            minimumInteritemSpacingForSectionAt _: Int
        ) -> CGFloat {
            parent.metrics.gap
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout _: UICollectionViewLayout,
            minimumLineSpacingForSectionAt _: Int
        ) -> CGFloat {
            parent.metrics.gap
        }

        func collectionView(
            _ collectionView: UICollectionView,
            layout _: UICollectionViewLayout,
            insetForSectionAt _: Int
        ) -> UIEdgeInsets {
            UIEdgeInsets(top: 0, left: parent.metrics.inset, bottom: 0, right: parent.metrics.inset)
        }

        // MARK: Hold-drag

        private let lift = UIImpactFeedbackGenerator(style: .light)
        private let tick = UISelectionFeedbackGenerator()
        private var isDragging = false

        @objc func handleHold(_ recognizer: UILongPressGestureRecognizer) {
            guard let collectionView else { return }
            let window = recognizer.location(in: nil)
            switch recognizer.state {
            case .began:
                let point = recognizer.location(in: collectionView)
                guard parent.onDragBegan != nil,
                      let indexPath = collectionView.indexPathForItem(at: point),
                      let asset = library.asset(at: indexPath.item),
                      let cell = collectionView.cellForItem(at: indexPath) as? VideoMediaGridCell
                else {
                    // Not on a cell: let this hold go.
                    recognizer.isEnabled = false
                    recognizer.isEnabled = true
                    return
                }
                // The scroll that was tracking the same finger lets go.
                collectionView.panGestureRecognizer.isEnabled = false
                collectionView.panGestureRecognizer.isEnabled = true
                isDragging = true
                cell.isLiftedSource = true
                lift.impactOccurred()
                tick.prepare()
                parent.onDragBegan?(asset, window, cell.convert(cell.bounds, to: nil), cell.imageView.image)
            case .changed:
                guard isDragging else { return }
                if parent.onDragMoved?(window) == true { tick.selectionChanged() }
            case .ended, .cancelled, .failed:
                guard isDragging else { return }
                isDragging = false
                for case let cell as VideoMediaGridCell in collectionView.visibleCells { cell.isLiftedSource = false }
                parent.onDragEnded?()
            default:
                break
            }
        }

        // MARK: Skim (FS-12.17b §6)

        private weak var skimmedCell: VideoMediaGridCell?
        private lazy var skimHint: UILabel = {
            let label = UILabel()
            label.text = VideoStudioCopy.skimHint
            label.font = .systemFont(ofSize: 13)
            label.textColor = UIColor(white: 1, alpha: 0.75)
            label.textAlignment = .center
            label.backgroundColor = UIColor(white: 0, alpha: 0.78)
            label.layer.cornerRadius = VideoMediaGridCell.skimHintSize.height / 2
            label.layer.masksToBounds = true
            label.isAccessibilityElement = false
            label.isUserInteractionEnabled = false
            return label
        }()

        @objc func handleHover(_ recognizer: UIHoverGestureRecognizer) {
            guard let collectionView else { return }
            switch recognizer.state {
            case .began, .changed:
                skim(at: recognizer.location(in: collectionView))
            default:
                endSkim()
            }
        }

        #if DEBUG
        /// `-VideoStudioDebugSkim "1,0.46"`: the pointer 46% across cell 1,
        /// through the same path a hover takes. The simulator's XCUITest
        /// hover sends no pointer to a `UIHoverGestureRecognizer` (measured
        /// 2026-10-08), so this is how the skim's screens are photographed.
        private var hasDebugSkimmed = false
        func debugSkimIfAsked() {
            guard !hasDebugSkimmed, let collectionView,
                  let spec = UserDefaults.standard.string(forKey: "VideoStudioDebugSkim")
            else { return }
            let parts = spec.split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2,
                  let cell = collectionView.cellForItem(at: IndexPath(item: Int(parts[0]), section: 0))
            else { return }
            hasDebugSkimmed = true
            skim(at: CGPoint(x: cell.frame.minX + cell.frame.width * parts[1], y: cell.frame.midY))
        }
        #endif

        private func skim(at point: CGPoint) {
            guard let collectionView else { return }
            guard !parent.isSkimPaused, !isDragging,
                  let indexPath = collectionView.indexPathForItem(at: point),
                  let asset = library.asset(at: indexPath.item),
                  let cell = collectionView.cellForItem(at: indexPath) as? VideoMediaGridCell
            else { return endSkim() }
            let fraction = Double((point.x - cell.frame.minX) / max(1, cell.frame.width))
            if skimmedCell !== cell { skimmedCell?.hideSkim() }
            skimmedCell = cell
            if asset.mediaType == .video {
                let time = VideoSkimMath.time(fraction: fraction, duration: asset.duration)
                cell.showSkim(fraction: fraction, time: VideoSkimMath.timeLabel(time))
            } else {
                cell.hideSkim()
            }
            placeHint(under: cell, in: collectionView)
            parent.onSkim?(asset, fraction, cell.imageView.image?.cgImage)
        }

        private func endSkim() {
            guard skimmedCell != nil || skimHint.superview != nil else { return }
            skimmedCell?.hideSkim()
            skimmedCell = nil
            skimHint.removeFromSuperview()
            parent.onSkimEnd?()
        }

        /// "Click adds · drag to place", 4 under the cell, its right edge 2
        /// in from the cell's (board F6_IL_HoverScrub).
        private func placeHint(under cell: UICollectionViewCell, in collectionView: UICollectionView) {
            if skimHint.superview == nil { collectionView.addSubview(skimHint) }
            let size = VideoMediaGridCell.skimHintSize
            let maxX = min(cell.frame.maxX - 2, collectionView.bounds.width - 2)
            skimHint.frame = CGRect(x: max(2, maxX - size.width), y: cell.frame.maxY + 4, width: size.width, height: size.height)
            collectionView.bringSubviewToFront(skimHint)
        }

        /// The hold watches alongside the scroll, so a drag that starts
        /// moving before 0.3 s is the scroll's and a still finger is the hold's.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            other === collectionView?.panGestureRecognizer
        }

        // MARK: Taps and prefetch

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let asset = library.asset(at: indexPath.item) else { return }
            parent.onTap(asset)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            didEndDisplaying cell: UICollectionViewCell,
            forItemAt _: IndexPath
        ) {
            guard let cell = cell as? VideoMediaGridCell, let request = cell.requestID else { return }
            library.photoLibrary.cancelThumbnailRequest(request)
            cell.requestID = nil
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let collectionView else { return }
            updateCaching(collectionView)
        }

        /// Keeps a screen either side of the visible cells warm in
        /// PhotoKit's cache, and lets go of what scrolled out of that window.
        private func updateCaching(_ collectionView: UICollectionView) {
            let visible = collectionView.indexPathsForVisibleItems.map(\.item)
            guard let first = visible.min(), let last = visible.max() else { return }
            let perScreen = VideoMediaPrefetch.itemsPerScreen(
                columns: parent.metrics.columns,
                cellHeight: cellSide(collectionView) + parent.metrics.gap,
                viewportHeight: collectionView.bounds.height
            )
            let window = VideoMediaPrefetch.window(visible: first..<(last + 1), itemsPerScreen: perScreen, count: library.count)
            let size = thumbnailSize(collectionView)
            guard window != cachedRange || size != cachedSize else { return }
            let photoLibrary = library.photoLibrary
            if size != cachedSize {
                photoLibrary.stopCachingThumbnails(for: library.assets(in: cachedRange), targetSize: cachedSize)
                photoLibrary.startCachingThumbnails(for: library.assets(in: window), targetSize: size)
            } else {
                for gone in VideoMediaPrefetch.subtract(window, from: cachedRange) {
                    photoLibrary.stopCachingThumbnails(for: library.assets(in: gone), targetSize: size)
                }
                for fresh in VideoMediaPrefetch.subtract(cachedRange, from: window) {
                    photoLibrary.startCachingThumbnails(for: library.assets(in: fresh), targetSize: size)
                }
            }
            cachedRange = window
            cachedSize = size
        }

        func resetCaching() {
            guard !cachedRange.isEmpty else { return }
            library.photoLibrary.stopCachingThumbnails(for: library.assets(in: cachedRange), targetSize: cachedSize)
            cachedRange = 0..<0
        }
    }
}

/// One square of the Media grid: the thumbnail edge to edge, no corner
/// radius (DESIGN §5), and a video's length at the bottom trailing corner.
final class VideoMediaGridCell: UICollectionViewCell {
    static let reuseIdentifier = "VideoMediaGridCell"

    let imageView = UIImageView()
    private let durationLabel = UILabel()
    /// ✓ on a white 19pt disc, or "×2" on a white capsule.
    private let badge = UILabel()
    private var isVideo = false
    private var duration: Double = 0
    private var name = ""
    /// What VoiceOver's two actions do for this cell.
    var actions: (insert: () -> Void, select: () -> Void)?
    /// Select's number, top leading, on a white disc.
    private let pickNumber = UILabel()
    var assetID: String?
    var requestID: PHImageRequestID?
    /// The cell a drag lifted from: a dashed outline where it was.
    var isLiftedSource = false {
        didSet {
            imageView.alpha = isLiftedSource ? 0.25 : 1
            dash.isHidden = !isLiftedSource
        }
    }
    private let dash = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor(white: 1, alpha: 0.06)
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        durationLabel.font = .systemFont(ofSize: 10.5, weight: .bold)
        durationLabel.textColor = .white
        durationLabel.layer.shadowColor = UIColor.black.cgColor
        durationLabel.layer.shadowOpacity = 0.6
        durationLabel.layer.shadowRadius = 2
        durationLabel.layer.shadowOffset = .zero
        durationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(durationLabel)

        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = .black
        badge.backgroundColor = .white
        badge.textAlignment = .center
        badge.layer.cornerRadius = Self.badgeSide / 2
        badge.layer.masksToBounds = true
        badge.isHidden = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(badge)

        pickNumber.font = .systemFont(ofSize: 12, weight: .bold)
        pickNumber.textColor = .black
        pickNumber.backgroundColor = .white
        pickNumber.textAlignment = .center
        pickNumber.layer.cornerRadius = Self.pickSide / 2
        pickNumber.layer.masksToBounds = true
        pickNumber.isHidden = true
        pickNumber.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pickNumber)
        contentView.layer.borderColor = UIColor.white.cgColor
        dash.strokeColor = UIColor.white.withAlphaComponent(0.7).cgColor
        dash.fillColor = UIColor.clear.cgColor
        dash.lineWidth = 1.5
        dash.lineDashPattern = [4, 3]
        dash.isHidden = true
        contentView.layer.addSublayer(dash)

        NSLayoutConstraint.activate([
            pickNumber.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            pickNumber.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 5),
            pickNumber.heightAnchor.constraint(equalToConstant: Self.pickSide),
            pickNumber.widthAnchor.constraint(equalToConstant: Self.pickSide),
            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            badge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            badge.heightAnchor.constraint(equalToConstant: Self.badgeSide),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: Self.badgeSide),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            durationLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -5),
            durationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        clear()
    }

    static let badgeSide: CGFloat = 19
    static let pickSide: CGFloat = 21
    /// The skim's marks (board F6_IL_HoverScrub): a 1.5pt line at the
    /// pointer, the time 64×20 at (4, 4), the hint 160×22 under the cell.
    static let skimTimeSize = CGSize(width: 64, height: 20)
    static let skimHintSize = CGSize(width: 160, height: 22)

    private lazy var skimLine: UIView = {
        let line = UIView()
        line.backgroundColor = .white
        line.isHidden = true
        line.isUserInteractionEnabled = false
        contentView.addSubview(line)
        return line
    }()

    private lazy var skimTime: UILabel = {
        let label = UILabel()
        label.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0, alpha: 0.75)
        label.layer.cornerRadius = Self.skimTimeSize.height / 2
        label.layer.masksToBounds = true
        label.isHidden = true
        label.isAccessibilityElement = false
        contentView.addSubview(label)
        return label
    }()

    /// The pointer `fraction` of the way across, at `time` of the source.
    func showSkim(fraction: Double, time: String) {
        let x = contentView.bounds.width * CGFloat(min(max(0, fraction), 1))
        skimLine.frame = CGRect(x: x - 0.75, y: 0, width: 1.5, height: contentView.bounds.height)
        skimLine.isHidden = false
        skimTime.frame = CGRect(origin: CGPoint(x: 4, y: 4), size: Self.skimTimeSize)
        skimTime.text = time
        skimTime.isHidden = false
        contentView.bringSubviewToFront(skimLine)
        contentView.bringSubviewToFront(skimTime)
    }

    func hideSkim() {
        skimLine.isHidden = true
        skimTime.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dash.frame = contentView.bounds
        dash.path = UIBezierPath(rect: contentView.bounds.insetBy(dx: 1, dy: 1)).cgPath
    }

    func clear() {
        hideSkim()
        isLiftedSource = false
        badge.isHidden = true
        markPick(nil)
        imageView.image = nil
        durationLabel.text = nil
        assetID = nil
        requestID = nil
    }

    func show(_ asset: PHAsset, index: Int) {
        assetID = asset.localIdentifier
        durationLabel.text = asset.mediaType == .video ? VideoMediaPoolFormat.duration(asset.duration) : nil
        isVideo = asset.mediaType == .video
        duration = asset.duration
        name = VideoMediaPoolFormat.name(for: asset)
        accessibilityLabel = VideoMediaPoolFormat.mediaCellLabel(isVideo: isVideo, duration: duration, name: name, uses: 0)
        accessibilityIdentifier = "videoMediaItem.\(index)"
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: VideoStudioCopy.insertAtPlayhead) { [weak self] _ in
                self?.actions?.insert()
                return true
            },
            UIAccessibilityCustomAction(name: VideoStudioCopy.select) { [weak self] _ in
                self?.actions?.select()
                return true
            },
        ]
    }

    /// Picked in Select: a 2pt white border and its number (FS-12.09 §4).
    func markPick(_ number: Int?) {
        pickNumber.isHidden = number == nil
        pickNumber.text = number.map(String.init)
        contentView.layer.borderWidth = number == nil ? 0 : 2
        if number != nil { accessibilityTraits.insert(.selected) } else { accessibilityTraits.remove(.selected) }
    }

    /// The used-mark (FS-12.09 §4): nothing, ✓, or ×n.
    func mark(uses: Int) {
        switch MediaUsage.badge(forUses: uses) {
        case .none:
            badge.isHidden = true
        case .check:
            badge.isHidden = false
            badge.attributedText = NSAttributedString(attachment: NSTextAttachment(
                image: UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 9, weight: .heavy))!
                    .withTintColor(.black, renderingMode: .alwaysOriginal)
            ))
        case .times(let count):
            badge.isHidden = false
            badge.attributedText = nil
            badge.text = "  ×\(count)  "
        }
        accessibilityLabel = VideoMediaPoolFormat.mediaCellLabel(isVideo: isVideo, duration: duration, name: name, uses: uses)
    }
}

