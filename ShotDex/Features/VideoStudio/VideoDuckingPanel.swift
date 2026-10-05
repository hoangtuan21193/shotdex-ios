import SwiftUI

/// A music bed's Ducking (FS-12.13 §3, boards F3_*): the whole film's graph
/// on the phone and the cover, UNDER VOICES, Amount, Duck in, Recover, what
/// makes it dip, and the summary line. Every control is the audio tier: the
/// mix changes, the frames do not (§4).
struct VideoDuckingPanel: View {
    @Bindable var model: VideoStudioModel
    let music: MusicTrack
    var isDesk = false
    /// The Duo's inner column: no graph, Volume first (F3_DI_Ducking).
    var isColumn = false
    @Environment(\.videoStudioWindowClass) private var windowClass

    private var isCover: Bool { windowClass == .duoCover }
    private var inset: CGFloat { isCover ? 14 : 16 }
    /// The phone and the cover draw the graph; a column has a timeline
    /// beside it that already shows the dips.
    private var showsGraph: Bool { !isDesk && !isColumn }
    private var ducking: MusicDucking { music.ducking }

    var body: some View {
        let dips = model.duckingDips(for: music)
        VStack(alignment: .leading, spacing: 0) {
            if showsGraph {
                VideoDuckingGraph(model: model, music: music, dips: dips)
                    .frame(height: VideoStudioMetrics.duckingGraphHeight)
                    .padding(.horizontal, inset)
                    .padding(.top, 4)
                if !isCover { legend.padding(.horizontal, inset).padding(.top, 6) }
            }
            if isDesk || isColumn { volumeRow }
            underVoicesRow
            amountRow
            duckInRow
            recoverRow
            triggerRow
            summaryRow
            if isDesk {
                Text(VideoStudioCopy.onlyTheMusicMoves)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, inset)
                    .padding(.top, 4)
                deskFadeRows
            }
            if !isDesk && !isColumn { volumeRow }
        }
        .padding(.bottom, 8)
        .onAppear { model.refreshDucking(force: true) }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(EditorTheme.timelineSpeech).frame(width: 10, height: 8)
                Text(VideoStudioCopy.duckTrigger(.voices))
            }
            HStack(spacing: 6) {
                Capsule().fill(Color.white).frame(width: 12, height: 2)
                Text(VideoStudioCopy.musicLevel)
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.55))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var volumeRow: some View {
        if isDesk {
            DeskVolumeRow(
                isMuted: music.isMuted, volume: music.volume, model: model,
                toggleMute: { model.toggleMusicMuted(music.id) },
                set: { model.setMusicVolume($0, for: music.id) },
                reset: { model.pushUndo(); model.setMusicVolume(1, for: music.id) }
            )
            .padding(.leading, inset - DeskRowMetrics.muteGap)
            .padding(.trailing, inset)
            .padding(.top, 6)
        } else {
            phoneVolumeRow
        }
    }

    /// Fade, scrolled to under the iPad's settings (F3_IL_Ducking).
    private var deskFadeRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fade", tableName: VideoStudioCopy.table, comment: "Video Studio clip panel: header over the clip's fade in and fade out")
                .font(.system(size: DeskRowMetrics.headerSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(height: DeskRowMetrics.headerHeight)
                .accessibilityAddTraits(.isHeader)
            DeskSliderRow(
                label: String(localized: "Fade in", table: VideoStudioCopy.table, comment: "Video Studio iPad clip panel: the fade-in slider"),
                value: music.fadeIn, range: MusicTrack.fadeRange,
                valueText: VideoStudioCopy.duckSeconds(music.fadeIn), model: model,
                set: { model.setMusicFadeIn($0, for: music.id) },
                reset: { model.pushUndo(); model.setMusicFadeIn(2, for: music.id) }
            )
            DeskSliderRow(
                label: String(localized: "Fade out", table: VideoStudioCopy.table, comment: "Video Studio iPad clip panel: the fade-out slider"),
                value: music.fadeOut, range: MusicTrack.fadeRange,
                valueText: VideoStudioCopy.duckSeconds(music.fadeOut), model: model,
                set: { model.setMusicFadeOut($0, for: music.id) },
                reset: { model.pushUndo(); model.setMusicFadeOut(2, for: music.id) }
            )
        }
        .padding(.horizontal, inset)
        .padding(.top, 12)
    }

    private var phoneVolumeRow: some View {
        MutableVolumeRow(
            isMuted: music.isMuted, volume: music.volume, model: model,
            toggleMute: { model.toggleMusicMuted(music.id) },
            set: { model.setMusicVolume($0, for: music.id) },
            reset: { model.pushUndo(); model.setMusicVolume(1, for: music.id) }
        )
    }

    private var underVoicesRow: some View {
        Toggle(isOn: Binding(
            get: { ducking.isOn },
            set: { model.setDucking($0, for: music.id) }
        )) {
            Text(isDesk ? VideoStudioCopy.underVoices : VideoStudioCopy.underVoices.uppercased())
                .font(.system(size: isDesk ? 15 : 12, weight: .semibold))
                .foregroundStyle(isDesk ? .white : .white.opacity(0.75))
        }
        .padding(.horizontal, inset)
        .frame(height: isDesk ? 44 : 38)
    }

    private var amountRow: some View {
        settingSlider(
            label: VideoStudioCopy.duckAmount, value: Double(ducking.amountDB), range: Double(MusicDucking.amountRange.lowerBound)...Double(MusicDucking.amountRange.upperBound),
            // The shared row's value column holds "−12", not "−12 dB": the
            // unit is the iPad's alone, where the column is 60 wide.
            valueText: isDesk ? VideoStudioCopy.decibels(ducking.amountDB) : "\(ducking.amountDB < 0 ? "−" : "")\(abs(ducking.amountDB))",
            anchor: Double(MusicDucking.amountRange.upperBound),
            set: { model.setDuckingAmount($0, for: music.id) },
            reset: { model.pushUndo(); model.setDuckingAmount(-12, for: music.id) }
        )
    }

    private var duckInRow: some View {
        settingSlider(
            label: VideoStudioCopy.duckIn, value: ducking.duckIn, range: MusicDucking.duckInRange,
            valueText: VideoStudioCopy.duckSeconds(ducking.duckIn), anchor: MusicDucking.duckInRange.lowerBound,
            set: { model.setDuckingDuckIn($0, for: music.id) },
            reset: { model.pushUndo(); model.setDuckingDuckIn(0.3, for: music.id) }
        )
    }

    private var recoverRow: some View {
        settingSlider(
            label: VideoStudioCopy.duckRecover, value: ducking.recover, range: MusicDucking.recoverRange,
            valueText: VideoStudioCopy.duckSeconds(ducking.recover), anchor: MusicDucking.recoverRange.lowerBound,
            set: { model.setDuckingRecover($0, for: music.id) },
            reset: { model.pushUndo(); model.setDuckingRecover(0.8, for: music.id) }
        )
    }

    /// A setting's slider: the iPad's Mac-style row (IL2), the shared
    /// slider row elsewhere. Dimmed while ducking is off.
    @ViewBuilder
    private func settingSlider(
        label: String, value: Double, range: ClosedRange<Double>, valueText: String, anchor: Double,
        set: @escaping (Double) -> Void, reset: @escaping () -> Void
    ) -> some View {
        Group {
            if isDesk {
                DeskSliderRow(label: label, value: value, range: range, valueText: valueText, anchor: anchor, model: model, set: set, reset: reset)
                    .padding(.horizontal, inset)
            } else {
                InspectorSlider(label: label, value: value, range: range, valueText: valueText, anchor: anchor, model: model, set: set, reset: reset)
            }
        }
        .disabled(!ducking.isOn)
        .opacity(ducking.isOn ? 1 : 0.28)
    }

    /// Voices · Any Clip Sound — chips on the phone and the Duo, a 36pt
    /// segmented control under "Duck Under" on the iPad.
    private var triggerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: isDesk ? 2 : 6) {
                ForEach(MusicDucking.Trigger.allCases, id: \.self) { trigger in
                    let isOn = ducking.trigger == trigger
                    Button { model.setDuckingTrigger(trigger, for: music.id) } label: {
                        Text(VideoStudioCopy.duckTrigger(trigger))
                            .font(.system(size: isDesk ? 15 : 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: isDesk ? 32 : 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isOn ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(isDesk ? 2 : 0)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isDesk ? Color.white.opacity(0.06) : .clear)
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(VideoStudioCopy.duckUnder))
        }
        .padding(.horizontal, inset)
        .padding(.vertical, 4)
        .disabled(!ducking.isOn)
        .opacity(ducking.isOn ? 1 : 0.28)
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            if model.ducking.isListening {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(EditorTheme.timelineSpeech)
            }
            Text(model.duckingSummary(for: music))
                .font(.system(size: isDesk ? 15 : 13))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, inset)
        .frame(minHeight: 36)
        .accessibilityElement(children: .combine)
    }
}

/// The whole film's music level (§3): the bed's box, the white line that
/// dips under every voice with the dip's dB at its foot, the clips along
/// the bottom with their voices in blue, and the playhead.
struct VideoDuckingGraph: View {
    @Bindable var model: VideoStudioModel
    let music: MusicTrack
    let dips: [ClipSoundActivity.Span]

    static let labelHeight: CGFloat = 14
    static let boxHeight: CGFloat = 50
    static let stripHeight: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let total = max(model.totalDuration, 0.001)
            let scale = width / total
            let boxTop = Self.labelHeight
            let bedStart = CGFloat(max(0, music.start)) * scale
            let bedEnd = CGFloat(min(total, music.end)) * scale
            let voices = model.voiceSpansOnTimeline
            ZStack(alignment: .topLeading) {
                Text(VideoStudioCopy.graphLane(model.laneName(for: music)))
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.45))
                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: max(0, bedEnd - bedStart), height: Self.boxHeight)
                    .offset(x: bedStart, y: boxTop)
                Canvas { context, _ in
                    let steps = max(2, Int((bedEnd - bedStart) / 2))
                    var line = Path()
                    var fill = Path()
                    func y(at time: Double) -> CGFloat {
                        let gain = DuckingMath.duckGain(at: time, dips: dips, ducking: music.ducking)
                        let decibels = 20 * log10(max(gain, 1e-4))
                        let depth = min(CGFloat(abs(decibels)) * 26 / 12, Self.boxHeight)
                        return boxTop + depth
                    }
                    for step in 0...steps {
                        let x = bedStart + (bedEnd - bedStart) * CGFloat(step) / CGFloat(steps)
                        let point = CGPoint(x: x, y: y(at: Double(x / scale)))
                        if step == 0 {
                            line.move(to: point)
                            fill.move(to: CGPoint(x: x, y: boxTop))
                        }
                        line.addLine(to: point)
                        fill.addLine(to: point)
                    }
                    fill.addLine(to: CGPoint(x: bedEnd, y: boxTop))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(EditorTheme.timelineSpeech.opacity(0.3)))
                    context.stroke(line, with: .color(.white), lineWidth: 1.6)
                }
                .allowsHitTesting(false)
                ForEach(Array(dips.enumerated()), id: \.offset) { _, dip in
                    let mid = CGFloat((dip.start + dip.end) / 2) * scale
                    if mid >= bedStart, mid <= bedEnd {
                        Text(VideoStudioCopy.decibels(music.ducking.amountDB))
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize()
                            .position(x: mid, y: boxTop + CGFloat(DuckingMath.dipDepth(amountDB: music.ducking.amountDB)) + 8)
                    }
                }
                // The clips, grey, and their voices in blue.
                let placements = clipPlacements
                ForEach(Array(placements.enumerated()), id: \.offset) { _, placement in
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: max(0, CGFloat(placement.duration) * scale - 1), height: Self.stripHeight)
                        .offset(x: CGFloat(placement.start) * scale, y: boxTop + Self.boxHeight + 6)
                }
                ForEach(Array(voices.enumerated()), id: \.offset) { _, voice in
                    Rectangle()
                        .fill(EditorTheme.timelineSpeech)
                        .frame(width: max(1, CGFloat(voice.duration) * scale), height: Self.stripHeight)
                        .offset(x: CGFloat(voice.start) * scale, y: boxTop + Self.boxHeight + 6)
                }
                Rectangle()
                    .fill(EditorTheme.clipping)
                    .frame(width: 2, height: Self.boxHeight + Self.stripHeight + 6)
                    .offset(x: CGFloat(min(model.currentTime, total)) * scale - 1, y: boxTop)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(VideoStudioCopy.musicLevel))
        .accessibilityValue(Text(model.duckingSummary(for: music)))
    }

    private var clipPlacements: [VideoTimelineMath.Placement] {
        let recipe = model.recipe
        let durations = recipe.clips.map(\.effectiveDuration)
        let overlaps = VideoTimelineMath.effectiveOverlaps(requested: recipe.transitions.map(\.requestedOverlap), durations: durations)
        return VideoTimelineMath.placements(durations: durations, overlaps: overlaps)
    }
}
