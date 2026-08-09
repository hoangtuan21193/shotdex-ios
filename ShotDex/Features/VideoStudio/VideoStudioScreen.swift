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

/// Full-screen video editor: preview stage on top, a transport/undo control
/// row, the multi-track timeline (ruler, text, effect, filter, clips, audio —
/// fixed centre playhead, scroll to scrub, pinch to zoom), and a contextual
/// bottom toolbar that swaps for detail panels. Single-video mode drops
/// reorder/transitions and adds Rotate.
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
    @State private var isAddingText = false
    @State private var editingOverlay: PhotoOverlay?

    var body: some View {
        ZStack {
            EditorTheme.background.ignoresSafeArea()
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .top) {
            // Cancel / Export flank the dynamic island; no screen title.
            if let model, model.phase == .ready {
                islandBar(model)
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
                overlayFontRecents: dependencies.overlayFontRecents
            )
            newModel.onSaved = { assetID in
                onSaved(assetID)
                dismiss()
            }
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
                VideoExportSheet(model: model)
                    .presentationDetents([.height(280)])
            }
        }
        .sheet(isPresented: $isFontPickerPresented) {
            if let model {
                EditorFontPickerSheet(
                    recents: model.fontRecents,
                    current: model.lastFont
                ) { choice in
                    model.rememberFont(choice)
                    model.updateSelectedOverlay { overlay in
                        overlay.fontPostScriptName = choice.postScriptName
                        overlay.fontFamilyName = choice.familyName
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isMusicImporterPresented,
            allowedContentTypes: [.audio]
        ) { result in
            if case .success(let url) = result {
                model?.importMusic(from: url)
            }
        }
        .fullScreenCover(isPresented: $isAddingText) {
            EditorInlineTextEditor(
                initialText: "",
                tokens: .empty,
                alignment: .center,
                onCommit: { text in
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty, let model {
                        // New captions drop in at the playhead.
                        model.pushUndo()
                        model.addTextOverlay(trimmed, at: model.currentTime)
                    }
                    isAddingText = false
                },
                onCancel: { isAddingText = false }
            )
        }
        .fullScreenCover(item: $editingOverlay) { overlay in
            EditorInlineTextEditor(
                initialText: overlay.text,
                tokens: .empty,
                alignment: overlay.alignment,
                onCommit: { text in
                    model?.updateSelectedOverlay { $0.text = text }
                    editingOverlay = nil
                },
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

    @ViewBuilder
    private func content(_ model: VideoStudioModel) -> some View {
        switch model.phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing clips…")
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.secondaryText)
            }
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(EditorTheme.maskSubtitle)
                    .foregroundStyle(EditorTheme.secondaryText)
                Button("Close") { dismiss() }
            }
        case .ready:
            VStack(spacing: 0) {
                stage(model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controlRow(model)
                VideoTimelineView(model: model, onEditText: { overlay in
                    model.selectedOverlayID = overlay.id
                    editingOverlay = overlay
                })
                VideoBottomArea(
                    model: model,
                    onImportMusic: { isMusicImporterPresented = true },
                    onAddText: { isAddingText = true },
                    onEditText: { overlay in
                        model.selectedOverlayID = overlay.id
                        editingOverlay = overlay
                    },
                    onPickFont: { isFontPickerPresented = true }
                )
            }
        }
    }

    /// Cancel and Export sit at the very top, flanking the dynamic island —
    /// no screen title in between.
    private func islandBar(_ model: VideoStudioModel) -> some View {
        HStack {
            Button("Cancel") {
                if model.hasEdits {
                    isDiscardConfirmationPresented = true
                } else {
                    dismiss()
                }
            }
            .foregroundStyle(EditorTheme.secondaryText)

            Spacer()

            Button("Export") {
                isExportSheetPresented = true
            }
            .fontWeight(.semibold)
            .foregroundStyle(EditorTheme.accent)
            .disabled(isExporting)
        }
        .font(.subheadline)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private func stage(_ model: VideoStudioModel) -> some View {
        ZStack {
            if let player = model.player {
                VideoPlayerLayerView(player: player)
            }
            if !model.isPlaying {
                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .editorGlass(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if model.isPlaying { model.togglePlayback() }
        }
    }

    /// Transport + undo: play/pause, timecodes, undo/redo.
    private func controlRow(_ model: VideoStudioModel) -> some View {
        HStack(spacing: 8) {
            Button {
                model.togglePlayback()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .editorGlass(Circle())
            }
            .buttonStyle(.plain)

            Text("\(timeText(model.currentTime)) / \(timeText(model.totalDuration))")
                .font(EditorTheme.rowValue)
                .foregroundStyle(EditorTheme.secondaryText)

            Spacer()

            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.canUndo ? .white : EditorTheme.dimText)
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!model.canUndo)

            Button {
                model.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.canRedo ? .white : EditorTheme.dimText)
                    .frame(width: 32, height: 30)
            }
            .buttonStyle(.plain)
            .disabled(!model.canRedo)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    private func timeText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// The preview surface: an `AVPlayerLayer` as the view's backing layer, so
/// resizes are free and playback never re-parents.
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
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}
