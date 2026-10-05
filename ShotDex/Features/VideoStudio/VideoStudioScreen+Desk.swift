import SwiftUI

/// The Video Studio's layouts for every window that is not a phone
/// (FS-12.03, FS-12.07b): each one reads its rects from
/// `VideoStudioDeskGeometry` and places the bands there, in window
/// coordinates. The views inside the bands are the studio's own.
extension VideoStudioScreen {
    // MARK: iPad landscape (FS-12.03 §2, board IL1)

    func deskLandscape(_ model: VideoStudioModel, window: CGSize) -> some View {
        let lanes = VideoStudioMetrics.Lanes.for(.iPadLandscape).showingCaptions(model.hasCaptionLane)
        let canOpenPool = VideoStudioDeskGeometry.canOpenPool(
            windowWidth: window.width,
            isInspectorOpen: columns.isInspectorOpen
        )
        let showsPool = canOpenPool
            && (columns.isPoolOpen ?? VideoStudioDeskGeometry.poolOpensByDefault(windowWidth: window.width))
        let frames = VideoStudioDeskGeometry.iPadLandscape(.init(
            window: window,
            canvas: model.recipe.canvasSize(),
            isPoolOpen: showsPool,
            isInspectorOpen: columns.isInspectorOpen,
            laneNeed: laneNeed(model, lanes: lanes),
            timelineExtra: CGFloat(timelineExtraHeight) + timelineDragOffset
        ))
        return ZStack(alignment: .topLeading) {
            EditorTheme.background
            deskStage(model, frames: frames)
            if let inspector = frames.inspector {
                inspectorColumn(model)
                    .placed(inspector)
            }
            deskPoolAndToolbar(model, frames: frames, canOpenPool: canOpenPool, showsPool: showsPool)
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .deskChrome(model, lanes: lanes, meter: levelMeter, hasMeter: frames.meter != nil, shortcuts: keyboardShortcuts(model))
    }

    // MARK: iPad portrait (FS-12.03 §3, board IP1)

    func deskPortrait(_ model: VideoStudioModel, window: CGSize) -> some View {
        let lanes = VideoStudioMetrics.Lanes.for(.iPadPortrait).showingCaptions(model.hasCaptionLane)
        let canOpenPool = VideoStudioDeskGeometry.canOpenPool(windowWidth: window.width, isInspectorOpen: false)
        let showsPool = canOpenPool
            && (columns.isPoolOpen ?? VideoStudioDeskGeometry.poolOpensByDefault(windowWidth: window.width))
        let frames = VideoStudioDeskGeometry.iPadPortrait(.init(
            window: window,
            canvas: model.recipe.canvasSize(),
            isPoolOpen: showsPool,
            isInspectorOpen: columns.isInspectorOpen,
            laneNeed: laneNeed(model, lanes: lanes),
            timelineExtra: CGFloat(timelineExtraHeight) + timelineDragOffset
        ))
        return ZStack(alignment: .topLeading) {
            EditorTheme.background
            deskStage(model, frames: frames)
            // Shut, the dock opens again on the next selection (FS-12.03 §5)
            // — there is no second, sliding panel for the same job.
            if let dock = frames.dock {
                VideoStudioDock(model: model, actions: actions(model), importedMusic: importedMusic)
                    .placed(dock)
            }
            deskPoolAndToolbar(model, frames: frames, canOpenPool: canOpenPool, showsPool: showsPool)
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .deskChrome(model, lanes: lanes, meter: levelMeter, hasMeter: frames.meter != nil, shortcuts: keyboardShortcuts(model))
    }

    /// The iPad's bands from the frame down, the same in both orientations:
    /// the frame and its meter, the play row under them, the timeline's tool
    /// row, the overview, the timeline and the divider's grabber.
    @ViewBuilder
    private func deskStage(_ model: VideoStudioModel, frames: VideoStudioDeskGeometry.Frames) -> some View {
        let box = frames.frameBox ?? frames.stage
        preview(model)
            .placed(quickAdjustTrimmed(box))
        if columns.isQuickAdjustOpen {
            VideoViewerToolStrip(model: model)
                .placed(quickAdjustStrip(box))
        }
        if let meter = frames.meter {
            // Side by Side spans the frame's box; the meter moves to the
            // box's edge, beside the After frame (board F7_IL).
            let placedMeter = model.compare?.mode == .sideBySide
                ? CGRect(x: box.maxX - 1, y: box.minY + 40, width: meter.width, height: min(meter.height, box.height - 40))
                : meter
            VideoAudioMeterColumn(model: model, meter: levelMeter, width: placedMeter.width)
                .placed(placedMeter)
        }
        if let playRow = frames.playRow {
            // Side by Side: the row runs to the After frame's edge, Before
            // and After at its end (FS-12.15 §4: x 945 with the pool shut).
            let row = model.compare?.mode == .sideBySide
                ? CGRect(x: playRow.minX, y: playRow.minY, width: box.maxX + 33 - playRow.minX, height: playRow.height)
                : playRow
            VideoPlayRow(model: model, groupMidX: (frames.playGroupMidX ?? row.midX) - row.minX)
                .placed(row)
        }
        VideoTimelineToolRow(model: model)
            .placed(frames.transport)
        if let overview = frames.overview {
            VideoTimelineOverview(model: model, visibleDuration: timelineVisibleDuration)
                .placed(overview)
        }
        deskTimeline(model, height: frames.timeline.height)
            .placed(frames.timeline)
        if let divider = frames.divider {
            timelineDivider
                .frame(width: 120)
                .position(x: divider.midX, y: divider.midY)
        }
    }

    /// The floating pool and the toolbar's capsules: drawn last, over the
    /// inspector's head (it runs from the window's top edge) and, in
    /// portrait, over the frame.
    @ViewBuilder
    private func deskPoolAndToolbar(
        _ model: VideoStudioModel,
        frames: VideoStudioDeskGeometry.Frames,
        canOpenPool: Bool,
        showsPool: Bool
    ) -> some View {
        if let pool = frames.pool {
            mediaPool(model, width: pool.width)
                .placed(pool)
        }
        VideoStudioDeskToolbar(
            model: model,
            actions: actions(model),
            isPoolOpen: canOpenPool || showsPool ? showsPool : nil,
            isInspectorOpen: columns.isInspectorOpen,
            isQuickAdjustOpen: columns.isQuickAdjustOpen,
            isExportOpen: isExportSheetPresented,
            onTogglePool: { columns.isPoolOpen = !showsPool },
            onToggleInspector: { columns.isInspectorOpen.toggle() },
            onToggleQuickAdjust: { columns.isQuickAdjustOpen.toggle() }
        )
        .disabled(model.isExportBusy)
        .placed(frames.band)
    }

    // MARK: Duo inner display (FS-12.03 §4, board DI1)

    /// The frame and the 264pt column side by side from the top — the frame
    /// is limited by the height, so the column is free — then the 40pt
    /// transport, the 188pt timeline and the 56pt bottom row. No pool, no
    /// meter, no viewer header: each would cost the height this window
    /// lacks. Back · Undo · Redo · Show original float over the frame.
    func duoInner(_ model: VideoStudioModel, window: CGSize) -> some View {
        let lanes = VideoStudioMetrics.Lanes.for(.duoInner).showingCaptions(model.hasCaptionLane)
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
            // Before and After in Show original's place (FS-12.15 §4):
            // a tap compares, a hold still shows the original.
            VideoDuoCompareDisc(model: model, diameter: VideoStudioDeskGeometry.duoDisc)
                .placed(discs[3])
            if let column = frames.inspector {
                VideoStudioSheetHost(
                    model: model,
                    actions: actions(model),
                    layout: .column,
                    importedMusic: importedMusic,
                    showsIdleLook: true,
                    server: server,
                    onServerExported: serverExported
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

    // MARK: Duo cover display (FS-12.07b, board DC1)

    /// The content in the safe 382pt — Back · Undo · Redo, the frame's
    /// 382×215 box, the phone's compact transport, the timeline to the home
    /// indicator — and the tools in the 84pt rail beside it. A tool's panel
    /// covers the timeline; the frame and the transport never move.
    func duoCover(_ model: VideoStudioModel, window: CGSize) -> some View {
        let lanes = VideoStudioMetrics.Lanes.for(.duoCover).showingCaptions(model.hasCaptionLane)
        let frames = VideoStudioDeskGeometry.duoCover(.init(
            window: window,
            canvas: model.recipe.canvasSize(),
            isPoolOpen: false,
            isInspectorOpen: false
        ))
        let discs = VideoStudioDeskGeometry.coverDiscFrames()
        return ZStack(alignment: .topLeading) {
            EditorTheme.background
            coverDisc("chevron.left", isEnabled: true, action: { leave(model) })
                .accessibilityLabel(Text("Back", comment: "Video Studio: leaves the editor"))
                .placed(discs[0])
            coverDisc("arrow.uturn.backward", isEnabled: model.canUndo, action: { model.undo() })
                .accessibilityLabel("Undo")
                .placed(discs[1])
            coverDisc("arrow.uturn.forward", isEnabled: model.canRedo, action: { model.redo() })
                .accessibilityLabel("Redo")
                .placed(discs[2])
            preview(model)
                .placed(frames.stage)
            VideoCompactTransportBar(model: model)
                .placed(frames.transport)
            if model.inspectorTarget == .clips, model.activeItemCommand != .look {
                // A multi-select group (FS-12.11 §3, board F1_DC): the
                // timeline stays, 240 tall at 18pt a second, so more clips
                // can be tapped; the panel is the row and one control row.
                let selection = VideoStudioDeskGeometry.coverGroupSelection(frames)
                if let timeline = selection.timeline {
                    deskTimeline(model, height: timeline.height, zoomOverride: VideoStudioDeskGeometry.coverGroupPointsPerSecond)
                        .placed(timeline)
                }
                contextPanel(model, height: window.height - selection.panel.minY)
                    .frame(width: selection.panel.width)
                    .offset(x: selection.panel.minX, y: selection.panel.minY)
                    .transition(.move(edge: .bottom))
            } else if model.inspectorTarget != .none {
                // A selected item (FS-12.07b §4): the overview under the
                // transport and the panel from 334 — or, pulled down, the
                // timeline back down to 566 over a 78pt panel. ✕ and ✓ are
                // in the rail.
                let selection = VideoStudioDeskGeometry.coverSelection(
                    frames,
                    isCollapsed: model.session?.isCollapsed == true
                )
                if let timeline = selection.timeline {
                    deskTimeline(model, height: timeline.height)
                        .placed(timeline)
                }
                if let overview = selection.overview {
                    VideoTimelineOverview(model: model, visibleDuration: timelineVisibleDuration)
                        .placed(overview)
                }
                contextPanel(model, height: window.height - selection.panel.minY)
                    .frame(width: selection.panel.width)
                    .offset(x: selection.panel.minX, y: selection.panel.minY)
                    .transition(.move(edge: .bottom))
            } else {
                deskTimeline(model, height: frames.timeline.height)
                    .placed(frames.timeline)
                if model.presentsSheet, let panel = frames.toolPanel {
                    // A tool's panel covers the timeline; its background
                    // runs on under the home indicator.
                    contextPanel(model, height: window.height - panel.minY)
                        .frame(width: panel.width)
                        .offset(x: panel.minX, y: panel.minY)
                        .transition(.move(edge: .bottom))
                }
            }
            if let rail = frames.rail {
                VideoStudioDuoCoverRail(model: model, actions: actions(model), windowWidth: window.width)
                    .placed(rail)
            }
        }
        .frame(width: window.width, height: window.height, alignment: .topLeading)
        .deskChrome(model, lanes: lanes, meter: levelMeter, hasMeter: false, shortcuts: keyboardShortcuts(model))
    }

    /// A 34pt disc on white 10 % — the cover's top row.
    private func coverDisc(_ systemName: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.28))
                .frame(width: VideoStudioDeskGeometry.coverDisc, height: VideoStudioDeskGeometry.coverDisc)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    // MARK: Shared pieces

    /// The stage less the Quick Adjust strip when it is open: the strip
    /// is 44pt taken off the bottom of the frame's box (FS-12.03b §1).
    func quickAdjustTrimmed(_ stage: CGRect) -> CGRect {
        guard columns.isQuickAdjustOpen else { return stage }
        var rect = stage
        rect.size.height -= VideoStudioMetrics.viewerToolStripHeight
        return rect
    }

    func quickAdjustStrip(_ stage: CGRect) -> CGRect {
        CGRect(
            x: stage.minX,
            y: stage.maxY - VideoStudioMetrics.viewerToolStripHeight,
            width: stage.width,
            height: VideoStudioMetrics.viewerToolStripHeight
        )
    }

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
        VStack(spacing: 0) {
            // The column runs from the window's top edge; the toolbar's
            // trailing capsules sit over its head, so its content starts
            // at 80 (FS-12.03 §2).
            Color.clear.frame(height: VideoStudioDeskGeometry.inspectorContentTop)
            VideoStudioSheetHost(
                model: model,
                actions: actions(model),
                layout: .column,
                importedMusic: importedMusic,
                showsIdleLook: true,
                isDeskInspector: true,
                server: server,
                onServerExported: serverExported
            )
            // The selected item's ✕ · name · ✓, at the column's foot
            // (FS-12.03 §2). Export stays in the band: nothing has to make
            // way for it.
            if let title = model.selectionTitle {
                VideoSessionFooter(
                    title: title,
                    onCancel: { model.cancelSession() },
                    onCommit: { model.commitSession() },
                    height: VideoStudioDeskGeometry.inspectorFooterHeight,
                    buttonSize: VideoStudioDeskGeometry.deskFooterButton,
                    style: .desk
                )
                .padding(.leading, 1)
            }
        }
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .leading) {
            Rectangle().fill(EditorTheme.hairline).frame(width: 1)
        }
    }

    func mediaPool(_ model: VideoStudioModel, width: CGFloat) -> some View {
        VideoMediaPoolColumn(
            model: model,
            photoLibrary: dependencies.photoLibrary,
            width: width,
            importedMusic: importedMusic,
            onClose: { columns.isPoolOpen = false },
            onChooseSticker: { isStickerPickerPresented = true },
            onImportMusic: { isMusicImporterPresented = true },
            onAddSticker: { addSticker($0, to: model) },
            onAddText: { font in
                if let font { model.rememberFont(font) }
                addTextOverlay(model, font: font)
            }
        )
    }

    func deskTimeline(_ model: VideoStudioModel, height: CGFloat, zoomOverride: CGFloat? = nil) -> some View {
        VideoTimelineView(
            model: model,
            height: height,
            onAddOverlay: { addTextOverlay(model) },
            onAddMusic: { model.toggleToolPanel(.music) },
            onAddMedia: { addMedia(model) },
            onEditText: { editingOverlay = $0 },
            onTransition: { model.editingTransitionIndex = $0 },
            onVisibleDuration: { timelineVisibleDuration = $0 },
            zoomOverride: zoomOverride
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
