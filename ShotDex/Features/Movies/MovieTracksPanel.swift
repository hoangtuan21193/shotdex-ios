import AVFoundation
import SwiftUI

/// Audio & Subtitles (FS-23.02 §3b, board `PH_MovieTracks`): one panel for
/// sound and subtitles, over the playing movie — a 370 pt column on the
/// right of a wide stage, the lower half of a tall one. Audio comes first;
/// the Subtitles part joins in plan task 23.
struct MovieTracksPanel: View {
    let model: MoviePlayerModel
    /// A row opened as a page of the panel. Pages, not system menus: on an
    /// upright phone the stage is turned, and a system menu would come up
    /// sideways to the viewer.
    @State private var page: Page?

    enum Page: Equatable {
        case choose(MoviePlayerModel.SubtitleLine)
        case position
        case style(MoviePlayerModel.SubtitleLine)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(EditorTheme.glassStroke)
            switch page {
            case .style(let line):
                MovieSubtitleStyleEditor(model: model, line: line) { page = nil }
            case .choose(let line):
                subtitleChoices(line)
            case .position:
                positionChoices
            case nil:
                trackList
            }
        }
        .foregroundStyle(.white)
        .background(EditorTheme.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(EditorTheme.glassStroke, lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private var trackList: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader(String(localized: "Audio", comment: "Movie player panel: section over the audio tracks"))
                    ForEach(Array(model.audioTracks.enumerated()), id: \.element.id) { index, track in
                        audioRow(track, position: index + 1)
                    }
                    if model.audioTracks.isEmpty {
                        Text(String(localized: "No Audio", comment: "Movie player panel: the movie has no audio track"))
                            .font(.subheadline)
                            .foregroundStyle(EditorTheme.secondaryText)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .frame(height: 40)
                    }
                    audioSyncRow
                    Text(MovieTracksText.route(AVAudioSession.sharedInstance().currentRoute))
                        .font(.caption)
                        .foregroundStyle(EditorTheme.secondaryText)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .padding(.bottom, AppTheme.Spacing.xs)

                    sectionHeader(String(localized: "Subtitles", comment: "Movie player panel: section over the subtitle rows"))
                    subtitleMenuRow(.primary)
                    subtitleMenuRow(.secondary)
                    if model.subtitleChoice.secondaryId != nil {
                        positionRow
                    }
                    styleRow(.primary)
                    if model.subtitleChoice.secondaryId != nil {
                        styleRow(.secondary)
                    }
                }
                .padding(.bottom, AppTheme.Spacing.md)
            }
    }

    // MARK: Subtitles (FS-23.03 §2)

    private func lineName(_ line: MoviePlayerModel.SubtitleLine) -> String {
        switch line {
        case .primary: String(localized: "Primary", comment: "Movie player panel: the main subtitle")
        case .secondary: String(localized: "Secondary", comment: "Movie player panel: the second subtitle")
        }
    }

    private func subtitleMenuRow(_ line: MoviePlayerModel.SubtitleLine) -> some View {
        let selectedId = line == .primary ? model.subtitleChoice.primaryId : model.subtitleChoice.secondaryId
        let value = model.subtitle(id: selectedId).map(model.subtitleTitle) ?? String(localized: "Off", comment: "Movie player panel: no subtitle on this line")
        return Button {
            page = .choose(line)
        } label: {
            valueRow(lineName(line), value: value)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lineName(line))
        .accessibilityValue(value)
    }

    private var positionRow: some View {
        let title = String(localized: "Position", comment: "Movie player panel: where the two subtitles sit")
        let value = MovieSubtitleLabel.positionValue(model.subtitleStyle.position)
        return Button {
            page = .position
        } label: {
            valueRow(title, value: value)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    /// Off, every subtitle, and — for the Secondary — Import File… (§2).
    private func subtitleChoices(_ line: MoviePlayerModel.SubtitleLine) -> some View {
        let selectedId = line == .primary ? model.subtitleChoice.primaryId : model.subtitleChoice.secondaryId
        let choices = model.subtitles.filter { line == .primary || model.hasText($0) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backRow(lineName(line))
                choiceRow(String(localized: "Off", comment: "Movie player panel: no subtitle on this line"), isSelected: selectedId == nil) {
                    Task { await model.selectSubtitle(nil, for: line) }
                    page = nil
                }
                ForEach(choices) { subtitle in
                    choiceRow(model.subtitleTitle(subtitle), isSelected: selectedId == subtitle.id) {
                        Task { await model.selectSubtitle(subtitle.id, for: line) }
                        page = nil
                    }
                }
                if line == .secondary, model.canImportSubtitles {
                    Divider().overlay(EditorTheme.glassStroke).padding(.leading, AppTheme.Spacing.lg)
                    Button {
                        page = nil
                        model.isPickingSubtitleFiles = true
                    } label: {
                        Label(String(localized: "Import File…", comment: "Movie player panel: add subtitle files from Files"), systemImage: "square.and.arrow.down")
                            .font(.subheadline)
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    private var positionChoices: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                backRow(String(localized: "Position", comment: "Movie player panel: where the two subtitles sit"))
                ForEach(DualSubtitlePosition.allCases, id: \.self) { position in
                    choiceRow(MovieSubtitleLabel.position(position), isSelected: model.subtitleStyle.position == position) {
                        model.setSubtitlePosition(position)
                        page = nil
                    }
                }
            }
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    private func backRow(_ title: String) -> some View {
        Button {
            page = nil
        } label: {
            Label(title, systemImage: "chevron.left")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, AppTheme.Spacing.lg)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Back", comment: "Movie player panel: leave a page"))
    }

    private func choiceRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 15)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func styleRow(_ line: MoviePlayerModel.SubtitleLine) -> some View {
        let title = line == .primary
            ? String(localized: "Primary Style", comment: "Movie player panel: size, color and sync of the main subtitle")
            : String(localized: "Secondary Style", comment: "Movie player panel: size, color and sync of the second subtitle")
        let value = MovieSubtitleLabel.style(line == .primary ? model.subtitleStyle.primary : model.subtitleStyle.secondary, offsetMs: model.subtitleSyncMs(for: line))
        return Button {
            page = .style(line)
        } label: {
            valueRow(title, value: value)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer(minLength: AppTheme.Spacing.sm)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: 44)
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack {
            Text(String(localized: "Audio & Subtitles", comment: "Movie player panel title"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: AppTheme.Spacing.sm)
            Button {
                model.closeTracksPanel()
            } label: {
                Text(String(localized: "Done", comment: "Movie player panel: close"))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(EditorTheme.control, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.md)
        .frame(height: 56)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(EditorTheme.secondaryText)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.top, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    private func audioRow(_ track: MovieAudioTrack, position: Int) -> some View {
        let isSelected = track.id == model.selectedAudioTrackId
        let title = MovieAudioTrackLabel.title(track, position: position)
        let detail = track.isSupported
            ? MovieAudioTrackLabel.detail(track)
            : String(localized: "Not supported on this device", comment: "Movie player panel: audio track the device cannot decode")
        return Button {
            model.selectAudio(id: track.id)
        } label: {
            HStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.semibold))
                    .opacity(isSelected ? 1 : 0)
                    .frame(width: 15)
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .layoutPriority(1)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if track.isDefault {
                    Text(String(localized: "Default", comment: "Movie player panel: the track the file marks as default"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(EditorTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .frame(height: 18)
                        .background(EditorTheme.control, in: Capsule())
                }
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .frame(height: 40)
            .contentShape(Rectangle())
            .opacity(track.isSupported ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!track.isSupported)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([title, detail, track.isDefault ? String(localized: "Default", comment: "Movie player panel: the track the file marks as default") : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var audioSyncRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(String(localized: "Audio Sync", comment: "Movie player panel: shift the sound against the picture"))
                .font(.subheadline)
            Spacer(minLength: 0)
            stepButton("minus", label: String(localized: "Earlier", comment: "Movie player panel: Audio Sync, sound earlier")) {
                model.nudgeAudioDelay(by: -1)
            }
            Text(MovieTracksText.delay(model.audioDelayMs))
                .font(.subheadline.monospacedDigit())
                .frame(width: 58)
                .accessibilityHidden(true)
            stepButton("plus", label: String(localized: "Later", comment: "Movie player panel: Audio Sync, sound later")) {
                model.nudgeAudioDelay(by: 1)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Audio Sync", comment: "Movie player panel: shift the sound against the picture"))
        .accessibilityValue(MovieTracksText.delay(model.audioDelayMs))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.nudgeAudioDelay(by: 1)
            case .decrement: model.nudgeAudioDelay(by: -1)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 34, height: 28)
                .background(EditorTheme.control, in: Capsule())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .buttonRepeatBehavior(.enabled)
    }
}

enum MovieTracksText {
    /// `0.00 s`, `+0.30 s`, `−0.30 s`.
    static func delay(_ ms: Int) -> String {
        let seconds = (Double(abs(ms)) / 1000).formatted(.number.precision(.fractionLength(2)))
        switch ms {
        case ..<0: return "\u{2212}\(seconds) s"
        case 0: return "\(seconds) s"
        default: return "+\(seconds) s"
        }
    }

    /// `Playing as stereo on AirPods Pro` (§3b): a track with more channels
    /// than the output is mixed down, not refused.
    static func route(_ route: AVAudioSessionRouteDescription) -> String {
        guard let output = route.outputs.first else { return "" }
        let channels = output.channels?.count ?? 2
        let layout = MovieAudioTrackLabel.channelName(channels).localizedLowercase
        return String(localized: "Playing as \(layout) on \(output.portName)", comment: "Movie player panel footer, e.g. Playing as stereo on AirPods Pro")
    }

    /// `English AC3 5.1` — what the transport button reads out.
    static func summary(_ track: MovieAudioTrack?, position: Int) -> String? {
        guard let track else { return nil }
        let detail = MovieAudioTrackLabel.detail(track)
        let title = MovieAudioTrackLabel.title(track, position: position)
        return detail.isEmpty ? title : "\(title) \(detail)"
    }
}

/// Primary Style / Secondary Style (FS-23.03 §2): size 50–200 %, one of the
/// four subtitle colors, Sync −10…+10 s — every change shows at once.
private struct MovieSubtitleStyleEditor: View {
    let model: MoviePlayerModel
    let line: MoviePlayerModel.SubtitleLine
    let onBack: () -> Void

    private var style: MovieSubtitleStyle.Line {
        line == .primary ? model.subtitleStyle.primary : model.subtitleStyle.secondary
    }

    private var title: String {
        line == .primary
            ? String(localized: "Primary Style", comment: "Movie player panel: size, color and sync of the main subtitle")
            : String(localized: "Secondary Style", comment: "Movie player panel: size, color and sync of the second subtitle")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onBack) {
                    Label(title, systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, AppTheme.Spacing.lg)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Back", comment: "Movie player panel: leave the style page"))

                stepperRow(
                    String(localized: "Size", comment: "Subtitle style: text size"),
                    value: style.scale.formatted(.percent.precision(.fractionLength(0))),
                    earlier: String(localized: "Smaller", comment: "Subtitle style: size down"),
                    later: String(localized: "Larger", comment: "Subtitle style: size up")
                ) { step in
                    model.setSubtitleScale(((style.scale * 10).rounded() + Double(step)) / 10, for: line)
                }

                colorRow

                stepperRow(
                    String(localized: "Sync", comment: "Subtitle style: shift the subtitle against the picture"),
                    value: MovieSubtitleLabel.sync(model.subtitleSyncMs(for: line)),
                    earlier: String(localized: "Earlier", comment: "Subtitle Sync: subtitle earlier"),
                    later: String(localized: "Later", comment: "Subtitle Sync: subtitle later")
                ) { step in
                    model.setSubtitleSync(model.subtitleSyncMs(for: line) + step * 100, for: line)
                }
            }
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    private var colorRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(String(localized: "Color", comment: "Subtitle style: text color"))
                .font(.subheadline)
            Spacer(minLength: 0)
            ForEach(MovieSubtitleStyle.Color.allCases, id: \.self) { color in
                Button {
                    model.setSubtitleColor(color, for: line)
                } label: {
                    Circle()
                        .fill(color.swatch)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(.white, lineWidth: style.color == color ? 2 : 0).padding(-4))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MovieSubtitleLabel.colorName(color))
                .accessibilityAddTraits(style.color == color ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.leading, AppTheme.Spacing.lg)
        .padding(.trailing, AppTheme.Spacing.sm)
        .frame(height: 48)
    }

    private func stepperRow(_ title: String, value: String, earlier: String, later: String, step: @escaping (Int) -> Void) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text(title)
                .font(.subheadline)
            Spacer(minLength: 0)
            stepButton("minus", label: earlier) { step(-1) }
            Text(value)
                .font(.subheadline.monospacedDigit())
                .frame(width: 58)
                .accessibilityHidden(true)
            stepButton("plus", label: later) { step(1) }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(1)
            case .decrement: step(-1)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(width: 34, height: 28)
                .background(EditorTheme.control, in: Capsule())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .buttonRepeatBehavior(.enabled)
    }
}
