import AVFoundation
import SwiftUI

/// Before and After on the stage (FS-12.15 §4–5, plan K2). The compositor
/// draws one frame holding both — [Before | After], from the same source
/// pixels in the same request — and this view shows it through two windows
/// on the **same** player: side by side, or one over the other with the
/// Split line between them. One clock by construction; dragging the line
/// only moves a mask, never builds a composition.
struct VideoBeforeAfterStage: View {
    @Bindable var model: VideoStudioModel
    let compare: VideoBeforeAfter
    let player: AVPlayer
    /// The project frame's rect in the stage, for Split.
    let contentRect: CGRect
    /// The stage, for Side by Side's two frames.
    let stage: CGRect
    let windowClass: VideoStudioWindowClass?

    var body: some View {
        switch compare.mode {
        case .sideBySide: sideBySide
        case .split: split
        case .hold: EmptyView()
        }
    }

    // MARK: Side by Side

    private var sideBySideInsets: (inset: CGFloat, gap: CGFloat) {
        windowClass == .duoInner ? (9, 8) : (16, 16)
    }

    /// The level meter's column, kept clear of the frames on the iPad.
    static let meterAllowance: CGFloat = 40

    /// The two frames: centred on the Duo; on the iPad 80 under the stage's
    /// top — under Side by Side · Split — as the boards draw them.
    static func frames(in stage: CGRect, aspect: CGFloat, inset: CGFloat, gap: CGFloat, windowClass: VideoStudioWindowClass?) -> (left: CGRect, right: CGRect) {
        var frames = VideoBeforeAfter.sideBySideFrames(in: stage, aspect: aspect, inset: inset, gap: gap)
        if windowClass == .iPadLandscape || windowClass == .iPadPortrait {
            let top = stage.minY + (windowClass == .iPadPortrait ? 143 : 80)
            if top + frames.left.height <= stage.maxY {
                frames.left.origin.y = top
                frames.right.origin.y = top
            }
        }
        return frames
    }

    private var sideBySide: some View {
        let aspect = model.recipe.canvasSize().width / max(model.recipe.canvasSize().height, 1)
        let frames = Self.frames(in: stage, aspect: aspect, inset: sideBySideInsets.inset, gap: sideBySideInsets.gap, windowClass: windowClass)
        let beforeFrame = compare.isSwapped ? frames.right : frames.left
        let afterFrame = compare.isSwapped ? frames.left : frames.right
        return ZStack(alignment: .topLeading) {
            VideoPairHalfView(player: player, showsAfter: false)
                .frame(width: beforeFrame.width, height: beforeFrame.height)
                .overlay(alignment: .topLeading) { pill(isBefore: true).padding(10) }
                .position(x: beforeFrame.midX, y: beforeFrame.midY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VideoStudioCopy.before)
            VideoPairHalfView(player: player, showsAfter: true)
                .frame(width: afterFrame.width, height: afterFrame.height)
                .overlay(alignment: .topTrailing) { pill(isBefore: false).padding(10) }
                .position(x: afterFrame.midX, y: afterFrame.midY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VideoStudioCopy.after)
            Text(model.hasNothingToCompare ? VideoStudioCopy.noEditsToCompare : VideoStudioCopy.bothSidesPlay(
                windowClass == .duoInner, at: VideoStudioMetrics.captionTime(model.currentTime)
            ))
            .font(.system(size: windowClass == .duoInner ? 12 : 15))
            .foregroundStyle(.white.opacity(0.55))
            .lineLimit(1)
            .frame(width: stage.width)
            .position(x: stage.midX, y: frames.left.maxY + 20)
            .accessibilityIdentifier("compareCaption")
        }
        .frame(width: stage.maxX, height: stage.maxY, alignment: .topLeading)
    }

    // MARK: Split

    @State private var dragStart: Double?

    private var split: some View {
        let lineX = compare.lineX(in: contentRect)
        let beforeWidth = max(0, lineX - contentRect.minX)
        return ZStack(alignment: .topLeading) {
            // After fills the frame; Before is drawn over it, cut at the line.
            VideoPairHalfView(player: player, showsAfter: true)
                .frame(width: contentRect.width, height: contentRect.height)
                .position(x: contentRect.midX, y: contentRect.midY)
            VideoPairHalfView(player: player, showsAfter: false)
                .frame(width: contentRect.width, height: contentRect.height)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: beforeWidth)
                }
                .position(x: contentRect.midX, y: contentRect.midY)
            pill(isBefore: true)
                .position(x: contentRect.minX + 10 + 32, y: contentRect.minY + 10 + 11)
            pill(isBefore: false)
                .position(x: contentRect.maxX - 10 - 28, y: contentRect.minY + 10 + 11)
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: contentRect.height)
                .position(x: lineX, y: contentRect.midY)
                .allowsHitTesting(false)
            if !model.isPlaying {
                Button { model.togglePlayback() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background { Color.clear.editorGlass(Circle()) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .position(x: (lineX + contentRect.maxX) / 2, y: contentRect.midY)
                .accessibilityLabel(Text("Play", comment: "Video Studio: starts preview playback"))
            }
            handle
                .position(x: lineX, y: contentRect.midY)
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("compareStage"))
                        .onChanged { value in
                            model.setCompareFraction(VideoBeforeAfter.fraction(forX: value.location.x, in: contentRect))
                        }
                )
        }
        .coordinateSpace(name: "compareStage")
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: "chevron.left.chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            }
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .accessibilityElement()
            .accessibilityLabel(VideoStudioCopy.before)
            .accessibilityValue(VideoStudioCopy.percentValue(compare.percent))
            .accessibilityHint(VideoStudioCopy.dragToCompare)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.adjustCompareFraction(by: 1)
                case .decrement: model.adjustCompareFraction(by: -1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("compareHandle")
    }

    /// "Before" 64×22 on black 60 %, "After" 56×22 on white (§4).
    private func pill(isBefore: Bool) -> some View {
        Text(isBefore ? VideoStudioCopy.before : VideoStudioCopy.after)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(isBefore ? Color.white : Color.black)
            .frame(width: isBefore ? 64 : 56, height: 22)
            .background(Capsule().fill(isBefore ? Color.black.opacity(0.6) : Color.white))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// One half of the pair frame: an `AVPlayerLayer` twice the view's width,
/// shifted so Before (the left half) or After (the right) fills it. Two of
/// these on one player is the whole trick of the shared clock.
struct VideoPairHalfView: UIViewRepresentable {
    let player: AVPlayer
    let showsAfter: Bool

    final class HostView: UIView {
        let playerLayer = AVPlayerLayer()
        var showsAfter = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            playerLayer.videoGravity = .resize
            layer.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = CGRect(x: showsAfter ? -bounds.width : 0, y: 0, width: bounds.width * 2, height: bounds.height)
            CATransaction.commit()
        }
    }

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.playerLayer.player = player
        view.showsAfter = showsAfter
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HostView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        if view.showsAfter != showsAfter {
            view.showsAfter = showsAfter
            view.setNeedsLayout()
        }
    }
}

/// Before and After in the Look panel's title on the phone and the Duo's
/// cover (FS-12.15 §4, boards F7_P, F7_DC): a 32pt disc left of ✕ and ✓ —
/// white with a black glyph when on, white 10 % when off; never accent.
struct VideoLookCompareButton: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        let isOn = model.compare != nil
        Button {
            model.toggleBeforeAfter(sideBySide: false, fromLookPanel: true)
        } label: {
            Image(systemName: "square.split.2x1")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isOn ? Color.white : Color.white.opacity(0.10)))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 32, height: 32)
        .accessibilityLabel(VideoStudioCopy.beforeAndAfter)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("beforeAndAfterButton")
    }
}
