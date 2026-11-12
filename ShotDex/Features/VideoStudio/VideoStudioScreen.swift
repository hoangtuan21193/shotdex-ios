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

/// Server photos opening the Video Studio (FS-17.06 §5b).
struct ServerVideoStudioLaunch {
    let photos: [FetchedServerPhoto]
    let export: ServerExportContext
}

/// Full-screen video editor: a floating command band over the Dynamic Island
/// (undo/redo, timecode, back, export), the preview, the multi-lane timeline
/// with a fixed centre playhead, and a tool row. Editing controls live in one
/// contextual bottom sheet that reskins for whatever is selected.
struct VideoStudioScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppDependencies.self) var dependencies

    let assets: [PHAsset]
    let mode: VideoStudioMode
    var onSaved: (String) -> Void
    /// Reopening a video from Creations: its stored recipe comes back in place
    /// of a fresh project, and exporting updates that same row.
    var restoring: Creation?
    /// A project of server photos: Export hands the file to the export sheet.
    var server: ServerVideoStudioLaunch?

    @State private var model: VideoStudioModel?
    @State private var isDiscardConfirmationPresented = false
    /// Back found the draft would not write (FS-12.18 §6): the one time
    /// Back asks anything, because closing quietly would lose the session.
    @State private var isDraftSaveFailurePresented = false
    @State var isExportSheetPresented = false
    @State var isMusicImporterPresented = false
    @State private var isFontPickerPresented = false
    @State private var musicChooserIntent: MusicChooserIntent?
    @State var isStickerPickerPresented = false
    /// The layout drawn last, for the commands that differ by window — Add
    /// Media opens the pool on an iPad in landscape and the Media panel
    /// everywhere else.
    @State var currentWindowClass: VideoStudioWindowClass?
    /// The menu bar's way to this studio (FS-12.17b §4) — one object, so
    /// the scene's focused value does not change with every render.
    @State var keyboardTarget = VideoStudioKeyboardTarget()
    /// Whether something is being typed in — the bare keys go quiet
    /// (FS-12.17b §3).
    @State var textInputMonitor = VideoTextInputMonitor()

    /// One of the screen's own sheets or alerts is up: every key is silent
    /// (FS-12.17b §3). Panels report theirs through `nestedModalCount`.
    var presentsModal: Bool {
        isDiscardConfirmationPresented || isDraftSaveFailurePresented || isExportSheetPresented
            || isMusicImporterPresented || isFontPickerPresented || musicChooserIntent != nil
            || isStickerPickerPresented
    }
    @State var editingOverlay: PhotoOverlay?
    /// The preview's size, for the export preset's Fit preview (FS-12.16 §4).
    @State var previewSize: CGSize = .zero
    /// A caption cue in the full-screen editor (FS-12.14 §5, Expand Text Field).
    @State var editingCaptionID: UUID?
    @State private var stickerImages: [UUID: CGImage] = [:]
    /// How much taller than its lanes the user has dragged the timeline.
    ///
    /// Persisted, but read once into scene-local state rather than bound with
    /// `@AppStorage`: a live binding pushes every change to every observer,
    /// so on an iPad with two windows open dragging one window's divider
    /// resized the other window's timeline under a user who was not touching
    /// it. It is written back when the drag ends, so the next window to open
    /// still starts where the last one left it.
    @State var timelineExtraHeight = UserDefaults.standard.double(
        forKey: SettingsKeys.videoTimelineExtraHeight
    )
    /// The drag in progress, added to the stored value while a finger is down.
    @State var timelineDragOffset: CGFloat = 0
    @StateObject var importedMusic = ImportedMusicStore()
    /// The wide layouts' side columns and Quick Adjust strip: session
    /// state the window class does not own, so rotating or folding keeps it.
    @State var columns = VideoDeskColumns()
    /// Seconds the timeline viewport is showing, reported up by the timeline
    /// so the project-overview strip can draw the window it stands for.
    @State var timelineVisibleDuration: Double = 0
    @State var levelMeter = VideoLevelMeterModel()
    /// The window's trailing inset as the window reports it — the Duo
    /// cover's 84pt rail, which a reader inside the safe area cannot see on
    /// a screen that runs past the top and bottom insets. Nil until the
    /// first report (FS-12.07b §1).
    @State var windowTrailingInset: CGFloat?

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
            if let model, let id = editingCaptionID, let cue = model.recipe.captions?.cues.first(where: { $0.id == id }) {
                EditorInlineTextEditor(
                    initialText: cue.text,
                    tokens: .empty,
                    showsTokens: false,
                    alignment: .center,
                    onCommit: { text in
                        model.pushUndo()
                        model.setCaptionText(text, for: id)
                        editingCaptionID = nil
                    },
                    onCancel: { editingCaptionID = nil }
                )
                .transition(.opacity)
            }
            if let model, model.mediaDrag != nil {
                VideoMediaDragOverlay(model: model)
            }
        }
        // FS-12.18 §6: a draft that would not write says so and offers the
        // write again; nothing blocks, the project in memory is all there.
        .overlay(alignment: .top) {
            if let model, model.hasFailedDraftSave {
                ActionToast(text: VideoStudioCopy.draftSaveFailed, actionTitle: VideoStudioCopy.tryAgain, dark: true) {
                    model.retryDraftSave()
                }
                .padding(.top, AppTheme.Spacing.sm)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(AppTheme.Motion.standard, value: model?.hasFailedDraftSave == true)
        // FS-12.04 §7: clips still in iCloud stay as gaps; a quiet line
        // says why they are dark instead of the clips vanishing.
        .overlay(alignment: .top) {
            if let model, model.phase == .ready, !model.hasFailedDraftSave, !model.unavailableClipIDs.isEmpty {
                ActionToast(text: VideoStudioCopy.clipsWaitingForICloud(model.unavailableClipIDs.count), dark: true)
                    .padding(.top, AppTheme.Spacing.sm)
                    .allowsHitTesting(false)
            }
        }
        .animation(EditorTheme.animation, value: editingOverlay == nil)
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .task {
            guard model == nil else { return }
            // Originals only in iCloud come down through the app's fetcher
            // (the scripted one under -ShotDexFakeICloud).
            dependencies.videoStudio.originalFetcher = dependencies.originalFetcher
            let newModel = VideoStudioModel(
                photos: server.map { $0.photos.map(PhotoEditOrigin.serverFile) } ?? assets.map(PhotoEditOrigin.asset),
                mode: mode,
                service: dependencies.videoStudio,
                photoLibrary: dependencies.photoLibrary,
                overlayFontRecents: dependencies.overlayFontRecents,
                overlayImages: dependencies.overlayImages,
                creationStore: server == nil ? dependencies.creations : nil,
                restoring: restoring,
                serverWorkDirectory: server?.export.workDirectory
            )
            newModel.onSaved = { assetID in onSaved(assetID); dismiss() }
            newModel.presetName = { [looks = dependencies.lookPresets] in looks.displayName(of: $0) }
            model = newModel
            textInputMonitor.start { [weak newModel] typing in newModel?.isTypingText = typing }
            await newModel.load()
        }
        .onDisappear {
            textInputMonitor.stop()
            model?.close()
            levelMeter.cancelDecoding()
        }
        // The scene leaving the foreground, or the window changing class —
        // the Duo folding from its inner display to the cover, or opening
        // — writes the draft at once (FS-12.18 §2).
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model?.sceneDidChange() }
        }
        .interactiveDismissDisabled(model?.hasEdits == true || isExporting)
        // Only a project of server photos asks (FS-17.06 §5): it has no
        // draft. Every other project saved itself on the way out.
        .alert(VideoStudioCopy.draftSaveFailed, isPresented: $isDraftSaveFailurePresented) {
            // The cancel role, so the system adds no third "Cancel": the
            // two answers are the whole question (FS-12.18 §6).
            Button(VideoStudioCopy.tryAgain, role: .cancel) { if let model { leave(model) } }
            Button(VideoStudioCopy.leaveWithoutSaving, role: .destructive) { dismiss() }
        }
        .alert("Discard this video?", isPresented: $isDiscardConfirmationPresented) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        }
        .sheet(isPresented: Binding(
            get: { model?.editingTransitionIndex != nil },
            set: { if !$0 { model?.editingTransitionIndex = nil } }
        )) {
            if let model, let index = model.editingTransitionIndex {
                VideoTransitionSheet(model: model, index: index) {
                    model.editingTransitionIndex = nil
                }
                .presentationDetents([.height(300)])
            }
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
        // iPad: Export Video is a sheet (FS-12.16 §5); everywhere else it
        // is the studio's own panel.
        .sheet(isPresented: $isExportSheetPresented) {
            if let model {
                VideoExportPanel(
                    model: model, server: server, onServerExported: serverExported,
                    onClose: { isExportSheetPresented = false }
                )
                .environment(\.videoMediaGrid, .pool)
                .interactiveDismissDisabled(model.isExportBusy)
                .preferredColorScheme(.dark)
                .modifier(VideoExportSheetSizing(isExporting: model.isExportBusy))
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

    /// Text (FS-12.04 §3): a "Text" block at the playhead, selected, with
    /// Edit open — the keyboard is up in the panel. The full-screen editor
    /// is the field's expand button.
    func addTextOverlay(_ model: VideoStudioModel, font: OverlayFontChoice? = nil) {
        model.addTextBlock(font: font)
    }

    /// Commits (or abandons) the full-screen editor. A caption emptied
    /// there is deleted — one undo step — rather than left as an invisible
    /// empty layer.
    private func finishTextEditing(_ overlay: PhotoOverlay, text: String?) {
        defer { editingOverlay = nil }
        guard let model, let text else { return }
        model.updateSelectedOverlay { $0.text = text }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.deleteSelectedOverlay()
        }
    }

    /// Back: the model keeps the selection, writes the draft and says
    /// whether the studio may close.
    func leave(_ model: VideoStudioModel) {
        Task { @MainActor in
            switch await model.back() {
            case .close: dismiss()
            case .confirmDiscard: isDiscardConfirmationPresented = true
            case .saveFailed: isDraftSaveFailurePresented = true
            }
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

    /// Picks the layout by the window (FS-12.03 §1): its size and its
    /// trailing inset, never the device's name. A compact window waits for
    /// its inset before it draws anything, so the Duo's cover never flashes
    /// the phone layout on its way to the rail.
    private func content(_ model: VideoStudioModel) -> some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let window = VideoStudioWindowClass.windowSize(
                content: proxy.size,
                top: insets.top,
                bottom: insets.bottom,
                leading: insets.leading,
                trailing: insets.trailing
            )
            let knownInset = windowTrailingInset.map { max($0, insets.trailing) }
                ?? (insets.trailing > 0 ? insets.trailing : nil)
            #if DEBUG
            // A window class drawn at its own size in the corner of a bigger
            // one — the Duo's inner display, which the simulator boots
            // folded and cannot open from the command line. Debug builds
            // only; the proof is still the device's.
            if let stand = Self.debugStandInWindow {
                layout(model, proxy: proxy, window: stand.size, windowClass: stand.windowClass)
                    .frame(width: stand.size.width, height: stand.size.height, alignment: .topLeading)
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea()
            } else if let windowClass = VideoStudioWindowClass.resolve(window: window, knownTrailingInset: knownInset) {
                layout(model, proxy: proxy, window: window, windowClass: windowClass)
                    .onChange(of: windowClass) { _, _ in model.sceneDidChange() }
            } else {
                Color.clear
            }
            #else
            if let windowClass = VideoStudioWindowClass.resolve(window: window, knownTrailingInset: knownInset) {
                layout(model, proxy: proxy, window: window, windowClass: windowClass)
                    // A new class is a new scene shape — the Duo folding or
                    // opening, a Stage Manager window crossing a line: the
                    // draft is written at once (FS-12.18 §2).
                    .onChange(of: windowClass) { _, _ in model.sceneDidChange() }
            } else {
                Color.clear
            }
            #endif
        }
        .background {
            EditorWindowInsetsReader { insets in
                if windowTrailingInset != insets.right { windowTrailingInset = insets.right }
            }
        }
        // A selection on a wide window opens a shut inspector: its foot
        // carries ✕ · ✓ (FS-12.03 §5).
        .onChange(of: model.presentsSheet) { old, new in
            columns.presentsSheetChanged(from: old, to: new)
        }
    }

    #if DEBUG
    /// `-VideoStudioStandIn duoInner` draws the Duo inner layout at 951×669
    /// in the top-left corner of whatever window the studio is in;
    /// `duoCover` the cover's 466×678.
    static var debugStandInWindow: (windowClass: VideoStudioWindowClass, size: CGSize)? {
        switch UserDefaults.standard.string(forKey: "VideoStudioStandIn") {
        case "duoInner": (.duoInner, CGSize(width: 951, height: 669))
        case "duoCover": (.duoCover, CGSize(width: 466, height: 678))
        default: nil
        }
    }
    #endif

    /// One body per window class (FS-12.03 §1). The phone's stack stays
    /// with the phone plan; every other class places its bands from
    /// `VideoStudioDeskGeometry`.
    @ViewBuilder
    private func layout(
        _ model: VideoStudioModel,
        proxy: GeometryProxy,
        window: CGSize,
        windowClass: VideoStudioWindowClass
    ) -> some View {
        Group {
        switch windowClass {
        case .iPadLandscape:
            deskLandscape(model, window: window)
        case .iPadPortrait:
            deskPortrait(model, window: window)
        case .duoInner:
            duoInner(model, window: window)
        case .duoCover:
            duoCover(model, window: window)
        case .phone:
            phoneBody(model, proxy: proxy)
        }
        }
        .environment(\.videoMediaGrid, VideoMediaGridMetrics.for(windowClass))
        .environment(\.videoLookPanelStyle, VideoLookPanelStyle.for(windowClass))
        .environment(\.videoStudioWindowClass, windowClass)
        .overlay {
            // The Duo's inner display: the keyboard's list as a card over
            // the studio (FS-12.17b §4, board F6_DI_Keyboard).
            if windowClass == .duoInner, model.isShortcutListShown {
                VideoShortcutListOverlay(model: model)
            }
        }
        .onAppear {
            currentWindowClass = windowClass
            model.shortcutListIsOverlay = windowClass == .duoInner
        }
        .onChange(of: windowClass) { _, new in
            currentWindowClass = new
            model.shortcutListIsOverlay = new == .duoInner
        }
        .onChange(of: model.compare?.mode) { old, new in
            guard windowClass == .iPadLandscape || windowClass == .iPadPortrait else { return }
            columns.compareModeChanged(from: old, to: new)
        }
    }

    /// Export: Export Video opens and nothing is exported yet (FS-12.10b
    /// §2) — a sheet on an iPad, the studio's panel everywhere else.
    func openExport(_ model: VideoStudioModel) {
        switch currentWindowClass {
        case .iPadLandscape, .iPadPortrait:
            isExportSheetPresented = true
        case .duoInner, .duoCover:
            model.duoExportTapped()
        default:
            // A second tap closes it, keeping the choice (FS-12.16 §5);
            // opening never exports.
            if model.activeToolPanel != .export {
                model.showToolPanel(.export)
            } else if !model.isExportBusy {
                model.showToolPanel(nil)
            }
        }
    }

    /// A server run's file has reached every destination: the studio closes.
    func serverExported() {
        server?.export.onExported()
        isExportSheetPresented = false
        dismiss()
    }

    /// Add Media: the pool's Media tab on an iPad in landscape, where the
    /// library stands beside the stage; the Media panel everywhere else
    /// (FS-12.09 §3).
    func addMedia(_ model: VideoStudioModel) {
        if currentWindowClass == .iPadLandscape {
            columns.isPoolOpen = true
        } else {
            model.toggleToolPanel(.media)
        }
    }

    /// The phone (FS-12.07): the top band over the Dynamic Island, the
    /// frame, the compact transport, the timeline and the tool row, as one
    /// stack whose heights `VideoStudioMetrics.stackLayout` decides. The
    /// panel slides over the bars. This body belongs to the phone plan;
    /// every other window class has its own in `VideoStudioScreen+Desk`.
    private func phoneBody(_ model: VideoStudioModel, proxy: GeometryProxy) -> some View {
        // The band spans the Dynamic Island: it grows to the device's top
        // safe inset so its row lands level with the island.
        let bandHeight = VideoStudioMetrics.topBandHeight(
            usesToolRail: false,
            safeAreaTop: proxy.safeAreaInsets.top
        )
        // A selected item swaps the tool row for ✕ · name · ✓ (FS-12.04
        // §5). The panel carries it at its foot, in the row's place, so it
        // stands a row taller.
        let showsSessionFooter = model.sessionFooterTitle != nil
        // The Look tool's panel stands over the tool row (FS-12.06c §3).
        // So does the keyboard's list (FS-12.17b §4, board F6_P_Keyboard).
        // So does the Text panel (FS-12.04 §4, board TX_P_TextPanel): the
        // five tools stay, Text lit.
        let showsTextTool = model.inspectorTarget == .none && model.activeToolPanel == .text
        let showsLookTool = (model.inspectorTarget == .none && model.activeToolPanel == .look) || model.isShortcutListInPanel || showsTextTool
        // A clip's Look block stands 340 too, over its ✕ · name · ✓ footer
        // (board F5_P_ClipLook).
        let showsClipLook = (model.inspectorTarget == .clip || model.inspectorTarget == .clips) && model.activeItemCommand == .look
        // A multi-select group (FS-12.11 §3, board F1_P_MultiSelect): a 260
        // panel slides over the lower lanes and nothing lifts — the timeline
        // keeps its whole height, so the clips above the panel can still be
        // tapped into the group.
        let showsGroup = model.inspectorTarget == .clips && !showsClipLook
        let contentHeight = showsLookTool || showsClipLook
            ? VideoStudioMetrics.lookSheetHeight
            : (showsGroup ? VideoStudioMetrics.groupSheetHeight : VideoStudioMetrics.sheetHeight)
        let panelHeight = showsLookTool
            ? VideoStudioMetrics.lookSheetHeight
            : contentHeight + proxy.safeAreaInsets.bottom
                + (showsSessionFooter ? VideoStudioMetrics.toolbarHeight : 0)
        let lanes = VideoStudioMetrics.Lanes.for(.phone)
        // The reader sits inside the safe area while the stack below ignores
        // it, so the stack's real height is the reader's plus both insets.
        let screen = CGSize(
            width: proxy.size.width,
            height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
        )
        let idleLayout = VideoStudioMetrics.stackLayout(
            screen: screen,
            bandHeight: bandHeight,
            bottomInset: proxy.safeAreaInsets.bottom,
            canvas: model.recipe.canvasSize(),
            presentsSheet: false,
            timelineContentHeight: lanes.timelineContentHeight(
                overlayLanes: max(1, model.overlayLaneCount),
                musicLanes: max(1, model.musicLaneCount)
            ),
            showsBottomBar: false,
            deskChromeHeight: VideoStudioMetrics.compactTransportHeight
        )
        // The group's panel lifts the stack only as far as keeps the video
        // lane clear of it: none on a 16:9 project, where the lane already
        // stands above y 530; a taller frame gives up what it must.
        let groupLift = showsGroup
            ? VideoStudioMetrics.groupPanelLift(
                timelineTop: bandHeight + idleLayout.preview + VideoStudioMetrics.compactTransportHeight + VideoStudioMetrics.previewTimelineGap,
                videoLaneBottom: lanes.topPadding + lanes.ruler + lanes.rulerGap
                    + lanes.videoLaneTop(overlayLanes: max(1, model.overlayLaneCount)) + lanes.video,
                panelTop: screen.height - panelHeight
            )
            : 0
        // The frame trim (FS-12.17 §4, board F6_P_PreciseTrim): the panel
        // goes, the timeline has its idle height back, and ✕ · "Trim · Clip
        // 2" · ✓ stands where the tools were.
        let isFrameTrimming = model.isFrameTrimming
        var layout = (showsGroup && groupLift == 0) || isFrameTrimming ? idleLayout : VideoStudioMetrics.stackLayout(
            screen: screen,
            bandHeight: bandHeight,
            bottomInset: proxy.safeAreaInsets.bottom,
            canvas: model.recipe.canvasSize(),
            presentsSheet: model.presentsSheet,
            // The timeline takes what its lanes need and no more: the
            // surplus belongs around the frame being edited.
            timelineContentHeight: lanes.timelineContentHeight(
                overlayLanes: max(1, model.overlayLaneCount),
                musicLanes: max(1, model.musicLaneCount)
            ),
            // Back and Export are in the top band (FS-12.07 §2), so there
            // is no bottom band to pay for.
            showsBottomBar: false,
            deskChromeHeight: VideoStudioMetrics.compactTransportHeight,
            presentsSessionFooter: showsSessionFooter,
            sheetHeight: showsGroup
                ? groupLift
                : (showsLookTool ? VideoStudioMetrics.lookSheetHeight + VideoStudioMetrics.toolbarHeight : contentHeight)
        )
        // The keyboard's list leaves the frame as it was (FS-12.17b §4,
        // AC-8): the timeline gives up what the panel takes, down to a
        // slice — the list is reference, the frame is the work.
        if model.isShortcutListInPanel, !isFrameTrimming {
            let canvas = model.recipe.canvasSize()
            let natural = canvas.width > 0 ? screen.width * canvas.height / canvas.width : layout.preview
            layout = layout.keepingPicture(of: idleLayout, natural: natural)
        }
        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                VideoStudioTopBand(model: model, phoneActions: actions(model))
                    .frame(height: bandHeight, alignment: .top)
                    .disabled(model.isExportBusy)
                preview(model)
                    .frame(height: layout.preview)
                // Not "no transport" — the same commands in the shape a
                // phone has room for. See `VideoCompactTransportBar`.
                VideoCompactTransportBar(model: model)
                Color.clear.frame(height: VideoStudioMetrics.previewTimelineGap)
                if !layout.hidesTimeline {
                    VideoTimelineView(
                        model: model,
                        height: layout.timeline,
                        onAddOverlay: { addTextOverlay(model) },
                        onAddMusic: { model.toggleToolPanel(.music) },
                        onAddMedia: { addMedia(model) },
                        onEditText: { editingOverlay = $0 },
                        onTransition: { model.editingTransitionIndex = $0 },
                        onVisibleDuration: { timelineVisibleDuration = $0 }
                    )
                    // Drop photos or clips straight onto the timeline.
                    .onDrop(
                        of: [PhotoDragItem.assetIdentifierType] + PhotoDropImport.acceptedTypes,
                        isTargeted: nil
                    ) { providers in
                        appendDroppedMedia(providers, to: model)
                    }
                }
                // Sits under the panel; keeps the timeline above it.
                Color.clear.frame(height: layout.lift)
                if isFrameTrimming, let title = model.frameTrimTitle() {
                    VideoSessionFooter(
                        title: title,
                        onCancel: { model.cancelFrameTrim() },
                        onCommit: { model.commitFrameTrim() }
                    )
                    .accessibilityIdentifier("frameTrimFooter")
                } else {
                    VideoStudioToolbar(model: model, actions: actions(model))
                }
                Color.clear.frame(height: proxy.safeAreaInsets.bottom)
            }

            if isFrameTrimming {
                // ‹ −1 Frame · 0:09.07 · +1 Frame ›, 14 above the footer.
                VideoFrameTrimPill(model: model)
                    .padding(.bottom, VideoStudioMetrics.toolbarHeight + proxy.safeAreaInsets.bottom + VideoStudioMetrics.FrameTrim.pillGap)
            }

            // The panel slides over the bars; the layout underneath never
            // moves, so the timeline stays exactly where the user left it.
            if model.presentsSheet, !isFrameTrimming {
                contextPanel(model, height: panelHeight, showsFooter: showsSessionFooter, bottomInset: proxy.safeAreaInsets.bottom)
                    .padding(.bottom, showsLookTool ? VideoStudioMetrics.toolbarHeight + proxy.safeAreaInsets.bottom : 0)
                    .transition(.move(edge: .bottom))
            }
        }
        .overlayPreferenceValue(FrameTrimLoupeAnchorKey.self) { anchor in
            frameTrimLoupe(model, anchor: anchor, diameter: VideoStudioMetrics.FrameTrim.loupeDiameterPhone, gap: VideoStudioMetrics.FrameTrim.loupeGapPhone, compact: true)
        }
        .background { keyboardShortcuts(model) }
        .environment(\.videoLaneMetrics, lanes)
        .environment(\.usesRegularToolChrome, false)
        .animation(EditorTheme.animation, value: model.presentsSheet)
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    /// Media dropped on the timeline. From inside ShotDex it is an asset
    /// identifier and appends at once; from another app it is a file, and a
    /// clip can only reference a `PHAsset`, so it is imported into the
    /// library first and appended when it lands.
    func appendDroppedMedia(_ providers: [NSItemProvider], to model: VideoStudioModel) -> Bool {
        let inApp = providers.filter {
            $0.hasItemConformingToTypeIdentifier(PhotoDragItem.assetIdentifierType)
        }
        if !inApp.isEmpty {
            model.dropImportTask = Task { @MainActor in
                var ids: [String] = []
                for provider in inApp {
                    let data: Data? = await withCheckedContinuation { continuation in
                        _ = provider.loadDataRepresentation(
                            forTypeIdentifier: PhotoDragItem.assetIdentifierType
                        ) { data, _ in continuation.resume(returning: data) }
                    }
                    if let data, let id = String(data: data, encoding: .utf8) { ids.append(id) }
                }
                guard !Task.isCancelled else { return }
                appendMedia(ids: ids, to: model, imported: 0, failed: 0)
            }
            return true
        }
        // A project of server photos keeps files from other apps out: they
        // would be imported into Photos first (FS-17.06 §5b).
        guard model.acceptsFilesFromOtherApps, PhotoDropImport.canImport(providers) else { return false }
        model.dropImportTask = Task { @MainActor in
            let result = await PhotoDropImport.importAssets(
                from: providers,
                into: dependencies.photoLibrary
            )
            guard !Task.isCancelled else { return }
            appendMedia(ids: result.ids, to: model, imported: result.ids.count, failed: result.failures)
        }
        return true
    }

    /// One library photo, added as a sticker overlay rather than a clip —
    /// the Stickers tab of the media pool.
    ///
    /// Rasterized at a bounded size: an overlay is drawn over the frame at a
    /// fraction of its width, and a 48-megapixel PNG held in an overlay store
    /// is memory spent on pixels nobody sees.
    @MainActor
    func addSticker(_ asset: PHAsset, to model: VideoStudioModel) {
        _ = dependencies.photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 1024, height: 1024),
            contentMode: .aspectFit
        ) { image, delivery in
            guard delivery.isFinal else { return }
            guard let image, let data = image.pngData() else {
                model.errorMessage = String(localized: "Couldn't add the sticker.")
                return
            }
            model.addImageOverlay(pngData: data, assetIdentifier: asset.localIdentifier)
        }
    }

    @MainActor
    func appendMedia(ids: [String], to model: VideoStudioModel, imported: Int, failed: Int) {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        let picks = assets.map {
            VideoMediaPick(assetID: $0.localIdentifier, kind: $0.mediaType == .video ? .video : .photo)
        }
        if !picks.isEmpty { model.appendMedia(picks) }
        // An import writes to the user's photo library; saying so is the
        // difference between adding a clip and putting a file somewhere they
        // did not watch it go.
        if imported > 0 {
            model.errorMessage = PhotoDropImport.addedMessage(
                count: imported,
                destination: .libraryAndTimeline
            )
        }
        if failed > 0 {
            model.errorMessage = PhotoDropImport.failureMessage(count: failed)
        }
    }

    /// Drag to trade preview height for timeline height. The app's own answer
    /// is that the surplus belongs around the frame (spec §7.9); this is how
    /// the user says otherwise, and Final Cut for iPad publishes the same
    /// handle at the top of its timeline.
    var timelineDivider: some View {
        Capsule()
            .fill(Color.white.opacity(0.28))
            .frame(width: VideoStudioDeskGeometry.dividerSize.width, height: VideoStudioDeskGeometry.dividerSize.height)
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
                        UserDefaults.standard.set(
                            timelineExtraHeight,
                            forKey: SettingsKeys.videoTimelineExtraHeight
                        )
                        timelineDragOffset = 0
                    }
            )
            .accessibilityLabel(Text(VideoStudioCopy.resizeTimeline))
            .accessibilityHint(Text("Drag up for a taller timeline, down for a bigger preview", comment: "Hint for the Video Studio timeline divider"))
            .accessibilityAdjustableAction { direction in
                timelineExtraHeight = Double(VideoStudioMetrics.steppedTimelineExtra(
                    CGFloat(timelineExtraHeight), increment: direction == .increment
                ))
                UserDefaults.standard.set(
                    timelineExtraHeight,
                    forKey: SettingsKeys.videoTimelineExtraHeight
                )
            }
    }

    /// The contextual editing panel. It looks and behaves like a bottom sheet —
    /// grabber, rounded top, drag down to dismiss — but is drawn in-screen rather
    /// than presented: the studio's pickers (font, media, music, sticker) are
    /// system sheets fired from here, and UIKit cannot present a sheet from a view
    /// that is already presenting one. It slides *over* the tool row and the
    /// bottom bar; nothing underneath is displaced.
    func contextPanel(
        _ model: VideoStudioModel,
        height: CGFloat,
        showsFooter: Bool = false,
        bottomInset: CGFloat = 0,
        showsGrabber: Bool = true
    ) -> some View {
        VStack(spacing: 0) {
            if showsGrabber {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 36, height: 5)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onEnded { value in
                                let dy = value.translation.height
                                // The Duo cover pulls a selected item's panel
                                // down to its 78pt strip and back (FS-12.07b
                                // §4); elsewhere a pull down closes and keeps.
                                if currentWindowClass == .duoCover, model.selectionTitle != nil, !model.isSelectingClips {
                                    if dy > 40 { model.setPanelCollapsed(true) } else if dy < -40 { model.setPanelCollapsed(false) }
                                } else if dy > 40 {
                                    if model.isShortcutListInPanel { model.closeShortcutList() } else { model.clearSelection() }
                                }
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: VideoStudioCopy.panelGrabber))
                    .accessibilityIdentifier("panelGrabber")
            }
            VideoStudioSheetHost(
                model: model, actions: actions(model), importedMusic: importedMusic,
                server: server, onServerExported: serverExported
            )
            if showsFooter, let title = model.sessionFooterTitle {
                VideoSessionFooter(
                    title: title,
                    onCancel: { model.cancelSession() },
                    onCommit: { model.commitSession() }
                )
                Color.clear.frame(height: bottomInset)
            }
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

    func actions(_ model: VideoStudioModel) -> VideoInspectorActions {
        VideoInspectorActions(
            onExport: { openExport(model) },
            onBack: { leave(model) },
            onAddMedia: { addMedia(model) },
            onReplaceClip: { model.beginReplacePick() },
            onAddText: { addTextOverlay(model) },
            onAddSticker: { isStickerPickerPresented = true },
            onAddMusic: { model.toggleToolPanel(.music) },
            onReplaceMusic: { musicChooserIntent = .replace($0) },
            onEditText: { editingOverlay = $0 },
            onPickFont: { isFontPickerPresented = true },
            onImportMusic: { isMusicImporterPresented = true },
            onEditCaption: { editingCaptionID = $0 }
        )
    }

    /// The loupe over the held edge (FS-12.17 §5): hung on the point the
    /// timeline publishes, drawn over everything, slid in from the screen's
    /// edges.
    @ViewBuilder
    func frameTrimLoupe(
        _ model: VideoStudioModel,
        anchor: Anchor<CGPoint>?,
        diameter: CGFloat,
        gap: CGFloat,
        compact: Bool
    ) -> some View {
        if let anchor, let trim = model.frameTrim, model.isFrameTrimHolding {
            GeometryReader { geo in
                let point = geo[anchor]
                let frame = VideoStudioMetrics.FrameTrim.loupeFrame(
                    edgeX: point.x, clipTop: point.y, diameter: diameter, gap: gap,
                    bounds: CGRect(origin: .zero, size: geo.size)
                )
                VideoFrameTrimLoupe(
                    frames: model.frameTrimFrames.loupe,
                    label: VideoFrameGrid.hundredths(trim.edgeTime) + " · " + VideoStudioCopy.frameCount(trim.frames, compact: compact),
                    diameter: diameter,
                    isOffline: model.frameTrimFrames.isOffline
                )
                .offset(x: frame.minX, y: frame.minY)
            }
            .allowsHitTesting(false)
        }
    }

    func preview(_ model: VideoStudioModel) -> some View {
        previewContent(model)
            // The frame takes no touches while an export runs (FS-12.10b §4).
            .allowsHitTesting(!model.isExportBusy)
    }

    private func previewContent(_ model: VideoStudioModel) -> some View {
        ZStack {
            Color.black
            // While Before and After draws a pair, the stage below shows it
            // through two windows on the same player (FS-12.15, plan K2).
            Group {
            if let player = model.player, model.compare?.drawsPair != true {
                VideoPlayerLayerView(player: player)
            }
            // Until the first preview item can play, the first clip's still
            // rather than a black stage under a live Play button (DUO_LOOP 38b).
            if !model.hasPreviewFrame, let first = model.recipe.clips.first {
                VideoPreviewStill(assetID: first.assetID, serverFile: model.serverFileURL(for: first.assetID))
            }
            // A library item under the pointer (FS-12.17b §6): its frame
            // over the project's, as it is in the source — no look yet.
            if let image = model.skimImage {
                Color.black
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .accessibilityIdentifier("skimFrame")
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
                    .opacity(model.compare?.mode == .sideBySide ? 0 : 1)
                    .position(x: contentRect.midX, y: contentRect.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                // The frame trim (FS-12.17 §4): the viewer shows the frame
                // at the edge — decoded from the source, since the preview
                // has not been rebuilt — under "Last frame · 0:09.07".
                if let trim = model.frameTrim {
                    if let image = model.frameTrimFrames.viewer {
                        // Framed the way the compositor frames the clip —
                        // filled or fitted on the project's background.
                        ZStack {
                            let colour = model.recipe.background.colour
                            Color(red: colour.red, green: colour.green, blue: colour.blue)
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: model.recipe.framing == .fill ? .fill : .fit)
                        }
                        .frame(width: contentRect.width, height: contentRect.height)
                        .clipped()
                        .position(x: contentRect.midX, y: contentRect.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                    // The phone's sits at the viewer's top-left; the Duo's
                    // inner display floats Back · Undo · Redo there, so its
                    // label sits low on the left (board F6_DI_TouchTrim).
                    let isDuoInner = currentWindowClass == .duoInner
                    VideoEdgeFrameLabel(
                        trim: trim,
                        height: isDuoInner
                            ? VideoStudioMetrics.FrameTrim.viewerLabelHeightDuoInner
                            : VideoStudioMetrics.FrameTrim.viewerLabelHeightPhone,
                        fontSize: isDuoInner ? 11.5 : 11
                    )
                    .fixedSize()
                    .padding(.leading, isDuoInner ? VideoStudioMetrics.FrameTrim.viewerLabelInsetDuoInner : VideoStudioMetrics.FrameTrim.viewerLabelInset)
                    .padding(.top, isDuoInner ? 0 : VideoStudioMetrics.FrameTrim.viewerLabelInset)
                    .padding(.bottom, isDuoInner ? VideoStudioMetrics.FrameTrim.viewerLabelBottomDuoInner : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isDuoInner ? .bottomLeading : .topLeading)
                    .allowsHitTesting(false)
                }
                // "9:16 · Fill" at the frame's top-left while Video
                // Settings is open (FS-12.10 §4): what the frame is now.
                if model.activeToolPanel == .videoSettings {
                    Text(verbatim: VideoStudioCopy.frameLabel(model.recipe))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        // Below the Duo inner display's floating Back · Undo · Redo,
                        // which sit over the frame's top-left corner.
                        .position(
                            x: contentRect.minX + 8 + 37,
                            y: contentRect.minY + 18 + (currentWindowClass == .duoInner ? 48 : 0)
                        )
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("videoFrameLabel")
                }
                let afterRect = compareAfterRect(model, contentRect: contentRect, stage: compareStage(geo.size))
                if let compare = model.compare, compare.drawsPair, let player = model.player {
                    VideoBeforeAfterStage(
                        model: model, compare: compare, player: player,
                        contentRect: contentRect, stage: compareStage(geo.size),
                        windowClass: currentWindowClass
                    )
                }
                // Overlays and captions belong to After: hidden while the
                // original is held, on the After frame side by side, and cut
                // at the Split line (FS-12.15 §3).
                if !model.showsOriginal {
                    Group {
                        VideoOverlayCanvas(
                            model: model,
                            contentRect: afterRect,
                            images: stickerImages
                        )
                        // Captions over everything, as the export burns them
                        // in (FS-12.14 §6).
                        VideoCaptionProxyLayer(
                            model: model,
                            contentRect: afterRect,
                            frame: model.recipe.canvasSize(),
                            showsSelectionOutline: currentWindowClass != .phone && currentWindowClass != .duoCover
                        )
                    }
                    .allowsHitTesting(model.compare?.drawsPair != true)
                    .mask {
                        if let compare = model.compare, compare.mode == .split {
                            Rectangle()
                                .frame(width: max(0, contentRect.maxX - compare.lineX(in: contentRect)), height: geo.size.height)
                                .position(x: (compare.lineX(in: contentRect) + contentRect.maxX) / 2, y: geo.size.height / 2)
                        } else {
                            Rectangle()
                        }
                    }
                }
            }
            }
            // Fit on Background: the project's frame drawn smaller inside
            // the preset's frame while Export Video is open (FS-12.16 §4).
            .scaleEffect(exportFitScale(model))
            exportFramingOverlay(model)
            // In Split the play button moves to After's half, clear of the
            // line's handle (FS-12.15 §4) — the stage draws it there.
            if !model.isPlaying, model.compare?.mode != .split, !model.isFrameTrimming {
                // `.editorGlass`, like every other round control this app
                // floats over a photo. This was a hand-rolled colour plus
                // `.ultraThinMaterial` from the feature's first commit —
                // a system material in tier D, which DESIGN §9 allows through
                // exactly three entry points and this was none of them.
                Button { model.togglePlayback() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background { Color.clear.editorGlass(Circle()) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Play", comment: "Video Studio: starts preview playback"))
            }
        }
        .frame(maxWidth: .infinity)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { previewSize = geometry.size }
                .onChange(of: geometry.size) { _, size in previewSize = size }
        })
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
        // Side by Side · Split over the iPad's stage (FS-12.15 §4).
        .overlay(alignment: .top) {
            if let compare = model.compare, currentWindowClass == .iPadLandscape || currentWindowClass == .iPadPortrait {
                VideoDeskSegmented(
                    items: VideoBeforeAfter.modes(sideBySide: true).map { ($0, VideoStudioCopy.compareMode($0), "compareMode.\($0.rawValue)") },
                    selection: Binding(get: { compare.mode }, set: { model.setCompareMode($0) }),
                    label: Text(VideoStudioCopy.beforeAndAfter)
                )
                .frame(width: 280)
                .padding(.top, 4)
            }
        }
        // Hold to Compare (FS-12.15 §5, AC-4): a finger on the frame shows
        // Before until it lifts.
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !model.showsOriginal { model.holdCompare(true) } }
                .onEnded { _ in model.holdCompare(false) },
            including: model.compare?.mode == .hold ? .all : .none
        )
        .onAppear { loadStickerImages(model) }
        .onChange(of: model.recipe.overlays) { loadStickerImages(model) }
    }

    /// Export Video is open with a preset whose ratio is not the project's.
    private func exportFraming(_ model: VideoStudioModel) -> (spec: VideoExportSpec, framing: VideoFraming, preset: VideoExportPreset)? {
        guard model.activeToolPanel == .export || isExportSheetPresented,
              case .preset(let preset) = model.exportTarget
        else { return nil }
        let spec = model.exportSpec
        guard let framing = spec.framing else { return nil }
        return (spec, framing, preset)
    }

    private func exportFitScale(_ model: VideoStudioModel) -> CGFloat {
        guard let framing = exportFraming(model), framing.framing == .fit, previewSize.width > 0 else { return 1 }
        let content = VideoGeometry.stillFitRect(imageSize: model.recipe.canvasSize(), renderSize: previewSize)
        let fit = VideoExportFraming.fit(in: content, output: framing.spec.size, project: model.recipe.canvasSize())
        return fit.project.width / max(content.width, 1)
    }

    /// Fill: the crop over the frame — outside it dimmed 62 %, a 1.5pt
    /// white rule, "9:16 · Fill" at its corner. Fit: the preset's frame,
    /// the project's background in the bands around the smaller frame.
    @ViewBuilder
    private func exportFramingOverlay(_ model: VideoStudioModel) -> some View {
        if let framing = exportFraming(model), previewSize.width > 0 {
            let content = VideoGeometry.stillFitRect(imageSize: model.recipe.canvasSize(), renderSize: previewSize)
            let output = framing.framing == .fill
                ? VideoExportFraming.fillCrop(in: content, output: framing.spec.size)
                : VideoExportFraming.fit(in: content, output: framing.spec.size, project: model.recipe.canvasSize()).output
            ZStack(alignment: .topLeading) {
                if framing.framing == .fill {
                    Path { path in
                        path.addRect(content)
                        path.addRect(output)
                    }
                    .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                } else {
                    let inner = VideoExportFraming.fit(in: content, output: framing.spec.size, project: model.recipe.canvasSize()).project
                    let colour = model.recipe.background.colour
                    Path { path in
                        path.addRect(output)
                        path.addRect(inner)
                    }
                    .fill(Color(red: colour.red, green: colour.green, blue: colour.blue), style: FillStyle(eoFill: true))
                }
                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1.5)
                    .frame(width: output.width, height: output.height)
                    .offset(x: output.minX, y: output.minY)
                Text(verbatim: VideoExportFraming.pill(framing.preset, framing: framing.framing))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 70, height: 20)
                    .background(Capsule().fill(Color.white))
                    .offset(x: output.minX + 6, y: output.minY + 6)
                    .accessibilityIdentifier("exportFramingPill")
            }
            .frame(width: previewSize.width, height: previewSize.height, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }

    /// Where Side by Side lays its two frames: the stage, short of the
    /// iPad's level meter on the right.
    private func compareStage(_ size: CGSize) -> CGRect {
        let isPad = currentWindowClass == .iPadLandscape || currentWindowClass == .iPadPortrait
        return CGRect(x: 0, y: 0, width: max(0, size.width - (isPad ? VideoBeforeAfterStage.meterAllowance : 0)), height: size.height)
    }

    /// Where After's frame is: the project frame, or — side by side — the
    /// After window of the pair.
    private func compareAfterRect(_ model: VideoStudioModel, contentRect: CGRect, stage: CGRect) -> CGRect {
        guard let compare = model.compare, compare.mode == .sideBySide else { return contentRect }
        let canvas = model.recipe.canvasSize()
        let inset: CGFloat = currentWindowClass == .duoInner ? 9 : 14
        let gap: CGFloat = currentWindowClass == .duoInner ? 8 : 16
        let frames = VideoBeforeAfterStage.frames(in: stage, aspect: canvas.width / max(canvas.height, 1), inset: inset, gap: gap, windowClass: currentWindowClass)
        return compare.isSwapped ? frames.left : frames.right
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
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? EditorTheme.activeRow : EditorTheme.emptyLane))
    }
}

/// Decodes and caches downsampled waveforms for the chooser rows, lazily as
/// each row appears (only visible rows decode). Reuse across scrolls is free.
@MainActor
final class MusicWaveformCache: ObservableObject {
    @Published private var cache: [String: [Float]] = [:]
    @Published private var durations: [String: Double] = [:]
    private var inFlight: Set<String> = []

    func samples(for id: String) -> [Float] { cache[id] ?? [] }

    /// "3:24 · m4a" — the song's length once it is known, and its kind.
    func detail(for id: String, url: URL) -> String {
        let kind = url.pathExtension.lowercased()
        guard let seconds = durations[id] else { return kind }
        let whole = Int(seconds.rounded())
        return String(format: "%d:%02d · %@", whole / 60, whole % 60, kind)
    }

    func load(id: String, url: URL) async {
        if cache[id] != nil || inFlight.contains(id) { return }
        inFlight.insert(id)
        let samples = await VideoWaveform.samples(from: url, buckets: 56)
        cache[id] = samples
        if let duration = try? await AVURLAsset(url: url).load(.duration) {
            durations[id] = duration.seconds
        }
        inFlight.remove(id)
    }
}

/// A compact mirrored-bar waveform for a chooser row.
struct MusicRowWaveform: View {
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

/// The iPad's Export Video sheet at the size the boards draw it (FS-12.10b
/// §2): 700 × 620, 572 while exporting, radius 22, over the system scrim.
private struct VideoExportSheetSizing: ViewModifier {
    let isExporting: Bool

    func body(content: Content) -> some View {
        let sheet = VideoStudioMetrics.ExportSheet.self
        let height = isExporting ? sheet.exportingHeight : sheet.readyHeight
        if #available(iOS 18.0, *) {
            content
                .frame(width: sheet.width, height: height)
                .presentationSizing(.fitted)
                .presentationCornerRadius(sheet.cornerRadius)
        } else {
            content
                .frame(idealWidth: sheet.width, idealHeight: height)
                .presentationCornerRadius(sheet.cornerRadius)
        }
    }
}

/// The first clip's still, shown on the stage until the preview has a frame.
private struct VideoPreviewStill: View {
    let assetID: String
    let serverFile: URL?
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: assetID) { await load() }
    }

    private func load() async {
        if let serverFile {
            image = await PhotoOriginFile.loadImage(at: serverFile, maxPixelSize: 1024)
            return
        }
        guard let asset = PhotoLibraryService.fetchAssets(ids: [assetID]).first else { return }
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 1024, height: 1024),
            contentMode: .aspectFit,
            allowNetwork: false
        ) { result, _ in
            if let result { image = result }
        }
    }
}
