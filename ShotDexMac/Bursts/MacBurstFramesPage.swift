import AppKit
import SwiftUI

/// Image › Choose Frames… (board `MAC_BurstFrames`): Single or Survey (the
/// current frame and the three after it, zoom and position synced), the
/// strip of every frame at the foot, Keep N, remove M and Done.
struct MacBurstFramesPage: View {
    @Bindable var model: MacBurstFramesModel
    let close: () -> Void
    @State private var keyMonitor: Any?
    @State private var asksDiscard = false

    /// Done, Esc: picks not acted on are asked about; nothing else is lost.
    private func finish() {
        if model.hasUnusedPicks { asksDiscard = true } else { close() }
    }

    private func watchKeys() {
        guard keyMonitor == nil else { return }
        let model = model
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.numericPad, .function]).isEmpty,
                  event.window?.attachedSheet == nil else { return event }
            let responder = event.window?.firstResponder
            if responder is NSTextView { return event }
            switch event.keyCode {
            case 123: model.previous()
            case 124: model.next()
            // A focused Keep box keeps its own Space.
            case 49 where !(responder is NSButton): model.toggleKeepCurrent()
            default: return event
            }
            return nil
        }
    }

    private func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    ContentUnavailableView(String(localized: "Not a Burst Any More", comment: "Mac Choose Frames: fewer than two frames"),
                                           systemImage: "square.stack.3d.down.right",
                                           description: Text("This burst has fewer than two frames ShotDex can see. Go back to the library.", comment: "Mac Choose Frames: empty"))
                case .ready:
                    stage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.phase != .empty {
                Divider()
                MacBurstStrip(model: model)
            }
        }
        .navigationTitle(String(localized: "Choose Frames", comment: "Mac Choose Frames: the page title"))
        .navigationSubtitle(model.subtitle)
        .toolbar { toolbar }
        .task { if model.phase == .loading { await model.load() } }
        // Esc leaves (Done). ← → and Space go through a key watcher that
        // leaves them to a focused control (a Keep box keeps its own Space).
        .background {
            Button("", action: finish).keyboardShortcut(.cancelAction)
                .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
        .onAppear(perform: watchKeys)
        .confirmationDialog(String(localized: "Leave without removing frames?", comment: "Mac Choose Frames: leaving with picks"),
                            isPresented: $asksDiscard) {
            Button(String(localized: "Leave", comment: "Mac Choose Frames: leave, keeping every frame"), role: .destructive, action: close)
            Button(String(localized: "Keep Choosing", comment: "Mac Choose Frames: stay"), role: .cancel) {}
        } message: {
            Text("Your picks aren’t saved — every frame stays in the burst. To keep only your picks, use Keep and Remove.",
                 comment: "Mac Choose Frames: what leaving does")
        }
        .onDisappear(perform: stopWatchingKeys)
    }

    @ViewBuilder
    private var stage: some View {
        switch model.layout {
        case .single:
            if let current = model.selection.current {
                MacBurstFrameView(model: model, id: current.id, index: model.selection.currentIndex)
                    .padding(16)
            }
        case .survey:
            // (index, id) read once: a delete shrinks the frames under a stale index.
            let frames = model.selection.frames
            let shown = model.surveyIndices.filter { frames.indices.contains($0) }.map { (index: $0, id: frames[$0].id) }
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                ForEach(Array(stride(from: 0, to: shown.count, by: 2)), id: \.self) { row in
                    GridRow {
                        ForEach(shown[row..<min(row + 2, shown.count)], id: \.id) { frame in
                            MacBurstFrameView(model: model, id: frame.id, index: frame.index)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: close) { Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left") }
                .keyboardShortcut("[", modifiers: .command)
                .help(String(localized: "Back (⌘[ or Esc)", comment: "Mac Choose Frames toolbar"))
                .accessibilityIdentifier("burst.back")
        }
        ToolbarItem(placement: .primaryAction) {
            Picker(String(localized: "Layout", comment: "Mac Choose Frames toolbar"), selection: $model.layout) {
                ForEach(MacBurstFramesModel.Layout.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .help(String(localized: "One frame, or four side by side · ← → move between frames", comment: "Mac Choose Frames toolbar"))
            .accessibilityIdentifier("burst.layout")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Picker(selection: $model.zoom) {
                    ForEach(MacBurstFramesModel.Zoom.allCases) { Text($0.title).tag($0) }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } label: {
                Text("Zoom: \(model.zoom.title)", comment: "Mac Choose Frames toolbar: the zoom menu")
            }
            .help(String(localized: "Zoom, the same on every frame", comment: "Mac Choose Frames toolbar"))
            .accessibilityLabel(String(localized: "Zoom", comment: "Mac Choose Frames toolbar"))
            .accessibilityIdentifier("burst.zoom")
            Button(action: model.zoomToFace) {
                Label(String(localized: "Zoom to Face", comment: "Mac Choose Frames toolbar"), systemImage: "viewfinder")
            }
            .disabled(model.selection.current.flatMap { model.faceRect(for: $0.id) } == nil)
            .help(String(localized: "Zoom to the face in this frame", comment: "Mac Choose Frames toolbar"))
            .accessibilityIdentifier("burst.face")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button(role: .destructive) {
                Task { await model.deleteUnkept() }
            } label: {
                Label(model.selection.deleteTitle, systemImage: "trash").labelStyle(.titleAndIcon)
                    .foregroundStyle(model.selection.canDelete ? MacTheme.redText : Color.secondary)
            }
            .disabled(!model.selection.canDelete || model.isDeleting)
            .help(model.selection.deleteFootnote)
            .accessibilityIdentifier("burst.delete")
            Button(String(localized: "Done", comment: "Mac Choose Frames toolbar: leave"), action: finish)
                .keyboardShortcut(.return, modifiers: .command)
                .help(String(localized: "Leave without removing anything (⌘↩)", comment: "Mac Choose Frames toolbar"))
                .buttonStyle(MacPushButtonStyle(isDefault: true, isToolbarCommand: true))
                .accessibilityIdentifier("burst.done")
        }
    }
}

/// One frame with its chips, caption and Keep box. Clicking it shows it
/// (Survey) or keeps it (Single, as on iPhone); dragging moves the zoomed
/// view of every frame together.
private struct MacBurstFrameView: View {
    @Bindable var model: MacBurstFramesModel
    let id: String
    let index: Int
    @State private var dragStart: CGPoint?

    var body: some View {
        let isCurrent = index == model.selection.currentIndex
        let isKept = model.selection.isKept(id)
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(0.04)
                    if let picture = model.pictures[id] {
                        picturePlaced(picture, in: geometry.size)
                    }
                    HStack(spacing: 6) {
                        if model.selection.frames.indices.contains(index), model.selection.frames[index].isSuggested {
                            chip(BurstSelection.suggestedTitle)
                        }
                        ForEach(model.chips(for: id), id: \.self) { chip($0) }
                    }
                    .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 6).inset(by: -4)
                        .strokeBorder(isCurrent && model.layout == .survey ? MacTheme.accent : .clear, lineWidth: 2)
                }
                .contentShape(Rectangle())
                .gesture(panGesture(size: geometry.size))
                // Showing a frame never changes the picks: Keep (or Space) does.
                .onTapGesture { if model.layout == .survey { model.show(index) } }
                .overlay(alignment: .topTrailing) {
                    if isKept {
                        Label(String(localized: "Kept", comment: "Mac Choose Frames: a kept frame"), systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(MacTheme.onAccentFill)
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(MacTheme.accentFill, in: Capsule())
                            .padding(10)
                    }
                }
            }
            .onAppear { model.loadPicture(id, big: true) }
            .onChange(of: id) { model.loadPicture(id, big: true) }
            HStack(spacing: 8) {
                Text("Frame \(index + 1) of \(model.selection.count)", comment: "Mac Choose Frames: a frame's caption")
                    .font(.system(size: 13, weight: .semibold))
                Text(detailText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                Toggle(String(localized: "Keep", comment: "Mac Choose Frames: keep this frame"), isOn: Binding(
                    get: { isKept }, set: { _ in model.toggleKeep(id) }))
                    .toggleStyle(.checkbox)
                    .help(String(localized: "Keep this frame (Space keeps the frame you're on)", comment: "Mac Choose Frames: the Keep box"))
                    .disabled(model.isDeleting)
                    .accessibilityIdentifier("burst.keep.\(index + 1)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.selection.accessibilityLabel(at: index))
    }

    /// "IMG_5308.HEIC · 1/500 s · 6.0 s later".
    private var detailText: String {
        guard let detail = model.details[id] else { return "" }
        var parts = [detail.name]
        if let shutter = detail.shutter { parts.append("\(shutter) s") }
        if let offset = detail.offset, offset > 0 {
            parts.append(offset < 60
                         ? String(localized: "\(offset.formatted(.number.precision(.fractionLength(1)))) s later", comment: "Mac Choose Frames: time after the first frame")
                         : String(localized: "\(MacBurstFramesModel.duration(offset)) later", comment: "Mac Choose Frames: time after the first frame, long"))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func picturePlaced(_ picture: CGImage, in box: CGSize) -> some View {
        let size = CGSize(width: picture.width, height: picture.height)
        if let factor = model.zoom.factor, size.width > 0, size.height > 0 {
            // Filling the box (× the factor), placed so the shared focus sits
            // in the middle of the box.
            let scale = max(box.width / size.width, box.height / size.height) * factor
            let shown = CGSize(width: size.width * scale, height: size.height * scale)
            // Kept inside the frame at this zoom too (a position dragged at 2× may be off the edge at Fill Frame).
            let halfX = min(0.5, box.width / 2 / shown.width), halfY = min(0.5, box.height / 2 / shown.height)
            let focusX = min(max(model.focus.x, halfX), 1 - halfX), focusY = min(max(model.focus.y, halfY), 1 - halfY)
            Image(decorative: picture, scale: 1).resizable()
                .frame(width: shown.width, height: shown.height)
                .offset(x: box.width / 2 - focusX * shown.width, y: box.height / 2 - focusY * shown.height)
        } else {
            Image(decorative: picture, scale: 1).resizable().scaledToFit()
                .frame(width: box.width, height: box.height)
        }
    }

    /// Drag at a zoom: every frame's view moves together (the focus is shared).
    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard let factor = model.zoom.factor, let picture = model.pictures[id], picture.width > 0, picture.height > 0 else { return }
                let start = dragStart ?? model.focus
                if dragStart == nil { dragStart = start }
                let scale = max(size.width / CGFloat(picture.width), size.height / CGFloat(picture.height)) * factor
                let shown = CGSize(width: CGFloat(picture.width) * scale, height: CGFloat(picture.height) * scale)
                // Clamped so the frame always covers its box (no blank edge).
                let halfX = min(0.5, size.width / 2 / shown.width), halfY = min(0.5, size.height / 2 / shown.height)
                model.focus = CGPoint(x: min(max(start.x - value.translation.width / shown.width, halfX), 1 - halfX),
                                      y: min(max(start.y - value.translation.height / shown.height, halfY), 1 - halfY))
            }
            .onEnded { _ in dragStart = nil }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8).frame(height: 20)
            .background(MacTheme.hudFill, in: Capsule())
    }
}

/// Every frame in capture order: the current one ringed, kept ones ticked,
/// weak ones dotted red; the counts on the right.
private struct MacBurstStrip: View {
    @Bindable var model: MacBurstFramesModel

    var body: some View {
        HStack(spacing: 16) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 4) {
                        ForEach(Array(model.selection.frames.enumerated()), id: \.element.id) { index, frame in
                            thumb(frame.id, index: index)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.leading, 16)
                }
                .onChange(of: model.selection.currentIndex) { _, index in
                    if model.selection.frames.indices.contains(index) {
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(model.selection.frames[index].id, anchor: .center) }
                    }
                }
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text(MacInflect.string("\(model.keptIds.count) kept · ^[\(model.selection.deleteIds.count) frame](inflect: true) to remove",
                                       comment: "Mac Choose Frames: the counts"))
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    .accessibilityIdentifier("burst.counts")
                Text(note).font(.system(size: 11)).foregroundStyle(model.note == nil ? Color.secondary : Color.primary)
                    .multilineTextAlignment(.trailing).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("burst.note")
                if model.selection.hasSuggestions {
                    Button(String(localized: "Keep Only Suggested", comment: "Mac Choose Frames: keep Photos' suggested frames")) {
                        model.keepOnlySuggested()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .accessibilityIdentifier("burst.keepSuggested")
                }
            }
            .frame(width: 320, alignment: .trailing)
            .padding(.trailing, 16)
        }
        .frame(height: 80)
    }

    /// "Zoom synced at 100% · 6 weak frames", or the last delete's result.
    private var note: String {
        if let note = model.note { return note }
        if let limited = model.limitedNote { return limited }
        // Where removed frames go, first: it is what reassures before Keep and Remove.
        var parts = [model.selection.deleteFootnote]
        if model.zoom != .fit {
            parts.append(String(localized: "Zoom synced (\(model.zoom.title))", comment: "Mac Choose Frames: every frame shares the zoom and position"))
        }
        if model.weakCount > 0 {
            parts.append(MacInflect.string("^[\(model.weakCount) weak frame](inflect: true)", comment: "Mac Choose Frames: frames the scoring found weak"))
        }
        return parts.joined(separator: " · ")
    }

    private func thumb(_ id: String, index: Int) -> some View {
        let isCurrent = index == model.selection.currentIndex
        let isKept = model.selection.isKept(id)
        return ZStack(alignment: .topTrailing) {
            Group {
                if let picture = model.thumbnails[id] {
                    Image(decorative: picture, scale: 1).resizable().scaledToFill()
                } else {
                    MacTheme.fill2
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            if model.isWeak(id) {
                Circle().fill(Color.red).frame(width: 8, height: 8).overlay(Circle().strokeBorder(.white, lineWidth: 1)).padding(3)
            }
            if isKept {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14)).foregroundStyle(.white, MacTheme.accentFill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(3)
            }
        }
        .frame(width: 56, height: 56)
        .overlay(RoundedRectangle(cornerRadius: 4).inset(by: -2).strokeBorder(isCurrent ? MacTheme.accent : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { model.show(index) }
        .help(String(localized: "Show this frame · Space keeps it", comment: "Mac Choose Frames: a strip thumbnail"))
        .onAppear { model.loadPicture(id, big: false) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.selection.accessibilityLabel(at: index))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("burst.frame.\(index + 1)")
    }
}
