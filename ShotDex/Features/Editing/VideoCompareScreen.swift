import AVFoundation
import SwiftUI
import UIKit

/// FS-24 §10 Compare Videos (boards `PH_/IP_/DI_/DC_VideoCompare`): the
/// original (A) against its compressed copy (B) — one transport for both, a
/// pinch that zooms both to the same spot, hold a pane to see the other.
/// Stacked on a compact screen, side by side on a wide one, like the photo
/// Compare. Tier D, dark whatever the appearance.
struct VideoCompareScreen: View {
    @State private var model: VideoCompareModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDuoInner) private var isDuoInner
    @State private var synchronizer = CompareScrollSynchronizer()
    @State private var zoom: CGFloat = 1
    /// The pane being held, which shows the other video meanwhile.
    @State private var heldPane: Int?
    /// Frozen while the finger is on the scrubber.
    @State private var scrubTime: Double?

    init(batch: VideoCompressionBatch, startID: String?) {
        _model = State(initialValue: VideoCompareModel(batch: batch, startID: startID, loader: PhotoKitVideoCompareLoader()))
    }

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            GeometryReader { proxy in
                let isWide = proxy.size.width >= WideLayout.minimumWidth
                VStack(spacing: AppTheme.Spacing.md) {
                    topBar(isWide: isWide)
                    // Video and transport stay together, centred in what is
                    // left (boards `*_VideoCompare`); the panes get their
                    // height first and take only what their picture needs.
                    Spacer(minLength: 0)
                    panes(isWide: isWide)
                        .layoutPriority(1)
                    transport
                        .frame(maxWidth: isWide ? 720 : .infinity)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                    Spacer(minLength: 0)
                    footer(isWide: isWide)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xs)
                }
            }
        }
        .preferredColorScheme(.dark)
        .background { keys }
        .task {
            synchronizer.onZoomChange = { scale in zoom = scale }
            model.loadCurrent()
        }
        .onDisappear { model.tearDown() }
        .onChange(of: model.isEmpty) { _, empty in if empty { dismiss() } }
        .onChange(of: model.currentID) { _, _ in
            // A new pair opens at fit, like a new photo in Compare.
            heldPane = nil
            synchronizer.zoom(frameAt: 0, to: 1, animated: false)
        }
    }

    // MARK: Top bar

    private func topBar(isWide: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            GlassIconButton(systemImage: "xmark", accessibilityLabel: String(localized: "Close")) { dismiss() }
            VStack(spacing: 2) {
                Text(model.currentPair.map { model.batch.filename(of: $0.id) } ?? "")
                    .font(.headline)
                    .foregroundStyle(.white)
                if let pair = model.currentPair {
                    Text(VideoCompressionCopy.saved(pair.savedBytes))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(EditorTheme.secondaryText)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            deleteButton(showsTitle: isWide)
        }
        .padding(.horizontal, CullLayout.edgeInset)
        .padding(.top, isDuoInner ? CompareLayout.duoInnerTopInset : AppTheme.Spacing.sm)
    }

    private func deleteButton(showsTitle: Bool) -> some View {
        Button(role: .destructive) {
            Task { await model.deleteCurrentOriginal() }
        } label: {
            Group {
                if showsTitle {
                    Label(VideoCompressionCopy.deleteOriginal, systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, AppTheme.Spacing.md)
                } else {
                    Image(systemName: "trash")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44)
                }
            }
            .foregroundStyle(.white)
            .frame(minHeight: 44)
            .background(Capsule().fill(Color.red))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isDeleting || model.currentPair == nil)
        .accessibilityLabel(VideoCompressionCopy.deleteOriginal)
        .keyboardShortcut(.delete, modifiers: .command)
    }

    // MARK: Panes

    @ViewBuilder
    private func panes(isWide: Bool) -> some View {
        let layout = isWide ? AnyLayout(HStackLayout(spacing: AppTheme.Spacing.sm)) : AnyLayout(VStackLayout(spacing: 6))
        layout {
            pane(slot: 0)
            pane(slot: 1)
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity)
        .overlay {
            if model.isLoading {
                ProgressView().tint(.white)
            }
        }
    }

    private func player(_ slot: Int) -> AVPlayer {
        slot == 0 ? model.original : model.copy
    }

    private func pane(slot: Int) -> some View {
        VideoComparePane(
            player: player(slot),
            synchronizer: synchronizer,
            paneIndex: slot,
            onHoldChange: { holding in heldPane = holding ? slot : nil }
        )
        .overlay {
            // Hold = the other video at the same zoom, laid over this one so
            // the hold recognizer underneath keeps running.
            if heldPane == slot {
                VideoComparePane(player: player(1 - slot), synchronizer: synchronizer,
                                 paneIndex: 2 + slot, onHoldChange: { _ in })
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(model.videoAspect, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(alignment: .topLeading) {
            paneLabel(heldPane == slot ? 1 - slot : slot)
                .padding(AppTheme.Spacing.sm)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            if zoom > 1.01 {
                Text("\(Double(zoom).formatted(.number.precision(.fractionLength(0...1))))×")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(AppTheme.Spacing.sm)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(for: slot))
    }

    private func label(for slot: Int) -> String {
        guard let pair = model.currentPair else { return "" }
        return slot == 0
            ? VideoCompressionCopy.originalLabel(bytes: pair.originalBytes, codec: model.originalCodec)
            : VideoCompressionCopy.copyLabel(pair)
    }

    private func paneLabel(_ slot: Int) -> some View {
        HStack(spacing: AppTheme.Spacing.xs) {
            Text(slot == 0 ? "A" : "B")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.white))
            Text(label(for: slot))
                .lineLimit(1)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .monospacedDigit()
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 24)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(VideoCompressionCopy.time(scrubTime ?? model.currentTime))
                Slider(
                    value: Binding(
                        get: { scrubTime ?? model.currentTime },
                        set: { value in
                            scrubTime = value
                            model.scrub(to: value, isFinal: false)
                        }
                    ),
                    in: 0...max(model.duration, 0.01),
                    onEditingChanged: { editing in
                        if !editing, let value = scrubTime {
                            model.scrub(to: value, isFinal: true)
                            scrubTime = nil
                        }
                    }
                )
                .tint(.white)
                Text(VideoCompressionCopy.time(model.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(EditorTheme.secondaryText)
            HStack(spacing: AppTheme.Spacing.xl) {
                transportButton("backward.frame.fill", VideoCompressionCopy.previousFrame) { model.stepFrame(-1) }
                Button(action: model.togglePlay) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.isPlaying ? VideoCompressionCopy.pause : VideoCompressionCopy.play)
                transportButton("forward.frame.fill", VideoCompressionCopy.nextFrame) { model.stepFrame(1) }
                transportButton(model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                model.isMuted ? VideoCompressionCopy.soundOn : VideoCompressionCopy.soundOff) {
                    model.isMuted.toggle()
                }
            }
            .disabled(model.isLoading)
        }
    }

    private func transportButton(_ systemImage: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Footer

    @ViewBuilder
    private func footer(isWide: Bool) -> some View {
        if isWide {
            HStack {
                Text(VideoCompressionCopy.compareHint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                stepper
                Text(VideoCompressionCopy.compareKeys)
                    .foregroundStyle(EditorTheme.dimText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(EditorTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            VStack(spacing: AppTheme.Spacing.xs) {
                stepper
                Text(VideoCompressionCopy.compareHint)
                    .font(.caption)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button { model.stepVideo(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!model.canStepBack)
            .accessibilityLabel(VideoCompressionCopy.previousVideo)
            Text(model.currentIndex.map { VideoCompressionCopy.position($0, of: model.pairs.count) } ?? "")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
            Button { model.stepVideo(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(!model.canStepForward)
            .accessibilityLabel(VideoCompressionCopy.nextVideo)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    // MARK: Keyboard (FS-24 §10)

    private var keys: some View {
        Group {
            Button(VideoCompressionCopy.play) { model.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button(VideoCompressionCopy.previousFrame) { model.stepFrame(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(VideoCompressionCopy.nextFrame) { model.stepFrame(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button(VideoCompressionCopy.previousVideo) { model.stepVideo(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button(VideoCompressionCopy.nextVideo) { model.stepVideo(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button(String(localized: "Close")) { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// One video in a `UIScrollView` whose zoom and pan the synchronizer mirrors
/// onto the other pane. Double-tap toggles fit ↔ 3× at the tapped point; a
/// hold reports itself so the screen can show the other video in its place.
struct VideoComparePane: UIViewRepresentable {
    let player: AVPlayer
    let synchronizer: CompareScrollSynchronizer
    let paneIndex: Int
    let onHoldChange: (Bool) -> Void

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.minimumZoomScale = VideoCompareRules.minimumZoom
        scrollView.maximumZoomScale = VideoCompareRules.maximumZoom
        scrollView.bouncesZoom = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        let playerView = ZoomableVideoView.PlayerContainerView()
        playerView.playerLayer.player = player
        playerView.playerLayer.videoGravity = .resizeAspect
        playerView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            playerView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            playerView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
        context.coordinator.playerView = playerView
        context.coordinator.synchronizer = synchronizer
        context.coordinator.onHoldChange = onHoldChange

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHold(_:)))
        hold.minimumPressDuration = 0.3
        // A hold that starts moving becomes a pan, and the flip lets go.
        hold.allowableMovement = 12
        scrollView.addGestureRecognizer(hold)

        synchronizer.register(scrollView, at: paneIndex)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.onHoldChange = onHoldChange
        if let layer = context.coordinator.playerView?.playerLayer, layer.player !== player {
            layer.player = player
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var playerView: ZoomableVideoView.PlayerContainerView?
        var synchronizer: CompareScrollSynchronizer?
        var onHoldChange: ((Bool) -> Void)?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { playerView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            MainActor.assumeIsolated { synchronizer?.mirror(from: scrollView) }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard scrollView.isTracking || scrollView.isDecelerating || scrollView.isZooming else { return }
            MainActor.assumeIsolated { synchronizer?.mirror(from: scrollView) }
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView, let content = playerView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale * 1.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: content)
                let scale = VideoCompareRules.doubleTapZoom
                let size = CGSize(width: content.bounds.width / scale, height: content.bounds.height / scale)
                scrollView.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                           width: size.width, height: size.height), animated: true)
            }
        }

        @objc func handleHold(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began: onHoldChange?(true)
            case .ended, .cancelled, .failed: onHoldChange?(false)
            default: break
            }
        }
    }
}
