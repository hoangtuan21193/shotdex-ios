import AVFoundation
import SwiftUI

/// The Music tool's panel (FS-12.04 §3–4, board P4): Video sound — the one
/// project-wide level — then Add Music from Files… and My Music. Choosing a
/// song adds a track at the playhead and selects it.
///
/// Only the contents: the phone hosts it in its panel under a 46pt title,
/// and the iPad's media pool can host the same view in its Music tab.
struct VideoMusicPanelContent: View {
    @Bindable var model: VideoStudioModel
    @ObservedObject var importedMusic: ImportedMusicStore
    let onImport: () -> Void
    /// The phone's and the Duo's panel, or the iPad pool's Music tab — the
    /// Mac-style canvas's sizes: 44pt buttons, 17pt names, Title Case.
    var style: Style = .panel

    enum Style { case panel, pool }

    private typealias Pool = VideoStudioMetrics.Pool
    private var isPool: Bool { style == .pool }
    /// Labels' inset from the panel's edge.
    private var textInset: CGFloat { isPool ? Pool.titleLeading : 16 }

    @StateObject private var preview = MusicPreviewPlayer()
    @StateObject private var waveforms = MusicWaveformCache()
    /// A track the user asked to delete while it is on the timeline.
    @State private var trackPendingDeletion: ImportedMusicTrack?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: isPool ? 0 : 6)
                InspectorSlider(
                    label: VideoStudioCopy.videoSound, value: model.recipe.videoVolume, range: 0...1,
                    valueText: "\(Int(model.recipe.videoVolume * 100))", model: model,
                    set: { model.setVideoVolume($0) },
                    reset: { model.pushUndo(); model.setVideoVolume(1) }
                )
                Text(VideoStudioCopy.videoSoundCaption)
                    .font(.system(size: isPool ? 13 : 11))
                    .foregroundStyle(.white.opacity(isPool ? 0.55 : 0.35))
                    .padding(.horizontal, textInset)
                    .padding(.bottom, isPool ? 10 : 8)
                importButton
                Group {
                    if isPool {
                        Text(VideoStudioCopy.myMusicTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(height: Pool.sectionTitleHeight)
                            .padding(.top, Pool.sectionGap - 2)
                            .padding(.bottom, 10)
                    } else {
                        Text(VideoStudioCopy.myMusic)
                            .font(.system(size: 11, weight: .bold)).tracking(0.6)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                    }
                }
                .padding(.horizontal, textInset)
                .accessibilityAddTraits(.isHeader)
                if importedMusic.tracks.isEmpty {
                    Text("Add a track from Files — it's saved here for reuse.")
                        .font(.system(size: 12))
                        .foregroundStyle(EditorTheme.dimText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                } else {
                    ForEach(importedMusic.tracks) { track in
                        row(track)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .onDisappear { preview.stop() }
        .alert(
            "Delete Music in Use?",
            isPresented: Binding(
                get: { trackPendingDeletion != nil },
                set: { if !$0 { trackPendingDeletion = nil } }
            ),
            presenting: trackPendingDeletion
        ) { track in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { importedMusic.delete(track) }
        } message: { track in
            Text("\(track.displayName) is on this video's timeline. Deleting it removes the file, and the track goes silent in the preview and the export.")
        }
    }

    private var importButton: some View {
        Button {
            preview.stop()
            onImport()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus").font(.system(size: isPool ? 18 : 17))
                Text("Add Music from Files…").font(.system(size: isPool ? 17 : 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: isPool ? Pool.buttonHeight : 48)
            .background(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, isPool ? Pool.inset : 16)
    }

    private func isInUse(_ url: URL) -> Bool {
        model.recipe.musicTracks.contains { music in
            if case .imported(let used, _) = music.source { return used == url }
            return false
        }
    }

    private func row(_ track: ImportedMusicTrack) -> some View {
        let isPlaying = preview.playingID == track.url.absoluteString
        let inUse = isInUse(track.url)
        return HStack(spacing: 10) {
            Button {
                preview.toggle(id: track.url.absoluteString, url: track.url)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.white.opacity(0.14)))
                    .frame(width: isPool ? 44 : 34, height: isPool ? 44 : 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? Text("Stop preview") : Text("Preview \(track.displayName)"))

            Button {
                preview.stop()
                model.addMusicTrack(source: .imported(url: track.url, displayName: track.displayName))
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayName).font(.system(size: isPool ? 17 : 13.5, weight: .medium)).lineLimit(1)
                        Text(waveforms.detail(for: track.id, url: track.url))
                            .font(.system(size: isPool ? 13 : 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    Spacer(minLength: 0)
                    if inUse { Image(systemName: "checkmark").foregroundStyle(.white) }
                    if !isPool {
                        MusicRowWaveform(samples: waveforms.samples(for: track.id), active: isPlaying)
                            .frame(width: 56, height: 20)
                    }
                }
                .foregroundStyle(.white)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .task(id: track.id) { await waveforms.load(id: track.id, url: track.url) }

            Button {
                preview.stop()
                if inUse { trackPendingDeletion = track } else { importedMusic.delete(track) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundStyle(EditorTheme.timelineDestructive)
                    .frame(width: isPool ? 44 : 30, height: isPool ? 44 : 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete \(track.displayName)"))
        }
        .padding(.horizontal, isPool ? Pool.rowInset : 16)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}
