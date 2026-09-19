import AVFoundation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers
import ShotDexKit

/// Immutable payload for presenting the Video Studio (see
/// `CompressionPresentation` for why assets live inside the item).
struct VideoStudioPresentation: Identifiable {
    let id = UUID()
    /// Pick order; photos and videos mixed.
    let assets: [PHAsset]
    let mode: VideoStudioMode
}

/// Full-screen video editor: a floating command band over the Dynamic Island
/// (undo/redo, timecode, back, export), the preview, the multi-lane timeline
/// with a fixed centre playhead, and a tool row. Editing controls live in one
/// contextual bottom sheet that reskins for whatever is selected.
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
    @State private var musicChooserIntent: MusicChooserIntent?
    @State private var isStickerPickerPresented = false
    @State private var mediaPickerMode: MediaPickerMode?
    @State private var editingOverlay: PhotoOverlay?
    /// The caption just created by Add Text — cancelling its first edit removes
    /// it again instead of leaving an empty layer behind.
    @State private var newOverlayID: UUID?
    @State private var stickerImages: [UUID: CGImage] = [:]
    /// How much taller than its lanes the user has dragged the timeline.
    /// Persisted: a divider the app forgets is a divider the user has to set
    /// again every time they open a project.
    @AppStorage(SettingsKeys.videoTimelineExtraHeight) private var timelineExtraHeight = 0.0
    /// The drag in progress, added to the stored value while a finger is down.
    @State private var timelineDragOffset: CGFloat = 0
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
            if let editingOverlay {
                inlineTextEditor(editingOverlay)
            }
        }
        .animation(EditorTheme.animation, value: editingOverlay == nil)
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
        .alert("Discard this video?", isPresented: $isDiscardConfirmationPresented) {
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
        .sheet(item: $musicChooserIntent) { intent in
            if let model {
                VideoMusicChooserSheet(
                    model: model,
                    intent: intent,
                    importedMusic: importedMusic,
                    onImport: { isMusicImporterPresented = true }
                )
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
                // Persist for reuse in later sessions, then add it as a track.
                let track = try importedMusic.add(from: url)
                model.addMusicTrack(source: .imported(url: track.url, displayName: track.displayName))
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }

    /// The caption editor, laid over the studio the way the photo editor's is —
    /// the frame dims behind the words instead of a black cover. No token bar: a
    /// video project has no EXIF for the tokens to expand to.
    @ViewBuilder
    private func inlineTextEditor(_ overlay: PhotoOverlay) -> some View {
        EditorInlineTextEditor(
            initialText: overlay.text,
            tokens: .empty,
            showsTokens: false,
            alignment: overlay.alignment,
            onCommit: { text in finishTextEditing(overlay, text: text) },
            onCancel: { finishTextEditing(overlay, text: nil) }
        )
        .transition(.opacity)
    }

    /// Adds a caption and drops straight into the keyboard — an overlay reading
    /// "Text" is never the goal.
    private func addTextOverlay(_ model: VideoStudioModel) {
        let overlay = model.addTextOverlay("", at: model.currentTime)
        newOverlayID = overlay.id
        editingOverlay = overlay
    }

    /// Commits (or abandons) the inline editor. A caption that never got any
    /// text is removed rather than left as an invisible empty layer.
    private func finishTextEditing(_ overlay: PhotoOverlay, text: String?) {
        defer { editingOverlay = nil; newOverlayID = nil }
        guard let model else { return }
        if let text {
            model.updateSelectedOverlay { $0.text = text }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.deleteSelectedOverlay()
            }
        } else if newOverlayID == overlay.id {
            model.deleteSelectedOverlay()
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
            let usesRail = proxy.size.width >= EditorLayoutMetrics.sidebarMinCanvasWidth
            let bandHeight = VideoStudioMetrics.topBandHeight(
                usesToolRail: usesRail,
                safeAreaTop: proxy.safeAreaInsets.top
            )
            let panelHeight = VideoStudioMetrics.sheetHeight + proxy.safeAreaInsets.bottom
            // The preview takes its aspect-fit height and the timeline the rest, so
            // a landscape project gets a tall timeline instead of black bars. While
            // the panel is up the stack lifts by the panel's overlap, so the lanes
            // stay visible above it.
            // The reader sits inside the safe area while the stack below ignores it,
            // so the stack's real height is the reader's plus both insets.
            let usesToolRail = usesRail
            // Beside the stage on a wide window, under the timeline on a tall
            // one. Both spend the dimension the stage has to spare.
            let usesInspectorColumn = VideoStudioMetrics.usesInspectorColumn(size: proxy.size)
            let lanes = VideoStudioMetrics.Lanes.for(size: proxy.size)
            let layout = VideoStudioMetrics.stackLayout(
                screen: CGSize(
                    // The preview is drawn in the column beside the rail, not
                    // across the window, so the aspect-fit height has to be
                    // computed from the width it actually gets.
                    width: proxy.size.width
                        - (usesToolRail ? VideoStudioMetrics.railWidth : 0)
                        - (usesInspectorColumn ? VideoStudioMetrics.inspectorColumnWidth : 0),
                    height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                ),
                bandHeight: bandHeight,
                bottomInset: proxy.safeAreaInsets.bottom,
                canvas: model.recipe.canvasSize(),
                // With the inspector in a column the stack never has to move
                // for it, whatever is selected.
                presentsSheet: model.presentsSheet && !usesInspectorColumn,
                // The timeline takes what its lanes need and no more, on every
                // width. Handing it the whole leftover drew three lanes at the
                // top of a 330pt black field on the phone too — the surplus
                // belongs around the frame being edited, which is what black
                // around a preview is for, not under the tracks.
                timelineContentHeight: lanes.timelineContentHeight(
                    overlayLanes: max(1, model.overlayLaneCount),
                    musicLanes: max(1, model.musicLaneCount)
                ),
                usesToolRail: usesToolRail,
                // The column never covers anything, so there is nothing for
                // the stack to dock or lift out of the way of.
                panelMayDock: usesToolRail && !usesInspectorColumn,
                // Back, the read-out and Export move into the top band there,
                // so the bottom band is not drawn and costs no height.
                showsBottomBar: !usesToolRail,
                // Only where the divider exists to drag.
                timelineExtraHeight: usesToolRail ? CGFloat(timelineExtraHeight) + timelineDragOffset : 0
            )
            // `usesRail` is measured on the window, not on the size class. An
            // iPad Split View half reports `.regular` at ~500pt, where a
            // permanent 92pt rail costs a fifth of the width to save 62pt of
            // height — the wrong trade, and the exact mistake the editor's
            // sidebar avoids by using a 700pt threshold instead.
            ZStack(alignment: .bottom) {
                HStack(spacing: 0) {
                    // Regular width puts the tools down the leading edge: the
                    // row across the bottom spends 62pt of height — the thing
                    // a timeline editor is short of — to show nine cells in a
                    // bar that is 1032pt wide.
                    if usesRail {
                        VideoStudioToolRail(
                            model: model,
                            actions: actions(model),
                            topInset: bandHeight,
                            bottomInset: proxy.safeAreaInsets.bottom
                        )
                    }
                    VStack(spacing: 0) {
                        VideoStudioTopBand(
                            model: model,
                            projectActions: usesRail ? actions(model) : nil
                        )
                        .frame(height: bandHeight, alignment: .top)
                        preview(model).frame(height: layout.preview)
                        if usesRail {
                            timelineDivider
                        } else {
                            Color.clear.frame(height: VideoStudioMetrics.previewTimelineGap)
                        }
                        VideoTimelineView(
                            model: model,
                            height: layout.timeline,
                            onAddOverlay: { addTextOverlay(model) },
                            onAddMusic: { musicChooserIntent = .add },
                            onAddMedia: { mediaPickerMode = .add },
                            onEditText: { editingOverlay = $0 },
                            onTransition: { model.editingTransitionIndex = $0 }
                        )
                        // Sits under the panel; keeps the timeline above it.
                        Color.clear.frame(height: layout.lift)
                        // Where the window has height to spare the panel takes
                        // a place in the stack instead of sliding over the
                        // bars: it covers nothing, the timeline does not move,
                        // and the black that was padding the frame is spent on
                        // the controls for the thing that is selected.
                        if layout.dockedPanel > 0 {
                            contextPanel(model, height: layout.dockedPanel)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if !usesRail {
                            VideoStudioToolbar(model: model, actions: actions(model))
                        }
                        if !usesRail {
                            VideoStudioBottomBar(model: model, actions: actions(model))
                        }
                        Color.clear.frame(height: proxy.safeAreaInsets.bottom)
                    }

                    if usesInspectorColumn {
                        VideoStudioSheetHost(model: model, actions: actions(model), layout: .column)
                            .frame(width: VideoStudioMetrics.inspectorColumnWidth)
                            .padding(.top, bandHeight)
                            .padding(.bottom, proxy.safeAreaInsets.bottom)
                            .overlay(alignment: .leading) {
                                Rectangle().fill(EditorTheme.panelDivider).frame(width: 1)
                            }
                    }
                }

                // The panel slides over the bars; the layout underneath never
                // moves, so the timeline stays exactly where the user left it.
                if model.presentsSheet, layout.dockedPanel == 0, !usesInspectorColumn {
                    contextPanel(model, height: panelHeight)
                        .transition(.move(edge: .bottom))
                        // The rail is the one piece of chrome that must stay
                        // reachable while the panel is up — a tool row you
                        // cannot reach without dismissing the panel is a tool
                        // row that costs a tap for nothing. The panel starts
                        // where the rail ends.
                        .padding(.leading, usesRail ? VideoStudioMetrics.railWidth : 0)
                }
            }
            .background { keyboardShortcuts(model) }
            .environment(\.videoLaneMetrics, lanes)
            .animation(EditorTheme.animation, value: model.presentsSheet)
            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
    }

    /// The bindings every NLE has, for an iPad with a keyboard attached.
    ///
    /// Zero-size buttons in a background, the same shape the photo editor
    /// uses: a shortcut on a visible control only fires while that control is
    /// in the hierarchy, and half of these have no visible control at all.
    private func keyboardShortcuts(_ model: VideoStudioModel) -> some View {
        ZStack {
            Button("Play or Pause") { model.togglePlayback() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Back a Second") { model.seek(to: model.currentTime - 1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Forward a Second") { model.seek(to: model.currentTime + 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Back a Frame") { model.seek(to: model.currentTime - 1.0 / 30) }
                .keyboardShortcut(.leftArrow, modifiers: .shift)
            Button("Forward a Frame") { model.seek(to: model.currentTime + 1.0 / 30) }
                .keyboardShortcut(.rightArrow, modifiers: .shift)
            Button("Start") { model.seek(to: 0) }
                .keyboardShortcut(.home, modifiers: [])
            Button("End") { model.seek(to: model.totalDuration) }
                .keyboardShortcut(.end, modifiers: [])
            Button("Undo") { model.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
            Button("Redo") { model.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
            Button("Split") { model.splitClipUnderPlayhead() }
                .keyboardShortcut("b", modifiers: .command)
            // The sheet, not the export: ⌘E should put the user where the
            // Export button does, not start writing to their library.
            Button("Export") { isExportSheetPresented = true }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(model.exportState != .idle)
            Button("Deselect") { model.clearSelection() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!model.presentsSheet)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    /// Drag to trade preview height for timeline height. The app's own answer
    /// is that the surplus belongs around the frame (spec §7.9); this is how
    /// the user says otherwise, and Final Cut for iPad publishes the same
    /// handle at the top of its timeline.
    private var timelineDivider: some View {
        Capsule()
            .fill(EditorTheme.panelDivider)
            .frame(width: 44, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: VideoStudioMetrics.previewTimelineGap + 12)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    // Up is a taller timeline, so the sign flips.
                    .onChanged { timelineDragOffset = -$0.translation.height }
                    .onEnded { value in
                        let range = VideoStudioMetrics.timelineExtraRange
                        timelineExtraHeight = Double(
                            min(max(range.lowerBound, CGFloat(timelineExtraHeight) - value.translation.height), range.upperBound)
                        )
                        timelineDragOffset = 0
                    }
            )
            .accessibilityLabel("Timeline height")
            .accessibilityHint("Drag up for a taller timeline, down for a bigger preview")
            .accessibilityAdjustableAction { direction in
                let range = VideoStudioMetrics.timelineExtraRange
                let step: CGFloat = 40
                let next = CGFloat(timelineExtraHeight) + (direction == .increment ? step : -step)
                timelineExtraHeight = Double(min(max(range.lowerBound, next), range.upperBound))
            }
    }

    /// The contextual editing panel. It looks and behaves like a bottom sheet —
    /// grabber, rounded top, drag down to dismiss — but is drawn in-screen rather
    /// than presented: the studio's pickers (font, media, music, sticker) are
    /// system sheets fired from here, and UIKit cannot present a sheet from a view
    /// that is already presenting one. It slides *over* the tool row and the
    /// bottom bar; nothing underneath is displaced.
    private func contextPanel(_ model: VideoStudioModel, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.22))
                .frame(width: 36, height: 5)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onEnded { if $0.translation.height > 40 { model.clearSelection() } }
                )
            VideoStudioSheetHost(model: model, actions: actions(model))
        }
        .frame(height: height, alignment: .top)
        .background(EditorTheme.panelSolid)
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: AppTheme.Radius.lg, topTrailing: AppTheme.Radius.lg),
            style: .continuous
        ))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(
                cornerRadii: .init(topLeading: AppTheme.Radius.lg, topTrailing: AppTheme.Radius.lg),
                style: .continuous
            )
            .strokeBorder(EditorTheme.panelTopHairline, lineWidth: 1)
        }
        // Reads as a layer above the timeline rather than part of the stack.
        .shadow(color: .black.opacity(0.45), radius: 14, y: -2)
    }

    private func actions(_ model: VideoStudioModel) -> VideoInspectorActions {
        VideoInspectorActions(
            onExport: { isExportSheetPresented = true },
            onBack: { if model.hasEdits { isDiscardConfirmationPresented = true } else { dismiss() } },
            onAddMedia: { mediaPickerMode = .add },
            onReplaceClip: { mediaPickerMode = .replace },
            onAddText: { addTextOverlay(model) },
            onAddSticker: { isStickerPickerPresented = true },
            onAddMusic: { musicChooserIntent = .add },
            onReplaceMusic: { musicChooserIntent = .replace($0) },
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
            // Text and sticker overlays, drawn and manipulated live on top of the
            // player (the preview composition does not bake them). `contentRect` is
            // the aspect-fitted video rect the overlays' normalized centres map into.
            GeometryReader { geo in
                let contentRect = VideoGeometry.stillFitRect(
                    imageSize: model.recipe.canvasSize(),
                    renderSize: geo.size
                )
                // The frame's own edge. The compositor letterboxes a clip onto
                // the project's background — black by default — and the stage
                // behind it is black too, so without this line a 3:2 photo in
                // a 16:9 project looks like a 3:2 project: the user cannot see
                // the frame they are exporting, only the part of it the photo
                // happens to fill.
                Rectangle()
                    .strokeBorder(EditorTheme.hairline, lineWidth: 1)
                    .frame(width: contentRect.width, height: contentRect.height)
                    .position(x: contentRect.midX, y: contentRect.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                VideoOverlayCanvas(
                    model: model,
                    contentRect: contentRect,
                    images: stickerImages
                )
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
        // Paused, with a sheet up: a tap on the stage outside the video is the
        // obvious "done with this" — it closes the sheet. (A tap *inside* the video
        // is handled by the overlay canvas, which deselects the same way.)
        .onTapGesture {
            if model.isPlaying {
                model.togglePlayback()
            } else if model.presentsSheet {
                withAnimation(EditorTheme.animation) { model.clearSelection() }
            }
        }
        .onAppear { loadStickerImages(model) }
        .onChange(of: model.recipe.overlays) { loadStickerImages(model) }
    }

    /// Decode the sticker PNGs the preview proxy draws — off the render path, keyed
    /// by `imageID`, refreshed whenever the overlay set changes.
    private func loadStickerImages(_ model: VideoStudioModel) {
        var map: [UUID: CGImage] = [:]
        for timed in model.recipe.overlays {
            guard timed.overlay.kind == .image, let id = timed.overlay.imageID else { continue }
            if let existing = stickerImages[id] { map[id] = existing; continue }
            guard let data = try? Data(contentsOf: model.overlayImages.url(for: id)),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { continue }
            map[id] = image
        }
        stickerImages = map
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
            // A Cancel here is not a nicety: `fullScreenCover` has no swipe to
            // dismiss, and one clip whose original is still in iCloud can hold
            // this state for minutes. Without it the only way off the screen
            // is to kill the app.
            VStack(spacing: 12) {
                ProgressView()
                Text("Preparing clips…").font(EditorTheme.maskSubtitle).foregroundStyle(EditorTheme.secondaryText)
                Button("Cancel") { dismiss() }
                    .font(EditorTheme.maskSubtitle)
                    .padding(.top, AppTheme.Spacing.xs)
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

/// Whether the music chooser adds a new bed or swaps the audio behind one that
/// is already on the timeline.
enum MusicChooserIntent: Identifiable {
    case add
    case replace(UUID)

    var id: String {
        switch self {
        case .add: "add"
        case .replace(let id): id.uuidString
        }
    }
}

/// The picker for choosing which bed to add (or what to swap an existing bed
/// for). Music itself is multi-track, so this never "deselects" — removing a
/// bed is the timeline's job.
struct VideoMusicChooserSheet: View {
    @Bindable var model: VideoStudioModel
    let intent: MusicChooserIntent
    @ObservedObject var importedMusic: ImportedMusicStore
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preview = MusicPreviewPlayer()
    @StateObject private var waveforms = MusicWaveformCache()
    /// A track the user asked to delete while it is on the timeline.
    @State private var trackPendingDeletion: ImportedMusicTrack?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Music").font(EditorTheme.panelTitle).foregroundStyle(.white).padding(.top, 20)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    // Add-your-own sits at the top (accent), then the user's
                    // reusable imports. No bundled beds.
                    importRow

                    if importedMusic.tracks.isEmpty {
                        emptyState
                    } else {
                        Section {
                            ForEach(importedMusic.tracks) { track in
                                trackRow(
                                    title: track.displayName, systemImage: "music.note",
                                    selected: isInUse(track.url), trackID: track.id, previewURL: track.url,
                                    onDelete: {
                                        preview.stop()
                                        // Deleting the file under a bed that
                                        // is already on the timeline leaves
                                        // the bed drawn but silent, in the
                                        // preview and in the export. Ask.
                                        if isInUse(track.url) {
                                            trackPendingDeletion = track
                                        } else {
                                            importedMusic.delete(track)
                                        }
                                    }
                                ) {
                                    preview.stop()
                                    let source = MusicSource.imported(url: track.url, displayName: track.displayName)
                                    switch intent {
                                    case .add: model.addMusicTrack(source: source)
                                    case .replace(let id): model.replaceMusicTrack(id, source: source)
                                    }
                                    dismiss()
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

    /// Whether any bed on the timeline already plays this file — a checkmark,
    /// not an exclusive selection (the same file can be used more than once).
    private func isInUse(_ url: URL) -> Bool {
        model.recipe.musicTracks.contains { music in
            if case .imported(let used, _) = music.source { return used == url }
            return false
        }
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
