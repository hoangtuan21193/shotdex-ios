import AppKit
import ShotDexKit
import SwiftUI

/// The editor (board `MAC_Edit`, FS-18.03 §1): the photo on a dark canvas,
/// the inspector of 320 on the right, the filmstrip under it. Always dark,
/// chrome included (D10); the accent only on what commits.
struct MacEditorPage: View {
    @Bindable var model: MacEditorModel
    @Binding var showsInspector: Bool
    @Binding var zoom: MacViewerZoom
    @Binding var asksRevert: Bool
    /// ◀ and Esc: back to the viewer on the photo open.
    let close: (String) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if model.showsPresets {
                MacEditorPresetsPanel(model: model)
                Divider()
            }
            VStack(spacing: 0) {
                MacEditorCanvas(model: model, zoom: zoom)
                MacEditorFilmstrip(model: model)
            }
            if showsInspector {
                Divider()
                MacEditorInspector(model: model)
                    .frame(width: 320)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        // Popups and switches stay neutral here; the accent is for what commits (D10).
        .tint(MacTheme.Editor.label)
        .navigationTitle(model.details.fileName)
        .navigationSubtitle(MacEditorWords.subtitle(model))
        // The page's own toolbar: the window's is the grid's, not drawn while the editor is up.
        .toolbar {
            MacEditorToolbar(model: model, showsInspector: $showsInspector, zoom: $zoom, close: close, asksRevert: $asksRevert)
        }
        // In Crop, Esc puts the frame down and go back to Adjust;
        // nothing is undone — ⌘Z is there for that.
        .sheet(isPresented: $model.asksSync) { MacEditorSyncSheet(model: model, isPresented: $model.asksSync) }
        .onExitCommand {
            if model.isPickingColor { model.isPickingColor = false } else if !model.syncTargets.isEmpty { model.syncTargets = [] }
            else if model.tool != .adjust { model.tool = .adjust } else { leave() }
        }
        // Esc wherever the keys are (a checkbox, a menu just closed): the
        // eyedropper goes away, or Crop gives way to Adjust.
        .background {
            if model.tool != .adjust || model.isPickingColor || !model.syncTargets.isEmpty {
                Button("") {
                    if model.isPickingColor { model.isPickingColor = false } else if !model.syncTargets.isEmpty { model.syncTargets = [] }
                    else { model.tool = .adjust }
                }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
        }
        // Delete / ⌘⌫ removes the picked spot while healing (undoable; text fields keep their own Delete).
        .onDeleteCommand {
            if model.tool == .heal { model.deleteSelectedSpot() } else if model.tool == .mask { model.deleteSelectedMaskPart() }
        }
        .task { model.open() }
        // The frame is drawn over the fitted photo.
        .onChange(of: model.tool) { _, tool in if tool == .crop { zoom = .fit } }
        .onDisappear { model.flushSave() }
        // ⌘Q with an edit not written yet: written before the app goes.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.flushNow() }
    }

    private func leave() {
        model.flushSave()
        close(model.currentId)
    }
}

// MARK: - Toolbar

/// Sidebar · ◀ ▶ · title | Adjust · Crop · Mask · Heal · Markup | Undo ·
/// Redo · Before and After · Fit ▾ · Export · inspector · ✓ Edited · Saved ·
/// Revert to Original… (board `MAC_Edit`).
struct MacEditorToolbar: ToolbarContent {
    @Bindable var model: MacEditorModel
    @Binding var showsInspector: Bool
    @Binding var zoom: MacViewerZoom
    let close: (String) -> Void
    @Binding var asksRevert: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            // A plain button, not a toggle: an on toggle in the toolbar draws in the accent, kept for what commits.
            Button { model.showsPresets.toggle() } label: {
                Label(String(localized: "Presets and History", comment: "Mac editor toolbar: the left panel"), systemImage: "sidebar.left")
            }
            .accessibilityValue(model.showsPresets ? String(localized: "Shown", comment: "VoiceOver: a panel is shown")
                                                   : String(localized: "Hidden", comment: "VoiceOver: a panel is hidden"))
            .keyboardShortcut("p", modifiers: [.command, .option])
            .help(String(localized: "Presets and History (⌥⌘P)", comment: "Mac editor toolbar"))
            .accessibilityIdentifier("editor.presets")
            Button {
                model.flushSave()
                close(model.currentId)
            } label: {
                Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .help(String(localized: "Back to the photo (⌘[ or Esc)", comment: "Mac editor toolbar: leave the editor"))
            .accessibilityIdentifier("editor.back")
        }
        ToolbarItem(placement: .principal) {
            MacEditorTools(model: model)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: model.undo) { Label(String(localized: "Undo", comment: "Mac editor toolbar"), systemImage: "arrow.uturn.backward") }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!model.canUndo)
                .help(String(localized: "Undo (⌘Z)", comment: "Mac editor toolbar"))
                .accessibilityIdentifier("editor.undo")
            Button(action: model.redo) { Label(String(localized: "Redo", comment: "Mac editor toolbar"), systemImage: "arrow.uturn.forward") }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!model.canRedo)
                .help(String(localized: "Redo (⇧⌘Z)", comment: "Mac editor toolbar"))
                .accessibilityIdentifier("editor.redo")
            Toggle(isOn: $model.showsBefore) {
                Label(String(localized: "Before and After", comment: "Mac editor toolbar"), systemImage: "square.split.2x1")
            }
            .keyboardShortcut("\\", modifiers: [])
            .help(String(localized: "Show the original (\\)", comment: "Mac editor toolbar: Before and After"))
            .accessibilityIdentifier("editor.before")
            Menu {
                Picker(String(localized: "Zoom", comment: "Mac viewer toolbar: the zoom popup"), selection: $zoom) {
                    Text(MacViewerZoom.fit.title).tag(MacViewerZoom.fit)
                }
                .pickerStyle(.inline)
                // 1:1 needs a full-resolution render of the visible part: not yet.
                Button(MacViewerZoom.actual.title) {}.disabled(true)
            } label: {
                Text(zoom.title)
            }
            .fixedSize()
            .help(String(localized: "Zoom", comment: "Mac viewer toolbar: the zoom popup"))
            Button { showsInspector.toggle() } label: {
                Label(String(localized: "Inspector", comment: "Mac editor toolbar"), systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(String(localized: "Show or hide the adjustments (⌥⌘I)", comment: "Mac editor toolbar"))
            .accessibilityIdentifier("editor.inspector")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            MacEditorSaveStatus(state: model.saveState, retry: model.retrySave)
            Button(String(localized: "Revert to Original…", comment: "Mac editor toolbar: drop every edit of this photo")) {
                asksRevert = true
            }
            .disabled(model.recipe == .identity || model.load != .ready)
            .accessibilityIdentifier("editor.revert")
        }
    }
}

/// Adjust · Crop · Mask · Heal · Markup (316).
private struct MacEditorTools: View {
    @Bindable var model: MacEditorModel

    var body: some View {
        HStack(spacing: 2) {
            live(.adjust, String(localized: "Adjust", comment: "Mac editor tool"))
            live(.crop, String(localized: "Crop", comment: "Mac editor tool"))
            live(.mask, String(localized: "Mask", comment: "Mac editor tool"))
            live(.heal, String(localized: "Heal", comment: "Mac editor tool"))
            live(.markup, String(localized: "Markup", comment: "Mac editor tool"))
        }
        .padding(2)
        .background(MacTheme.Editor.glass, in: Capsule())
        .overlay(Capsule().strokeBorder(MacTheme.Editor.glassStroke))
        .frame(width: 316)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Tools", comment: "Mac editor: the tool switcher"))
    }

    private func live(_ tool: MacEditorModel.Tool, _ title: String) -> some View {
        let isOn = model.tool == tool
        return Button { model.tool = tool } label: {
            Text(title)
                .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? MacTheme.Editor.label : MacTheme.Editor.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(isOn ? MacTheme.Editor.pressed : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.load != .ready)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .accessibilityIdentifier("editor.tool.\(tool.rawValue)")
    }

}

private struct MacEditorSaveStatus: View {
    let state: MacEditorModel.SaveState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .unchanged:
            EmptyView()
        case .saving:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Saving…", comment: "Mac editor toolbar: the edit is being written").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        case .saved:
            Label(String(localized: "Edited · Saved", comment: "Mac editor toolbar: the edit is in the sidecar"), systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("editor.saved")
        case .failed:
            Button(action: retry) {
                Label(String(localized: "Couldn't Save — Try Again", comment: "Mac editor toolbar: the edit was not written; a click writes it again"),
                      systemImage: "exclamationmark.triangle")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(MacTheme.redText)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.retrySave")
        }
    }
}

// MARK: - Canvas

private struct MacEditorCanvas: View {
    let model: MacEditorModel
    let zoom: MacViewerZoom

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                switch model.load {
                case .loading:
                    ProgressView().controlSize(.small)
                case .unavailable(let reason):
                    VStack(spacing: 8) {
                        Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.secondary)
                        Text(reason).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 360)
                    }
                    .accessibilityElement(children: .combine)
                case .ready:
                    if model.renderFailed {
                        Text("ShotDex can't show this edit. Undo or change it to try again.", comment: "Mac editor: the render failed")
                            .font(.caption).padding(8)
                            .background(.black.opacity(0.7), in: Capsule())
                            .frame(maxHeight: .infinity, alignment: .top).padding(.top, 12)
                            .zIndex(1)
                    }
                    if let preview = model.preview {
                        let image = Image(decorative: preview, scale: 1)
                        Group {
                            if zoom == .actual {
                                ScrollView([.horizontal, .vertical]) {
                                    image.resizable().overlay { clipping }
                                        .accessibilityLabel(canvasLabel)
                                        // The original's size, whichever preview is up (a drag's is smaller).
                                        .frame(width: model.sourceSize.width / 2, height: model.sourceSize.height / 2)
                                }
                            } else {
                                let rect = Self.fitRect(preview, in: geometry.size)
                                ZStack(alignment: .topLeading) {
                                    image.resizable()
                                        .overlay { if model.tool != .crop { clipping } }
                                        .accessibilityLabel(canvasLabel)
                                        .frame(width: rect.width, height: rect.height)
                                        .offset(x: rect.minX, y: rect.minY)
                                    if model.tool == .crop, !model.showsBefore {
                                        MacEditorCropOverlay(model: model, imageRect: rect)
                                    } else if model.tool == .mask, !model.showsBefore {
                                        MacEditorMaskOverlay(model: model, imageRect: rect)
                                    } else if model.tool == .markup, !model.showsBefore {
                                        MacEditorMarkupOverlay(model: model, imageRect: rect)
                                    } else if model.tool == .heal, !model.showsBefore {
                                        MacEditorHealOverlay(model: model, imageRect: rect)
                                    } else if model.isPickingColor {
                                        MacEditorColorPicker(model: model, imageRect: rect)
                                    }
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                                .coordinateSpace(name: MacEditorCropOverlay.space)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if model.showsBefore {
                                Text("Original", comment: "Mac editor: Before and After shows the original")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.black.opacity(0.6), in: Capsule())
                                    .padding(40)
                            }
                        }

                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private var canvasLabel: String {
        model.showsBefore
            ? String(localized: "\(model.details.fileName), original", comment: "Mac editor canvas, VoiceOver")
            : String(localized: "\(model.details.fileName), edited", comment: "Mac editor canvas, VoiceOver")
    }

    /// The photo fitted in the canvas, 36 top · 35 sides · 28 bottom (board).
    static func fitRect(_ image: CGImage, in size: CGSize) -> CGRect {
        let area = CGRect(x: 35, y: 36, width: max(1, size.width - 70), height: max(1, size.height - 64))
        let scale = min(area.width / CGFloat(max(1, image.width)), area.height / CGFloat(max(1, image.height)))
        let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }

    @ViewBuilder
    private var clipping: some View {
        if let clipping = model.clipping, !model.showsBefore {
            Image(decorative: clipping, scale: 1).resizable().allowsHitTesting(false)
        }
    }
}

// MARK: - Filmstrip

/// 84×56 tiles, the photo open in a white ring, edited ones badged; "3 of 48".
private struct MacEditorFilmstrip: View {
    let model: MacEditorModel

    var body: some View {
        HStack(spacing: 12) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(model.ids.indices, id: \.self) { index in
                            let id = model.ids[index]
                            Button {
                                // ⌘-click picks photos to sync to, Shift-click a run of them; a plain click opens.
                                let flags = NSEvent.modifierFlags
                                if flags.contains(.command) || flags.contains(.shift) {
                                    model.toggleSyncTarget(at: index, extending: flags.contains(.shift))
                                } else {
                                    model.open(at: index)
                                }
                            } label: {
                                let isTarget = model.syncTargets.contains(id)
                                MacEditorStripTile(photoId: id)
                                    .frame(width: 84, height: 56)
                                    // While syncing is set up, the photos left out step back.
                                    .overlay { if !model.syncTargets.isEmpty, !isTarget, index != model.index { Color.black.opacity(0.28) } }
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(index == model.index ? Color.white : isTarget ? MacTheme.Editor.accent : Color.clear,
                                                      lineWidth: index == model.index && !model.syncTargets.isEmpty ? 3 : 2))
                                    .overlay(alignment: .bottomTrailing) {
                                        if model.failedIds.contains(id) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(MacTheme.redText)
                                                .frame(width: 16, height: 16)
                                                .background(.black.opacity(0.6), in: Circle())
                                                .padding(4)
                                                .accessibilityLabel(String(localized: "Not saved", comment: "Mac editor filmstrip: a photo whose edit failed to save"))
                                        } else if model.editedIds.contains(id) {
                                            Image(systemName: "slider.horizontal.3")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 16, height: 16)
                                                .background(.black.opacity(0.6), in: Circle())
                                                .padding(4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            // While a sync writes, the photos stay put: opening one now would read it half-done.
                            .disabled(model.isSyncing)
                            .accessibilityAction(named: model.syncTargets.contains(id)
                                                 ? String(localized: "Remove from Sync", comment: "Mac editor filmstrip, VoiceOver action")
                                                 : String(localized: "Add to Sync", comment: "Mac editor filmstrip, VoiceOver action")) {
                                model.toggleSyncTarget(at: index, extending: false)
                            }
                            .help(String(localized: "Click to edit · ⌘-click to pick for a sync · ⇧-click for a run", comment: "Mac editor filmstrip tile tooltip"))
                            .id(id)
                            .accessibilityLabel(String(localized: "Photo \(index + 1)", comment: "Mac editor filmstrip tile, VoiceOver"))
                            .accessibilityValue(model.editedIds.contains(id) ? String(localized: "Edited", comment: "Mac editor filmstrip tile, VoiceOver") : "")
                            .accessibilityAddTraits(index == model.index ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .onAppear { proxy.scrollTo(model.currentId, anchor: .center) }
                .onChange(of: model.index) { withAnimation { proxy.scrollTo(model.currentId, anchor: .center) } }
            }
            if let progress = model.syncProgress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Syncing \(progress.done.formatted()) of \(progress.total.formatted())…", comment: "Mac editor filmstrip: a sync running")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.trailing, 16)
                .accessibilityIdentifier("editor.sync.progress")
            } else if model.syncTargets.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(localized: "\((model.index + 1).formatted()) of \(model.ids.count.formatted())", comment: "Mac editor filmstrip: position"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let note = model.syncNote {
                        Text(note).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                            .frame(maxWidth: 220, alignment: .trailing)
                            .accessibilityIdentifier("editor.sync.note")
                    }
                }
                .padding(.trailing, 16)
            } else {
                VStack(alignment: .trailing, spacing: 4) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\((model.syncTargets.count + 1).formatted()) selected", comment: "Mac editor filmstrip: photos picked for a sync, the open one included")
                            .font(.system(size: 12, weight: .semibold))
                        Text("of \(model.ids.count.formatted())", comment: "Mac editor filmstrip: of how many").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .monospacedDigit()
                    HStack(spacing: 6) {
                        Button(String(localized: "Clear", comment: "Mac editor filmstrip: drop the sync picks")) { model.syncTargets = [] }
                            .controlSize(.small)
                            .accessibilityIdentifier("editor.sync.clear")
                        Button(String(localized: "Sync \(model.syncTargets.count)…", comment: "Mac editor filmstrip: open the sync sheet")) { model.asksSync = true }
                            .disabled(model.isSyncing)
                            .controlSize(.small)
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .help(String(localized: "Sync this photo's edit to the selected photos (⇧⌘S)", comment: "Mac editor filmstrip"))
                            .accessibilityIdentifier("editor.sync.open")
                    }
                }
                .padding(.trailing, 16)
            }
        }
        .frame(height: 84)
        .background(MacTheme.Editor.panelSolid)
        .overlay(alignment: .top) { Rectangle().fill(MacTheme.Editor.hairline).frame(height: 1) }
    }
}

/// A strip tile: the demo's picture, a file photo's thumbnail, or Photos'.
private struct MacEditorStripTile: View {
    let photoId: String
    @Environment(MacDependencies.self) private var dependencies
    @State private var image: CGImage?
    @State private var tried = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFill()
            } else if tried {
                MacAssetCover(assetId: photoId, side: 168)
            } else {
                MacTheme.fill2
            }
        }
        .task(id: photoId) {
            if let picture = MacRootWindow.demoPicture?(photoId) { image = picture; tried = true; return }
            let thumbnails = dependencies.photoLibrary.fileThumbnails, id = photoId
            let found = await Task.detached(priority: .utility) {
                thumbnails.image(for: id)?.cgImage(forProposedRect: nil, context: nil, hints: nil).map(StripImage.init)
            }.value
            image = found?.image
            tried = true
        }
    }
}

private struct StripImage: @unchecked Sendable {
    let image: CGImage
}

// MARK: - Words

enum MacEditorWords {
    /// "2026 Japan · Fujifilm X-T5 · XF56mmF1.2 R WR · 3 of 48".
    @MainActor
    static func subtitle(_ model: MacEditorModel) -> String {
        if !model.syncTargets.isEmpty {
            return ([String(localized: "\((model.syncTargets.count + 1).formatted()) of \(model.ids.count.formatted()) selected",
                            comment: "Mac editor subtitle while photos are picked for a sync"),
                     model.details.camera, model.details.lens].compactMap { $0 }).joined(separator: " · ")
        }
        if let name = model.previewName {
            return String(localized: "Previewing “\(name)” · \((model.index + 1).formatted()) of \(model.ids.count.formatted())",
                          comment: "Mac editor: the subtitle while a look is under the pointer")
        }
        return [model.details.sourceName, model.details.camera, model.details.lens,
         String(localized: "\((model.index + 1).formatted()) of \(model.ids.count.formatted())", comment: "Mac editor: position in the strip")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
