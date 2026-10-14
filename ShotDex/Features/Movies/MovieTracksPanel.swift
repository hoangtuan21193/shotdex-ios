import AVFoundation
import SwiftUI

/// Audio & Subtitles (FS-23.02 §3b, board `PH_MovieTracks`): one panel for
/// sound and subtitles, over the playing movie — a 370 pt column on the
/// right of a wide stage, the lower half of a tall one. Audio comes first;
/// the Subtitles part joins in plan task 23.
struct MovieTracksPanel: View {
    let model: MoviePlayerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(EditorTheme.glassStroke)
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
                        .padding(.bottom, AppTheme.Spacing.md)
                }
            }
        }
        .foregroundStyle(.white)
        .background(EditorTheme.panel.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(EditorTheme.glassStroke, lineWidth: 1))
        .environment(\.colorScheme, .dark)
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
