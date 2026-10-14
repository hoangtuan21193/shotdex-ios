import SwiftUI
import UniformTypeIdentifiers

/// Full-screen playback (FS-23.02 §2–3): black, a spinner only after 350 ms,
/// a card that says why when a movie can't play, and the transport — top bar,
/// the −10/play/+10 cluster over the picture and a two-row glass panel, all
/// fading together after 3 s of play. Board `PH_MoviePlayer`.
struct MoviePlayerScreen: View {
    @State var model: MoviePlayerModel
    let videoView: UIView
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSpinner = false

    var body: some View {
        // Measured inside the safe area so the insets are known; the stage
        // then covers the whole screen and pads its chrome by hand, since a
        // turned stage cannot use the system's insets.
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let screen = CGSize(
                width: proxy.size.width + insets.leading + insets.trailing,
                height: proxy.size.height + insets.top + insets.bottom
            )
            let layout = MoviePlayerLayout(
                size: screen,
                safeArea: insets,
                isCompactWidth: horizontalSizeClass == .compact,
                isLandscapePicture: model.isLandscapePicture
            )
            stage(layout: layout)
                .ignoresSafeArea()
                .frame(width: layout.stageSize.width, height: layout.stageSize.height)
                .rotationEffect(.degrees(layout.isRotated ? 90 : 0))
                .position(x: screen.width / 2 - insets.leading, y: screen.height / 2 - insets.top)
        }
        .background(Color.black.ignoresSafeArea())
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isChromeVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.showsUnlock)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isTracksPanelOpen)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            await model.loadSubtitles()
        }
        .task {
            model.start()
            try? await Task.sleep(for: .milliseconds(350))
            showsSpinner = true
        }
        .task(id: model.resumedAtMs) {
            guard model.resumedAtMs != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            model.dismissResumeNotice()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.resumedAtMs)
        .task(id: model.interaction) {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            model.hideAfterIdle()
        }
        // The screen stays on while the movie plays, and only then (§2).
        .onChange(of: model.isPlaying, initial: true) { _, playing in
            UIApplication.shared.isIdleTimerDisabled = playing
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.enterBackground() }
        }
        .fileImporter(
            isPresented: Binding(get: { model.isPickingSubtitleFiles }, set: { model.isPickingSubtitleFiles = $0 }),
            allowedContentTypes: Self.subtitleTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await model.importSubtitles(urls) }
        }
        .alert(
            String(localized: "Couldn't Add the Subtitle", comment: "Import File… failed"),
            isPresented: Binding(get: { model.subtitleImportFailure != nil }, set: { if !$0 { model.dismissSubtitleImportFailure() } }),
            presenting: model.subtitleImportFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { Text($0) }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.close()
        }
        .accessibilityElement(children: .contain)
    }

    private func stage(layout: MoviePlayerLayout) -> some View {
        let insets = layout.chromeInsets
        return ZStack {
            Color.black
            VideoSurface(view: videoView)
            touchLayer
            if !model.isFailed {
                MovieSubtitleOverlay(
                    model: model,
                    chromeTop: subtitleFloor(layout: layout),
                    chromeBottom: subtitleFloor(layout: layout).map { _ in layout.chromeInsets.top + 44 },
                    covered: panelCover(layout: layout)
                )
            }
            if let reason = model.failureReason {
                failureCard(reason)
                VStack {
                    topBar
                    Spacer(minLength: 0)
                }
                .padding(insets)
            } else {
                if showsSpinner {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        if model.needsSpinner(at: context.date) {
                            ProgressView().tint(.white).controlSize(.large)
                        }
                    }
                    .allowsHitTesting(false)
                }
                if model.isChromeVisible, !model.isLocked {
                    chrome(insets: insets).transition(.opacity)
                }
                if model.isLocked, model.showsUnlock {
                    unlockButton.padding(insets).transition(.opacity)
                }
                if model.isTracksPanelOpen {
                    tracksPanel(layout: layout).transition(.opacity)
                }
                if let resumedAt = model.resumedAtMs, !model.isLocked {
                    resumeNotice(resumedAt)
                        .padding(insets)
                        .padding(.top, 56)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Taps on the picture: one toggles the chrome, two skip by half.
    private var touchLayer: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in
                            model.doubleTap(isLeading: value.location.x < proxy.size.width / 2)
                        }
                        .exclusively(before: SpatialTapGesture(count: 1).onEnded { _ in model.tapPicture() })
                )
                // Pinch out fills the frame, pinch in fits the picture (§3).
                .simultaneousGesture(
                    MagnifyGesture().onEnded { value in
                        guard !model.isLocked else { return }
                        if value.magnification > 1.1 { model.setFill(true) }
                        if value.magnification < 0.9 { model.setFill(false) }
                    }
                )
        }
        .accessibilityHidden(true)
    }

    private func chrome(insets: EdgeInsets) -> some View {
        ZStack {
            // Board PH_MoviePlayer: the cluster sits 45 pt above the middle,
            // clear of the panel's two rows.
            centerCluster.offset(y: -45)
            VStack(spacing: AppTheme.Spacing.sm) {
                topBar
                Spacer(minLength: 0)
                if model.isChoosingRate {
                    rateChoices.transition(.opacity)
                }
                panel
            }
            .padding(insets)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        ZStack {
            Text(model.movie.displayTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .padding(.horizontal, 60)
            HStack {
                roundButton("xmark", size: 44, glyph: 16, label: String(localized: "Close", comment: "Movie player: close")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer(minLength: 0)
                if model.canPictureInPicture, !model.isFailed {
                    roundButton(
                        model.isPictureInPictureActive ? "pip.exit" : "pip.enter",
                        size: 44,
                        glyph: 18,
                        label: String(localized: "Picture in Picture", comment: "Movie player: PiP button")
                    ) {
                        model.togglePictureInPicture()
                    }
                }
            }
        }
    }

    // MARK: Centre cluster

    private var centerCluster: some View {
        HStack(spacing: 38) {
            roundButton("gobackward.10", size: 56, glyph: 22, label: String(localized: "Back 10 Seconds", comment: "Movie player: skip back")) {
                model.skip(by: -MoviePlayerModel.skipMs)
            }
            roundButton(model.isPlaying ? "pause.fill" : "play.fill", size: 68, glyph: 26, label: playLabel) {
                model.togglePlay()
            }
            .keyboardShortcut(.space, modifiers: [])
            roundButton("goforward.10", size: 56, glyph: 22, label: String(localized: "Forward 10 Seconds", comment: "Movie player: skip forward")) {
                model.skip(by: MoviePlayerModel.skipMs)
            }
        }
        .background {
            Button("") { model.skip(by: -MoviePlayerModel.skipMs) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
            Button("") { model.skip(by: MoviePlayerModel.skipMs) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    /// `Audio and Subtitles: English AC3 5.1` (§5).
    private var tracksLabel: String {
        let name = String(localized: "Audio and Subtitles", comment: "Movie player: the button that opens the Audio & Subtitles panel")
        let index = model.audioTracks.firstIndex { $0.id == model.selectedAudioTrackId }
        guard let index, let audio = MovieTracksText.summary(model.audioTracks[index], position: index + 1) else { return name }
        return "\(name): \(audio)"
    }

    private var playLabel: String {
        model.isPlaying
            ? String(localized: "Pause", comment: "Movie player: pause")
            : String(localized: "Play", comment: "Movie player: play")
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: 4) {
            timelineRow
            controlsRow
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: 750)
        .editorGlass(cornerRadius: 22)
        .environment(\.colorScheme, .dark)
    }

    /// Board PH_MoviePlayer: play 44 · elapsed 64 · scrubber · remaining 70.
    private var timelineRow: some View {
        HStack(spacing: 0) {
            Button {
                model.togglePlay()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(playLabel)
            .padding(.trailing, AppTheme.Spacing.xs)

            Text(MoviePlayerText.clock(model.displayMs, longest: model.durationMs))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 64, alignment: .leading)
                .accessibilityHidden(true)

            Slider(
                value: Binding(
                    get: { Double(model.displayMs) / 1000 },
                    set: { model.scrub(toMs: Int64($0 * 1000)) }
                ),
                in: 0...VideoTransportMath.timelineUpperBound(
                    duration: Double(model.durationMs) / 1000,
                    current: Double(model.timeMs) / 1000,
                    scrub: Double(model.displayMs) / 1000
                ),
                onEditingChanged: { editing in if !editing { model.endScrub() } }
            )
            .tint(.white)
            .accessibilityLabel(String(localized: "Position", comment: "Movie player: VoiceOver name of the scrubber"))
            .accessibilityValue(MoviePlayerText.spokenPosition(model.displayMs, of: model.durationMs))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: model.skip(by: MoviePlayerModel.skipMs)
                case .decrement: model.skip(by: -MoviePlayerModel.skipMs)
                @unknown default: break
                }
            }
            .padding(.trailing, 2)

            Text(MoviePlayerText.remaining(model.displayMs, of: model.durationMs))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 70, alignment: .trailing)
                .padding(.trailing, 6)
                .accessibilityHidden(true)
        }
        .frame(height: 44)
    }

    /// The six speeds, drawn in the stage rather than as a system menu: on
    /// an upright phone the stage is turned and a menu would come up
    /// sideways.
    private var rateChoices: some View {
        HStack(spacing: 2) {
            ForEach(MoviePlayerModel.rates, id: \.self) { rate in
                let isSelected = rate == model.rate
                Button {
                    model.setRate(rate)
                } label: {
                    Text(MoviePlayerText.rate(rate))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(isSelected ? .black : .white)
                        .frame(minWidth: 52, minHeight: 44)
                        .background(isSelected ? Color.white : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoviePlayerText.rate(rate))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .editorGlass(Capsule())
        .environment(\.colorScheme, .dark)
    }

    /// Speed, Audio & Subtitles, Fit/Fill and the touch lock.
    private var controlsRow: some View {
        HStack(spacing: 32) {
            Button {
                model.toggleRateChoices()
            } label: {
                Text(MoviePlayerText.rate(model.rate))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(model.isChoosingRate ? Color.white.opacity(0.2) : .clear, in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Playback Speed \(MoviePlayerText.rate(model.rate))", comment: "Movie player: speed button, with the current speed"))

            Button {
                model.openTracksPanel()
            } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(tracksLabel)

            Button {
                model.setFill(!model.fillsFrame)
            } label: {
                Image(systemName: model.fillsFrame ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            // Names what the picture is doing now; the button flips it.
            .accessibilityLabel(model.fillsFrame
                ? String(localized: "Fill", comment: "Movie player: picture fills the frame, edges cropped")
                : String(localized: "Fit", comment: "Movie player: whole picture fits, black bars"))

            Button {
                model.lock()
            } label: {
                Image(systemName: "lock")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(String(localized: "Lock Controls", comment: "Movie player: touch lock"))
        }
        .frame(height: 44)
    }

    /// Import File… (FS-23.03 §5): srt, ass, ssa, vtt and zip.
    static let subtitleTypes: [UTType] = ["srt", "ass", "ssa", "vtt"].compactMap { UTType(filenameExtension: $0) } + [.zip]

    /// Panel height: two 44 pt rows, 4 between, 4 above and below.
    static let panelHeight: CGFloat = 100

    /// Subtitles rise above the transport glass while it shows (§4).
    private func subtitleFloor(layout: MoviePlayerLayout) -> CGFloat? {
        guard model.isChromeVisible, !model.isLocked, !model.isTracksPanelOpen else { return nil }
        return layout.stageSize.height - layout.chromeInsets.bottom - Self.panelHeight
    }

    /// What the open panel hides of the stage, for the subtitles.
    private func panelCover(layout: MoviePlayerLayout) -> EdgeInsets {
        guard model.isTracksPanelOpen else { return EdgeInsets() }
        if layout.stageSize.width > layout.stageSize.height {
            return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: layout.chromeInsets.trailing + 370)
        }
        return EdgeInsets(top: 0, leading: 0, bottom: layout.chromeInsets.bottom + layout.stageSize.height / 2, trailing: 0)
    }

    /// A column on the right of a wide stage (board `PH_MovieTracks`: 370 pt,
    /// 12 from the top), the lower half of a tall one (§3b).
    @ViewBuilder
    private func tracksPanel(layout: MoviePlayerLayout) -> some View {
        let insets = layout.chromeInsets
        if layout.stageSize.width > layout.stageSize.height {
            HStack {
                Spacer(minLength: 0)
                MovieTracksPanel(model: model)
                    .frame(width: 370)
            }
            .padding(.top, AppTheme.Spacing.md)
            .padding(.bottom, insets.bottom)
            .padding(.trailing, insets.trailing)
        } else {
            VStack {
                Spacer(minLength: 0)
                MovieTracksPanel(model: model)
                    .frame(maxWidth: 560)
                    .frame(height: layout.stageSize.height / 2)
            }
            .padding(.bottom, insets.bottom)
            .padding(.horizontal, insets.leading)
        }
    }

    /// `Resumed at 47:12 · Start Over` (§2): one line, the second half is
    /// the button.
    private func resumeNotice(_ ms: Int64) -> some View {
        VStack {
            HStack(spacing: AppTheme.Spacing.sm) {
                Text(String(localized: "Resumed at \(MoviePlayerText.clock(ms, longest: model.durationMs))", comment: "Movie player: the movie reopened where it was left, e.g. Resumed at 47:12"))
                    .foregroundStyle(.white.opacity(0.8))
                Text(verbatim: "·")
                    .foregroundStyle(.white.opacity(0.5))
                    .accessibilityHidden(true)
                Button(String(localized: "Start Over", comment: "Movie player: play the movie from the beginning")) {
                    model.startOver()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
            }
            .font(.subheadline.monospacedDigit())
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 44)
            .editorGlass(Capsule())
            Spacer(minLength: 0)
        }
    }

    private var unlockButton: some View {
        VStack {
            Spacer(minLength: 0)
            Button {
                model.unlock()
            } label: {
                Label(String(localized: "Unlock Controls", comment: "Movie player: leave the touch lock"), systemImage: "lock.open")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .frame(minHeight: 44)
                    .editorGlass(Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
    }

    private func roundButton(_ systemImage: String, size: CGFloat, glyph: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyph, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .editorGlass(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func failureCard(_ reason: String) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            Text(String(localized: "Can't Play This Movie", comment: "Movie player: playback failed"))
                .font(.headline)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Close", comment: "Movie player: close after an error")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, AppTheme.Spacing.sm)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// The engine's own view, placed in SwiftUI.
private struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

enum MoviePlayerText {
    /// `47:12`, or `1:47:12` once the movie runs an hour.
    static func clock(_ ms: Int64, longest total: Int64) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = max(ms, total) >= 3_600_000 ? .hourMinuteSecond : .minuteSecond
        return Duration.milliseconds(max(0, ms)).formatted(.time(pattern: pattern))
    }

    /// `−1:59:00`; blank while the length is unknown.
    static func remaining(_ ms: Int64, of total: Int64) -> String {
        guard total > 0 else { return "" }
        return "\u{2212}" + clock(max(0, total - ms), longest: total)
    }

    /// `47:12 / 2:04:01`.
    static func position(_ ms: Int64, of total: Int64) -> String {
        guard total > 0 else { return clock(ms, longest: 0) }
        return "\(clock(ms, longest: total)) / \(clock(total, longest: total))"
    }

    /// `47 minutes 12 seconds of 2 hours 4 minutes`.
    static func spokenPosition(_ ms: Int64, of total: Int64) -> String {
        let now = Duration.milliseconds(max(0, ms)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        guard total > 0 else { return now }
        let length = Duration.milliseconds(total).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return String(localized: "\(now) of \(length)", comment: "Movie player: VoiceOver value of the scrubber, e.g. 47 minutes 12 seconds of 2 hours 4 minutes")
    }

    /// `1×`, `1.25×`.
    static func rate(_ rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "\u{00D7}"
    }
}
