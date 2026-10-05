import SwiftUI
import UIKit

/// A music bed's Beats (FS-12.12 §3, board F2_P_BeatDetect): the beat card
/// — what the analysis found, or that it is finding — then Snap, SNAP TO,
/// Offset and Cut Clips to Beat.
struct VideoBeatsPanel: View {
    @Bindable var model: VideoStudioModel
    let music: MusicTrack
    var isDesk = false

    private var inset: CGFloat { 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            beatCard
            snapRow
            offsetRow
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: Snap

    /// "Snap clips to beats" — dimmed 0.28 with no steady beat to snap to
    /// (AC-3); turning it on turns every other bed's off (§5).
    private var snapRow: some View {
        let canSnap = model.canSnap(to: music)
        return Toggle(isOn: Binding(
            get: { music.beatSnap.isOn },
            set: { model.setBeatSnap($0, for: music.id) }
        )) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(VideoStudioCopy.snapClipsToBeats)
                    .font(.system(size: isDesk ? 17 : 14))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, inset)
        .frame(height: isDesk ? 44 : 42)
        .disabled(!canSnap && !music.beatSnap.isOn)
        .opacity(canSnap || music.beatSnap.isOn ? 1 : 0.28)
    }

    /// Offset −250…+250 ms, a notch at 0 (§5): the grid moves under a
    /// beat that was found a hair early or late.
    private var offsetRow: some View {
        let canSnap = model.canSnap(to: music)
        return InspectorSlider(
            label: String(localized: "Offset", table: VideoStudioCopy.table, comment: "Video Studio beats: shifts every beat of the bed a few milliseconds earlier or later"),
            value: Double(music.beatSnap.offsetMs),
            range: Double(MusicBeatSnap.offsetRange.lowerBound)...Double(MusicBeatSnap.offsetRange.upperBound),
            valueText: VideoStudioCopy.offsetMilliseconds(music.beatSnap.offsetMs),
            anchor: 0, notch: true, detent: 0,
            model: model,
            set: { model.setBeatOffset(Int($0.rounded()), for: music.id) },
            reset: { model.pushUndo(); model.setBeatOffset(0, for: music.id) }
        )
        .disabled(!canSnap)
        .opacity(canSnap ? 1 : 0.28)
    }

    // MARK: Card

    private var beatCard: some View {
        let state = model.beatState(for: music)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(EditorTheme.timelineBeat.opacity(0.16))
                if state == .finding || state == nil {
                    ProgressView()
                        .controlSize(.small)
                        .tint(EditorTheme.timelineBeat)
                } else {
                    Image(systemName: VideoItemCommand.beats.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EditorTheme.timelineBeat)
                }
            }
            .frame(width: VideoStudioMetrics.beatCardDisc, height: VideoStudioMetrics.beatCardDisc)
            VStack(alignment: .leading, spacing: 2) {
                Text(cardTitle(state))
                    .font(.system(size: isDesk ? 17 : 15, weight: .semibold))
                    .foregroundStyle(.white)
                if let detail = cardDetail(state) {
                    Text(detail)
                        .font(.system(size: isDesk ? 13 : 11.5))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: VideoStudioMetrics.beatCardHeight)
        .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.06)))
        .padding(.horizontal, inset)
        .accessibilityElement(children: .combine)
    }

    private func cardTitle(_ state: VideoBeatsModel.State?) -> String {
        switch state {
        case .found(let analysis): VideoStudioCopy.bpmLine(analysis.bpm)
        case .noSteadyBeat: VideoStudioCopy.noSteadyBeat
        case .unreadable: VideoStudioCopy.cantReadTrack
        case .finding, nil: VideoStudioCopy.findingBeats
        }
    }

    private func cardDetail(_ state: VideoBeatsModel.State?) -> String? {
        switch state {
        case .found:
            let count = model.beatGrid(for: music)?.ticks.count ?? 0
            let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
            return VideoStudioCopy.beatsMarked(count, lane: model.laneName(for: music), device: device)
        case .noSteadyBeat: return VideoStudioCopy.snapNeedsClearBeat
        case .unreadable, .finding, nil: return nil
        }
    }
}

/// Beat ticks (FS-12.12 §3) in the beat colour, drawn in one `Canvas` — a
/// three-minute song is hundreds of beats, and a view per tick would make
/// the scroller rebuild them all on every update (D-7).
struct BeatTickMarks: View {
    enum Style { case band, overview }

    let ticks: [BeatGrid.Tick]
    /// Timeline second at the canvas's x = 0.
    let origin: Double
    /// Points per timeline second.
    let scale: Double
    var style: Style = .band

    var body: some View {
        Canvas { context, size in
            for tick in ticks {
                let x = CGFloat((tick.time - origin) * scale)
                guard x >= -4, x <= size.width + 4 else { continue }
                switch style {
                case .band:
                    if tick.isBar {
                        let line = VideoStudioMetrics.barTick
                        let square = VideoStudioMetrics.barTickSquare
                        context.fill(Path(CGRect(x: x - square / 2, y: 0, width: square, height: square)), with: .color(EditorTheme.timelineBeat))
                        context.fill(Path(CGRect(x: x - line.width / 2, y: 0, width: line.width, height: line.height)), with: .color(EditorTheme.timelineBeat))
                    } else {
                        let line = VideoStudioMetrics.beatTick
                        context.fill(Path(CGRect(x: x - line.width / 2, y: 0, width: line.width, height: line.height)), with: .color(EditorTheme.timelineBeat.opacity(0.7)))
                    }
                case .overview:
                    let line = tick.isBar ? VideoStudioMetrics.overviewBarTick : VideoStudioMetrics.overviewBeatTick
                    context.fill(
                        Path(CGRect(x: x - line.width / 2, y: 0, width: line.width, height: line.height)),
                        with: .color(EditorTheme.timelineBeat.opacity(tick.isBar ? 1 : 0.55))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
