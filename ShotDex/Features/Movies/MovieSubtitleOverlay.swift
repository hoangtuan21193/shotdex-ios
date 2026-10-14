import SwiftUI

/// ShotDex's own subtitle layer over the picture (FS-23.03 §4): placed in
/// the movie frame (Fit: the letterboxed frame; Fill: its visible part),
/// two subtitles never on top of each other, lifted above the transport
/// glass while it shows. Drawn every frame at `PlaybackClock` time.
struct MovieSubtitleOverlay: View {
    let model: MoviePlayerModel
    /// Top edge of the transport glass in stage coordinates, while it shows.
    let chromeTop: CGFloat?
    /// Bottom edge of the top bar, while it shows.
    var chromeBottom: CGFloat?
    /// Stage edges the Audio & Subtitles panel covers: the subtitles move
    /// into the picture still in view (03 §2).
    var covered = EdgeInsets()

    var body: some View {
        GeometryReader { proxy in
            let stage = CGRect(origin: .zero, size: proxy.size)
            let frame = Self.movieFrame(videoSize: model.videoSize, in: stage, fills: model.fillsFrame)
            let bounds = CGRect(
                x: covered.leading, y: covered.top,
                width: max(1, stage.width - covered.leading - covered.trailing),
                height: max(1, stage.height - covered.top - covered.bottom)
            )
            // Paused, the clock stands still; a seek or a sync change still
            // redraws through the observed values read here.
            let _ = (model.timeMs, model.primaryTimeline?.delayMs, model.secondaryTimeline?.delayMs)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.isPlaying)) { _ in
                let time = model.subtitleTimeMs(at: MoviePlayerModel.hostTime)
                let primary = model.primaryTimeline?.cues(atMs: time) ?? []
                let secondary = model.secondaryTimeline?.cues(atMs: time) ?? []
                DualSubtitleStack(position: model.subtitleStyle.position, frame: frame, bounds: bounds, chromeTop: chromeTop, chromeBottom: chromeBottom) {
                    if !primary.isEmpty {
                        SubtitleBlock(cues: primary, line: model.subtitleStyle.primary, frameHeight: frame.height)
                            .layoutValue(key: SubtitleRole.self, value: .init(isPrimary: true, wantsTop: primary.contains { $0.placement == .top }))
                    }
                    if !secondary.isEmpty {
                        SubtitleBlock(cues: secondary, line: model.subtitleStyle.secondary, frameHeight: frame.height)
                            .layoutValue(key: SubtitleRole.self, value: .init(isPrimary: false, wantsTop: secondary.contains { $0.placement == .top }))
                    }
                }
                .animation(nil, value: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the picture lands in `bounds`: fitted with bars, or filling
    /// and cropped. An undecoded picture is taken as the whole stage.
    static func movieFrame(videoSize: CGSize, in bounds: CGRect, fills: Bool) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
        let scaleX = bounds.width / videoSize.width
        let scaleY = bounds.height / videoSize.height
        let scale = fills ? max(scaleX, scaleY) : min(scaleX, scaleY)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
}

private struct SubtitleRole: LayoutValueKey {
    struct Value: Equatable {
        var isPrimary: Bool
        var wantsTop: Bool
    }

    static let defaultValue = Value(isPrimary: true, wantsTop: false)
}

/// Measures each subtitle at the frame's width limit and puts it where
/// `DualSubtitleLayout` says.
private struct DualSubtitleStack: Layout {
    let position: DualSubtitlePosition
    let frame: CGRect
    let bounds: CGRect
    let chromeTop: CGFloat?
    let chromeBottom: CGFloat?

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in rect: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = DualSubtitleLayout.maxWidth(frame: frame, bounds: bounds)
        var primary: (LayoutSubview, DualSubtitleLayout.Block)?
        var secondary: (LayoutSubview, DualSubtitleLayout.Block)?
        for subview in subviews {
            let role = subview[SubtitleRole.self]
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let block = DualSubtitleLayout.Block(size: size, wantsTop: role.wantsTop)
            if role.isPrimary { primary = (subview, block) } else { secondary = (subview, block) }
        }
        let placement = DualSubtitleLayout.place(
            primary: primary?.1, secondary: secondary?.1, position: position,
            frame: frame, bounds: bounds, chromeTop: chromeTop, chromeBottom: chromeBottom
        )
        for (entry, placed) in [(primary, placement.primary), (secondary, placement.secondary)] {
            guard let (subview, _) = entry, let placed else { continue }
            subview.place(
                at: CGPoint(x: rect.minX + placed.minX, y: rect.minY + placed.minY),
                proposal: ProposedViewSize(width: placed.width, height: placed.height)
            )
        }
    }
}

/// One subtitle's cues on screen; overlapping cues stack, the later one on
/// top (§4). White text with a dark edge and shadow, no box.
private struct SubtitleBlock: View {
    let cues: [SubtitleCue]
    let line: MovieSubtitleStyle.Line
    let frameHeight: CGFloat

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(cues.enumerated().reversed()), id: \.offset) { _, cue in
                cueText(cue)
            }
        }
        .font(.system(size: max(10, DualSubtitleLayout.fontSize(frameHeight: frameHeight, scale: line.scale)), weight: .semibold))
        .foregroundStyle(line.color.swatch)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black, radius: 1)
        .shadow(color: .black, radius: 1)
        .shadow(color: .black.opacity(0.9), radius: 1.5, y: 1)
    }

    private func cueText(_ cue: SubtitleCue) -> Text {
        var text = Text(verbatim: "")
        for (index, runs) in cue.lines.enumerated() {
            if index > 0 { text = text + Text(verbatim: "\n") }
            for run in runs {
                var piece = Text(verbatim: run.text)
                if run.isItalic { piece = piece.italic() }
                if run.isBold { piece = piece.bold() }
                text = text + piece
            }
        }
        return text
    }
}

extension MovieSubtitleStyle.Color {
    /// The four subtitle colors (FS-23.03 §2; DESIGN.md › Movie player).
    var swatch: Color {
        switch self {
        case .white: .white
        case .yellow: Color(red: 1, green: 0.839, blue: 0.039)
        case .lightGray: Color(white: 0.8)
        case .cyan: Color(red: 0.353, green: 0.784, blue: 0.98)
        }
    }
}
