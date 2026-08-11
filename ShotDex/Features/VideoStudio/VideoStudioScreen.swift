import AVFoundation
import Photos
import SwiftUI
import UniformTypeIdentifiers

/// Immutable payload for presenting the Video Studio (see
/// `CompressionPresentation` for why assets live inside the item).
struct VideoStudioPresentation: Identifiable {
    let id = UUID()
    /// Pick order; photos and videos mixed.
    let assets: [PHAsset]
    let mode: VideoStudioMode
}

/// Full-screen video editor (Turn 2): a floating command band over the Dynamic
/// Island, the preview, a transport bar, the multi-track timeline with a fixed
/// centre playhead, and a 260pt inspector that reskins per selected object —
/// never a sheet.
struct VideoStudioScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppDependencies.self) private var dependencies

    let assets: [PHAsset]
    let mode: VideoStudioMode
    var onSaved: (String) -> Void

    @State private var model: VideoStudioModel?
    @State private var isDiscardConfirmationPresented = false
    @State private var isExportSheetPresented = false
    @State private var isMusicImporterPresented = false
    @State private var isFontPickerPresented = false
    @State private var isMusicChooserPresented = false
    @State private var isStickerPickerPresented = false
    @State private var mediaPickerMode: MediaPickerMode?
    @State private var editingOverlay: PhotoOverlay?
    @StateObject private var importedMusic = ImportedMusicStore()

    private enum MediaPickerMode: Identifiable {
        case add, replace
        var id: Int { self == .add ? 0 : 1 }
    }

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let model, model.phase == .ready {
                content(model)
            } else if let model {
                loadingOrFailed(model)
            } else {
                ProgressView()
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            guard model == nil else { return }
            let newModel = VideoStudioModel(
                assets: assets,
                mode: mode,
                service: dependencies.videoStudio,
                photoLibrary: dependencies.photoLibrary,
                overlayFontRecents: dependencies.overlayFontRecents,
                overlayImages: dependencies.overlayImages
            )
            newModel.onSaved = { assetID in onSaved(assetID); dismiss() }
            model = newModel
            await newModel.load()
        }
        .onDisappear { model?.close() }
        .interactiveDismissDisabled(model?.hasEdits == true || isExporting)
        .confirmationDialog(
            "Discard this video?",
            isPresented: $isDiscardConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .modifier(TransitionDialog(model: model))
        .alert(
            "Video Error",
            isPresented: Binding(
                get: { model?.errorMessage != nil },
                set: { if !$0 { model?.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model?.errorMessage ?? "")
        }
        .sheet(isPresented: $isExportSheetPresented) {
            if let model {
                VideoExportSheet(model: model).presentationDetents([.height(300)])
            }
        }
        .sheet(isPresented: $isMusicChooserPresented) {
            if let model {
                VideoMusicChooserSheet(model: model, importedMusic: importedMusic, onImport: { isMusicImporterPresented = true })
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $isFontPickerPresented) {
            if let model {
                EditorFontPickerSheet(recents: model.fontRecents, current: model.lastFont) { choice in
                    model.rememberFont(choice)
                    model.updateSelectedOverlay { overlay in
                        overlay.fontPostScriptName = choice.postScriptName
                        overlay.fontFamilyName = choice.familyName
                    }
                }
            }
        }
        .sheet(item: $mediaPickerMode) { pickerMode in
            VideoMediaPicker(selectionLimit: pickerMode == .replace ? 1 : 0) { picks in
                guard let model, !picks.isEmpty else { return }
                switch pickerMode {
                case .add: model.appendMedia(picks)
                case .replace: if let first = picks.first { model.replaceSelectedClip(with: first) }
                }
            }
        }
        .sheet(isPresented: $isStickerPickerPresented) {
            EditorSignatureImagePicker(
                onPick: { data, assetID in model?.addImageOverlay(pngData: data, assetIdentifier: assetID) },
                onFailure: { model?.errorMessage = String(localized: "Couldn't add the sticker.") }
            )
        }
        .fileImporter(isPresented: $isMusicImporterPresented, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result, let model else { return }
            do {
                // Persist for reuse in later sessions, then select it.
                let track = try importedMusic.add(from: url)
                model.setMusic(MusicSelection(source: .imported(url: track.url, displayName: track.displayName)))
                model.selectMusic()
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
        .fullScreenCover(item: $editingOverlay) { overlay in
            EditorInlineTextEditor(
                initialText: overlay.text,
                tokens: .empty,
                alignment: overlay.alignment,
                onCommit: { text in model?.updateSelectedOverlay { $0.text = text }; editingOverlay = nil },
                onCancel: { editingOverlay = nil }
            )
        }
    }

    private var isExporting: Bool {
        guard let state = model?.exportState else { return false }
        switch state {
        case .exporting, .saving: return true
        default: return false
        }
    }

    // MARK: - Layout

    private func content(_ model: VideoStudioModel) -> some View {
        GeometryReader { proxy in
            // The band spans the Dynamic Island: grow it to the device's top safe
            // inset (≈59 on Face-ID iPhones) so its 11pt-inset row lands level with
            // the island and the preview starts below it — mirrors the photo editor.
            let bandHeight = max(EditorLayoutMetrics.editorTopBandHeight, proxy.safeAreaInsets.top)
            VStack(spacing: 0) {
                VideoStudioTopBand(model: model)
                    .frame(height: bandHeight, alignment: .top)
                preview(model).frame(maxHeight: .infinity)  // fills the space freed by the removed transport bar
                Color.clear.frame(height: 8)   // preview → timeline gap
                VideoTimelineView(
                    model: model,
                    onAddText: { model.addTextOverlay(String(localized: "Text"), at: model.currentTime) },
                    onAddFilter: { model.showNoneTool(.filters) },
                    onAddMusic: { isMusicChooserPresented = true },
                    onAddMedia: { mediaPickerMode = .add },
                    onEditText: { editingOverlay = $0 },
                    onTransition: { model.editingTransitionIndex = $0 }
                )
                VideoInspectorPanel(model: model, actions: actions(model))
            }
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    private func actions(_ model: VideoStudioModel) -> VideoInspectorActions {
        VideoInspectorActions(
            onExport: { isExportSheetPresented = true },
            onBack: { if model.hasEdits { isDiscardConfirmationPresented = true } else { dismiss() } },
            onAddMedia: { mediaPickerMode = .add },
            onReplaceClip: { mediaPickerMode = .replace },
            onAddSticker: { isStickerPickerPresented = true },
            onChooseMusic: { isMusicChooserPresented = true },
            onEditText: { editingOverlay = $0 },
            onPickFont: { isFontPickerPresented = true }
        )
    }

    private func preview(_ model: VideoStudioModel) -> some View {
        ZStack {
            Color.black
            if let player = model.player {
                VideoPlayerLayerView(player: player)
            }
            if !model.isPlaying {
                Button { model.togglePlayback() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color(red: 18 / 255, green: 18 / 255, blue: 20 / 255).opacity(0.55)))
                        .background(.ultraThinMaterial.opacity(0.9), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play")
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { if model.isPlaying { model.togglePlayback() } }
    }

    @ViewBuilder
    private func loadingOrFailed(_ model: VideoStudioModel) -> some View {
        switch model.phase {
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message).font(EditorTheme.maskSubtitle).foregroundStyle(EditorTheme.secondaryText)
                Button("Close") { dismiss() }
            }
        default:
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing clips…").font(EditorTheme.maskSubtitle).foregroundStyle(EditorTheme.secondaryText)
            }
        }
    }
}

/// The transition-kind chooser, driven by `model.editingTransitionIndex`.
private struct TransitionDialog: ViewModifier {
    let model: VideoStudioModel?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Transition",
            isPresented: Binding(
                get: { model?.editingTransitionIndex != nil },
                set: { if !$0 { model?.editingTransitionIndex = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let model, let index = model.editingTransitionIndex {
                ForEach(VideoTransitionKind.allCases) { kind in
                    Button(kind.displayName) {
                        let duration = model.recipe.transitions[safe: index]?.duration ?? 0.5
                        model.pushUndo()
                        model.setTransition(VideoBoundaryTransition(kind: kind, duration: duration), at: index)
                        model.editingTransitionIndex = nil
                    }
                }
                Button("Cancel", role: .cancel) { model.editingTransitionIndex = nil }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// A compact bundled-music chooser (tier D). Not a titled "sheet-panel" in the
/// timeline sense — it is the picker for choosing which bed to use.
struct VideoMusicChooserSheet: View {
    @Bindable var model: VideoStudioModel
    @ObservedObject var importedMusic: ImportedMusicStore
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = MusicPreviewPlayer()
    @StateObject private var waveforms = MusicWaveformCache()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Music").font(EditorTheme.panelTitle).foregroundStyle(.white).padding(.top, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    // Add-your-own sits at the top (accent), then the silence
                    // option, then the user's reusable imports. No bundled beds.
                    importRow
                    trackRow(
                        title: String(localized: "None"), systemImage: "speaker.slash",
                        selected: model.recipe.music == nil, trackID: nil, previewURL: nil
                    ) { model.setMusic(nil); dismiss() }

                    if importedMusic.tracks.isEmpty {
                        emptyState
                    } else {
                        Section {
                            ForEach(importedMusic.tracks) { track in
                                trackRow(
                                    title: track.displayName, systemImage: "music.note",
                                    selected: isImportedSelected(track.url), trackID: track.id, previewURL: track.url,
                                    onDelete: {
                                        if isImportedSelected(track.url) { model.setMusic(nil) }
                                        preview.stop(); importedMusic.delete(track)
                                    }
                                ) {
                                    preview.stop()
                                    model.setMusic(MusicSelection(source: .imported(url: track.url, displayName: track.displayName)))
                                    model.selectMusic(); dismiss()
                                }
                            }
                        } header: { sectionHeader(String(localized: "My Music")) }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(EditorTheme.panelSolid)
        .preferredColorScheme(.dark)
        .onDisappear { preview.stop() }
    }

    private var importRow: some View {
        Button { preview.stop(); dismiss(); onImport() } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(EditorTheme.accent)
                Text("Add Music from Files…").font(EditorTheme.rowLabel).foregroundStyle(.white)
                Spacer()
                Image(systemName: "square.and.arrow.down").font(.system(size: 14)).foregroundStyle(EditorTheme.dimText)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(EditorTheme.accent.opacity(0.14)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 30)).foregroundStyle(EditorTheme.dimText)
            Text("No music yet").font(EditorTheme.rowLabel).foregroundStyle(.white)
            Text("Add a track from Files — it's saved here for reuse.")
                .font(.system(size: 12)).foregroundStyle(EditorTheme.dimText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.6)
            .foregroundStyle(EditorTheme.dimText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(EditorTheme.panelSolid)
    }

    private func isImportedSelected(_ url: URL) -> Bool {
        if case .imported(let selected, _)? = model.recipe.music?.source { return selected == url }
        return false
    }

    /// A track row: tap the row to pick it, tap the leading disc to audition
    /// (play/pause). Bundled tracks also show a mini waveform preview.
    private func trackRow(
        title: String, systemImage: String, selected: Bool,
        trackID: String?, previewURL: URL?, onDelete: (() -> Void)? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isPlaying = previewURL != nil && preview.playingID == previewURL?.absoluteString
        return HStack(spacing: 10) {
            if let previewURL {
                Button {
                    preview.toggle(id: previewURL.absoluteString, url: previewURL)
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(isPlaying ? EditorTheme.accent : .white.opacity(0.85))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Stop preview" : "Preview \(title)")
            } else {
                Image(systemName: systemImage).font(.system(size: 14)).frame(width: 30)
            }

            Button(action: action) {
                HStack(spacing: 10) {
                    Text(title).font(EditorTheme.rowLabel).lineLimit(1)
                        .frame(width: 82, alignment: .leading)
                    if let trackID, let previewURL {
                        MusicRowWaveform(
                            samples: waveforms.samples(for: trackID),
                            active: isPlaying || selected
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .task(id: trackID) { await waveforms.load(id: trackID, url: previewURL) }
                    } else {
                        Spacer(minLength: 0)
                    }
                    if selected { Image(systemName: "checkmark").foregroundStyle(EditorTheme.accent) }
                }
                .foregroundStyle(selected ? .white : EditorTheme.secondaryText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(EditorTheme.timelineDestructive)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(title)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? EditorTheme.activeRow : Color.white.opacity(0.04)))
    }
}

/// Decodes and caches downsampled waveforms for the chooser rows, lazily as
/// each row appears (only visible rows decode). Reuse across scrolls is free.
@MainActor
final class MusicWaveformCache: ObservableObject {
    @Published private var cache: [String: [Float]] = [:]
    private var inFlight: Set<String> = []

    func samples(for id: String) -> [Float] { cache[id] ?? [] }

    func load(id: String, url: URL) async {
        if cache[id] != nil || inFlight.contains(id) { return }
        inFlight.insert(id)
        let samples = await VideoWaveform.samples(from: url, buckets: 56)
        cache[id] = samples
        inFlight.remove(id)
    }
}

/// A compact mirrored-bar waveform for a chooser row.
private struct MusicRowWaveform: View {
    let samples: [Float]
    let active: Bool

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }
            let n = samples.count
            let gap: CGFloat = 1
            let barW = max(1, (size.width - CGFloat(n - 1) * gap) / CGFloat(n))
            let mid = size.height / 2
            let color = active ? EditorTheme.accent : Color.white.opacity(0.32)
            for (i, s) in samples.enumerated() {
                let h = max(1, CGFloat(s) * size.height)
                let x = CGFloat(i) * (barW + gap)
                let rect = CGRect(x: x, y: mid - h / 2, width: barW, height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(color))
            }
        }
    }
}

/// Loops a bundled/imported bed for auditioning in the music chooser. One at a
/// time; `playingID` drives the row's play/pause glyph. Uses a `.playback`
/// session so preview is audible even on the silent switch (user-initiated).
@MainActor
final class MusicPreviewPlayer: ObservableObject {
    @Published private(set) var playingID: String?
    private var player: AVAudioPlayer?

    func toggle(id: String, url: URL) {
        if playingID == id { stop(); return }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.play()
            self.player = player
            playingID = id
        } catch {
            playingID = nil
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    deinit { player?.stop() }
}

/// The preview surface: an `AVPlayerLayer` as the view's backing layer.
struct VideoPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class PlayerHostView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}
