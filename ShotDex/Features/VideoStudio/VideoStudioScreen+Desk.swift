import SwiftUI

/// The Video Studio's layouts for every window that is not a phone
/// (FS-12.03, FS-12.07b): each one reads its rects from
/// `VideoStudioDeskGeometry` and places the bands there, in window
/// coordinates. The views inside the bands are the studio's own.
extension VideoStudioScreen {
    // MARK: iPad landscape (FS-12.03 §2, board IL1)

    func deskLandscape(_ model: VideoStudioModel, window: CGSize) -> some View {
        let lanes = VideoStudioMetrics.Lanes.for(.iPadLandscape)
        let canOpenPool = VideoStudioDeskGeometry.canOpenPool(
            windowWidth: window.width,
            isInspectorOpen: isInspectorOpen
        )
        let showsPool = canOpenPool
            && (isMediaPoolOpen ?? VideoStudioDeskGeometry.poolOpensByDefault(windowWidth: window.width))
        let frames = VideoStudioDeskGeometry.iPadLandscape(.init(
            window: window,
            canvas: model.recipe.canvasSize(),
            isPoolOpen: showsPool,
            isInspectorOpen: isInspectorOpen,
            laneNeed: laneNeed(model, lanes: lanes),
            timelineExtra: CGFloat(timelineExtraHeight) + timelineDragOffset
        ))
        return ZStack(alignment: .topLeading) {
            EditorTheme.background
            VideoStudioDeskBand(model: model, actions: actions(model))
                .placed(frames.band)
            if let pool = frames.pool {
                mediaPool(model, width: pool.width)
                    .placed(pool)
            }
            if let header = frames.header {
                VideoViewerHeader(
                    model: model,
                    isMediaPoolOpen: canOpenPool || showsPool ? showsPool : nil,
                    isInspectorOpen: isInspectorOpen,
                    isToolStripOpen: isToolStripOpen,
                    onToggleMediaPool: { isMediaPoolOpen = !showsPool },
                    onToggleInspector: { isInspectorOpen.toggle() },
                    onToggleToolStrip: { isToolStripOpen.toggle() }
                )
                .placed(header)
            }
            preview(model)
                .placed(frames.stage)
            if let meter = frames.meter {
                VideoAudioMeterColumn(model: model, meter: levelMeter, width: meter.width)
                    .placed(meter)
            }
            if let inspector = frames.inspector {
                inspectorColumn(model)
                    .placed(inspector)
            }
            VideoTransportBar(model: model)
                .placed(frames.transport)
            if let overview = frames.overview {
                VideoTimelineOverview(model: model, visibleDuration: timelineVisibleDuration)
                    .placed(overview)
            }
            deskTimeline(model, height: frames.timeline.height)
                .placed(frames.timeline)
            timelineDivider
                .frame(width: 120)
                .position(x: frames.timeline.midX, y: frames.timeline.minY + 4)
            // With the column shut, a selection still needs its controls:
            // the panel slides over the timeline (until the column learns
            // to open itself — FS-12.03 §5).
            if frames.inspector == nil, model.presentsSheet {
                contextPanel(model, height: VideoStudioMetrics.sheetHeight)
                    .frame(width: window.width)
                    .offset(y: window.height - VideoStudioMetrics.sheetHeight)
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .deskChrome(model, lanes: lanes, meter: levelMeter, hasMeter: frames.meter != nil, shortcuts: keyboardShortcuts(model))
    }

    // MARK: iPad portrait (FS-12.03 §3, board IP1)

    func deskPortrait(_ model: VideoStudioModel, window: CGSize) -> some View {
        let lanes = VideoStudioMetrics.Lanes.for(.iPadPortrait)
        let canOpenPool = VideoStudioDeskGeometry.canOpenPool(windowWidth: window.width, isInspectorOpen: false)
        let showsPool = canOpenPool
            && (isMediaPoolOpen ?? VideoStudioDeskGeometry.poolOpensByDefault(windowWidth: window.width))
        let frames = VideoStudioDeskGeometry.iPadPortrait(.init(
            window: window,
            canvas: model.recipe.canvasSize(),
            isPoolOpen: showsPool,
            isInspectorOpen: isInspectorOpen,
            laneNeed: laneNeed(model, lanes: lanes),
            timelineExtra: CGFloat(timelineExtraHeight) + timelineDragOffset
        ))
        return ZStack(alignment: .topLeading) {
            EditorTheme.background
            VideoStudioDeskBand(model: model, actions: actions(model), isPortrait: true)
                .placed(frames.band)
            if let pool = frames.pool {
                mediaPool(model, width: pool.width)
                    .placed(pool)
            }
            if let header = frames.header {
                VideoViewerHeader(
                    model: model,
                    isMediaPoolOpen: canOpenPool || showsPool ? showsPool : nil,
                    isInspectorOpen: isInspectorOpen,
                    isToolStripOpen: isToolStripOpen,
                    onToggleMediaPool: { isMediaPoolOpen = !showsPool },
                    onToggleInspector: { isInspectorOpen.toggle() },
                    onToggleToolStrip: { isToolStripOpen.toggle() }
                )
                .placed(header)
            }
            preview(model)
                .placed(frames.stage)
            if let meter = frames.meter {
                VideoAudioMeterColumn(model: model, meter: levelMeter, width: meter.width)
                    .placed(meter)
            }
            VideoTransportBar(model: model)
                .placed(frames.transport)
            if let overview = frames.overview {
                VideoTimelineOverview(model: model, visibleDuration: timelineVisibleDuration)
                    .placed(overview)
            }
            deskTimeline(model, height: frames.timeline.height)
                .placed(frames.timeline)
            timelineDivider
                .frame(width: 120)
                .position(x: frames.timeline.midX, y: frames.timeline.minY + 4)
            if let dock = frames.dock {
                VideoStudioDock(model: model, actions: actions(model), importedMusic: importedMusic)
                    .placed(dock)
            } else if model.presentsSheet {
                contextPanel(model, height: VideoStudioMetrics.sheetHeight)
                    .frame(width: window.width)
                    .offset(y: window.height - VideoStudioMetrics.sheetHeight)
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .deskChrome(model, lanes: lanes, meter: levelMeter, hasMeter: frames.meter != nil, shortcuts: keyboardShortcuts(model))
    }

    // MARK: Duo inner display (FS-12.03 §4, board DI1)

    /// The frame and the 264pt column side by side from the top — the frame
    /// is limited by the height, so the column is free — then the 40pt
    /// transport, the 188pt timeline and the 56pt bottom row. No pool, no
    /// meter, no viewer header: each would cost the height this window
    /// lacks. Back · Undo · Redo · Show original float over the frame.
    func duoInner(_ model: VideoStudioModel, window: CGSize) -> some View {
        let lanes = VideoStudioMetrics.Lanes.for(.duoInner)
        let frames = VideoStudioDeskGeometry.duoInner(.init(
            window: window,
            canvas: model.recipe.canvasSize(),
            isPoolOpen: false,
            isInspectorOpen: true
        ))
        let discs = VideoStudioDeskGeometry.duoDiscFrames()
        return ZStack(alignment: .topLeading) {
            EditorTheme.background
            preview(model)
                .placed(frames.stage)
            duoDisc("chevron.left", isEnabled: true, action: { leave(model) })
                .accessibilityLabel(Text("Back", comment: "Video Studio: leaves the editor"))
                .placed(discs[0])
            duoDisc("arrow.uturn.backward", isEnabled: model.canUndo, action: { model.undo() })
                .accessibilityLabel("Undo")
                .placed(discs[1])
            duoDisc("arrow.uturn.forward", isEnabled: model.canRedo, action: { model.redo() })
                .accessibilityLabel("Redo")
                .placed(discs[2])
            VideoShowOriginalButton(
                model: model,
                diameter: VideoStudioDeskGeometry.duoDisc,
                glyphSize: 14,
                restingFill: Color.black.opacity(0.55)
            )
            .placed(discs[3])
            if let column = frames.inspector {
                VideoStudioSheetHost(
                    model: model,
                    actions: actions(model),
                    layout: .column,
                    importedMusic: importedMusic,
                    showsIdleLook: true
                )
                .background(EditorTheme.panelSolid)
                .placed(column)
            }
            VideoTransportBar(model: model, height: frames.transport.height)
                .placed(frames.transport)
            deskTimeline(model, height: frames.timeline.height)
                .placed(frames.timeline)
            if let row = frames.bottomRow {
                VideoStudioDuoBottomRow(model: model, actions: actions(model))
                    .placed(row)
            }
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .deskChrome(model, lanes: lanes, meter: levelMeter, hasMeter: false, shortcuts: keyboardShortcuts(model))
    }

    /// A 36pt disc on black 55 %, floating over the Duo's frame.
    private func duoDisc(_ systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.3))
                .frame(width: VideoStudioDeskGeometry.duoDisc, height: VideoStudioDeskGeometry.duoDisc)
                .background(Circle().fill(Color.black.opacity(0.55)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: Shared pieces

    /// What the lanes of this project need to show without scrolling.
    func laneNeed(_ model: VideoStudioModel, lanes: VideoStudioMetrics.Lanes) -> CGFloat {
        lanes.timelineContentHeight(
            overlayLanes: max(1, model.overlayLaneCount),
            musicLanes: max(1, model.musicLaneCount)
        )
    }

    /// The inspector column: Look when nothing is selected, the selected
    /// item's commands and controls otherwise, a tool's panel when one is
    /// open. Rounded at its top leading corner.
    func inspectorColumn(_ model: VideoStudioModel) -> some View {
        VideoStudioSheetHost(
            model: model,
            actions: actions(model),
            layout: .column,
            importedMusic: importedMusic,
            showsIdleLook: true
        )
        .background(EditorTheme.panelSolid)
        .clipShape(UnevenRoundedRectangle(
            cornerRadii: .init(topLeading: VideoStudioDeskGeometry.inspectorCornerRadius),
            style: .continuous
        ))
    }

    func mediaPool(_ model: VideoStudioModel, width: CGFloat) -> some View {
        VideoMediaPoolColumn(
            model: model,
            photoLibrary: dependencies.photoLibrary,
            width: width,
            importedMusic: importedMusic,
            onClose: { isMediaPoolOpen = false },
            onBrowseAll: { mediaPickerMode = .add },
            onChooseSticker: { isStickerPickerPresented = true },
            onImportMusic: { isMusicImporterPresented = true },
            onAddSticker: { addSticker($0, to: model) },
            onAddText: { font in
                if let font { model.rememberFont(font) }
                addTextOverlay(model, font: font)
            }
        )
    }

    func deskTimeline(_ model: VideoStudioModel, height: CGFloat) -> some View {
        VideoTimelineView(
            model: model,
            height: height,
            onAddOverlay: { addTextOverlay(model) },
            onAddMusic: { model.toggleToolPanel(.music) },
            onAddMedia: { mediaPickerMode = .add },
            onEditText: { editingOverlay = $0 },
            onTransition: { model.editingTransitionIndex = $0 },
            onVisibleDuration: { timelineVisibleDuration = $0 }
        )
        // Drop photos or clips straight onto the timeline from Photos or
        // Files beside us in Split View.
        .onDrop(
            of: [PhotoDragItem.assetIdentifierType] + PhotoDropImport.acceptedTypes,
            isTargeted: nil
        ) { providers in
            appendDroppedMedia(providers, to: model)
        }
    }
}

extension View {
    /// Places the view at `rect`, in the coordinates of a top-leading ZStack
    /// that fills the window.
    func placed(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }

    /// What every wide layout carries around its bands: the keyboard
    /// shortcuts, the lane tier, the meter's refresh, and a window that runs
    /// past every safe-area inset so the rects are window coordinates.
    func deskChrome(
        _ model: VideoStudioModel,
        lanes: VideoStudioMetrics.Lanes,
        meter: VideoLevelMeterModel,
        hasMeter: Bool,
        shortcuts: some View
    ) -> some View {
        self
            .background { shortcuts }
            // The meter reads the recipe at the playhead, so it is recomputed
            // on the two things that change what is there.
            .onChange(of: model.currentTime) { if hasMeter { meter.refresh(model) } }
            .onChange(of: model.recipe) { if hasMeter { meter.refresh(model) } }
            .onAppear { if hasMeter { meter.refresh(model) } }
            .environment(\.videoLaneMetrics, lanes)
            .environment(\.usesRegularToolChrome, true)
            .animation(EditorTheme.animation, value: model.presentsSheet)
            .ignoresSafeArea(.container)
            .ignoresSafeArea(.keyboard)
    }
}
