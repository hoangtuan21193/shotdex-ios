import AVFoundation
import AppKit
import SwiftUI
import os

/// FS-24 §10 Compare Videos on the Mac (board `MAC_VideoCompare`): in the
/// Compress Videos window, in place of its list (`mac-few-windows`) — `‹`
/// goes back. The original (A) and the copy (B) side by side on one
/// transport; trackpad pinch or ⌘-scroll zooms both to the same spot, a drag
/// pans both, a double-click toggles fit ↔ 3×; holding Option swaps them.
struct MacVideoComparePage: View {
    @Bindable var model: VideoCompareModel
    let close: () -> Void
    @State private var scale: CGFloat = 1
    /// Pan, from the pane's centre, in points of the pane.
    @State private var offset: CGSize = .zero
    @State private var gestureStart: (scale: CGFloat, offset: CGSize)?
    @State private var paneSize: CGSize = .zero
    @State private var isOptionHeld = false
    @State private var monitors: [Any] = []
    @State private var scrubTime: Double?

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                pane(slot: 0)
                pane(slot: 1)
            }
            .overlay { if model.isLoading { ProgressView().controlSize(.small) } }
            transport
                .frame(maxWidth: 720)
            Text(VideoCompressionCopy.compareHintMac)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Editor.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .navigationTitle(model.currentPair.map { model.batch.filename(of: $0.id) } ?? "")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .background { keys }
        .task {
            model.loadCurrent()
            #if DEBUG
            // `-ShotDexCompareZoom 2.5`: open zoomed on the sign, for the board's shot.
            let arguments = ProcessInfo.processInfo.arguments
            if let index = arguments.firstIndex(of: "-ShotDexCompareZoom"), index + 1 < arguments.count,
               let value = Double(arguments[index + 1]) {
                try? await Task.sleep(for: .seconds(1))
                let zoomed = VideoCompareRules.zoom(scale: 1, offset: .zero, to: value,
                                                    about: CGPoint(x: 0, y: -paneSize.height * 0.15), paneSize: paneSize)
                scale = zoomed.scale
                offset = zoomed.offset
            }
            if arguments.contains("-ShotDexCompareKeys") {
                await MacVideoCompressPage.replayKeys(model: model)
            }
            #endif
        }
        .onAppear(perform: startMonitors)
        .onDisappear {
            #if DEBUG
            Logger(subsystem: "com.hoangtuan.shotdex", category: "compareKeys").notice("compare closed")
            #endif
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            model.pause()
        }
        .onChange(of: model.currentID) { _, _ in resetZoom() }
        .onChange(of: model.isEmpty) { _, empty in if empty { close() } }
    }

    private var subtitle: String {
        guard let index = model.currentIndex, let pair = model.currentPair else { return "" }
        return "\(VideoCompressionCopy.position(index, of: model.pairs.count)) · \(VideoCompressionCopy.saved(pair.savedBytes))"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: close) {
                Label(String(localized: "Back", comment: "Mac toolbar"), systemImage: "chevron.left")
            }
            .keyboardShortcut("[", modifiers: .command)
            .accessibilityIdentifier("videoCompare.back")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button { model.stepVideo(-1) } label: { Label(VideoCompressionCopy.previousVideo, systemImage: "chevron.left") }
                    .disabled(!model.canStepBack)
                Button { model.stepVideo(1) } label: { Label(VideoCompressionCopy.nextVideo, systemImage: "chevron.right") }
                    .disabled(!model.canStepForward)
            }
            Button(role: .destructive) {
                Task { await model.deleteCurrentOriginal() }
            } label: {
                Label(VideoCompressionCopy.deleteOriginal, systemImage: "trash")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.red)
            }
            .disabled(model.isDeleting || model.currentPair == nil)
            .help("\(VideoCompressionCopy.deleteOriginal) (⌘⌫)")
            .accessibilityIdentifier("videoCompare.deleteOriginal")
        }
    }

    // MARK: Panes

    private func shownSlot(_ slot: Int) -> Int { isOptionHeld ? 1 - slot : slot }

    private func pane(slot: Int) -> some View {
        let shown = shownSlot(slot)
        return MacZoomedPlayerView(player: shown == 0 ? model.original : model.copy, scale: scale, offset: offset)
            .aspectRatio(model.videoAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onGeometryChange(for: CGSize.self) { $0.size } action: { paneSize = $0 }
            .overlay(alignment: .topLeading) { label(shown).padding(8) }
            .overlay(alignment: .topTrailing) {
                if scale > 1.01 {
                    Text("\(Double(scale).formatted(.number.precision(.fractionLength(0...1))))×")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(8)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = gestureStart ?? (scale, offset)
                        gestureStart = start
                        let point = CGPoint(x: value.startLocation.x - paneSize.width / 2,
                                            y: value.startLocation.y - paneSize.height / 2)
                        let zoomed = VideoCompareRules.zoom(scale: start.scale, offset: start.offset,
                                                            to: start.scale * value.magnification,
                                                            about: point, paneSize: paneSize)
                        scale = zoomed.scale
                        offset = zoomed.offset
                    }
                    .onEnded { _ in gestureStart = nil }
                    .simultaneously(with: DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let start = gestureStart ?? (scale, offset)
                            gestureStart = start
                            offset = VideoCompareRules.clampedOffset(
                                CGSize(width: start.offset.width + value.translation.width,
                                       height: start.offset.height + value.translation.height),
                                scale: scale, paneSize: paneSize)
                        }
                        .onEnded { _ in gestureStart = nil })
            )
            .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                if scale > 1.01 {
                    resetZoom()
                } else {
                    let point = CGPoint(x: value.location.x - paneSize.width / 2, y: value.location.y - paneSize.height / 2)
                    let zoomed = VideoCompareRules.zoom(scale: 1, offset: .zero, to: VideoCompareRules.doubleTapZoom,
                                                        about: point, paneSize: paneSize)
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = zoomed.scale
                        offset = zoomed.offset
                    }
                }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text(for: shown))
    }

    private func text(for slot: Int) -> String {
        guard let pair = model.currentPair else { return "" }
        return slot == 0
            ? VideoCompressionCopy.originalLabel(bytes: pair.originalBytes, codec: model.originalCodec)
            : VideoCompressionCopy.copyLabel(pair)
    }

    private func label(_ slot: Int) -> some View {
        HStack(spacing: 6) {
            Text(slot == 0 ? "A" : "B")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.white))
            Text(text(for: slot))
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(height: 24)
        .background(Color.black.opacity(0.55), in: Capsule())
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            scale = 1
            offset = .zero
        }
    }

    // MARK: Transport

    private var transport: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(VideoCompressionCopy.time(scrubTime ?? model.currentTime))
                Slider(value: Binding(get: { scrubTime ?? model.currentTime },
                                      set: { value in
                                          scrubTime = value
                                          model.scrub(to: value, isFinal: false)
                                      }),
                       in: 0...max(model.duration, 0.01),
                       onEditingChanged: { editing in
                           if !editing, let value = scrubTime {
                               model.scrub(to: value, isFinal: true)
                               scrubTime = nil
                           }
                       })
                Text(VideoCompressionCopy.time(model.duration))
            }
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(MacTheme.Editor.secondaryText)
            HStack(spacing: 24) {
                Button { model.stepFrame(-1) } label: { Image(systemName: "backward.frame.fill") }
                    .help(VideoCompressionCopy.previousFrame)
                    .accessibilityLabel(VideoCompressionCopy.previousFrame)
                Button(action: model.togglePlay) {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                        .contentShape(Circle())
                }
                .accessibilityLabel(model.isPlaying ? VideoCompressionCopy.pause : VideoCompressionCopy.play)
                Button { model.stepFrame(1) } label: { Image(systemName: "forward.frame.fill") }
                    .help(VideoCompressionCopy.nextFrame)
                    .accessibilityLabel(VideoCompressionCopy.nextFrame)
                Button { model.isMuted.toggle() } label: {
                    Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(model.isMuted ? VideoCompressionCopy.soundOn : VideoCompressionCopy.soundOff)
            }
            .buttonStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(.white)
            .disabled(model.isLoading)
        }
    }

    // MARK: Keys, Option, ⌘-scroll

    private var keys: some View {
        Group {
            Button(VideoCompressionCopy.play) { model.togglePlay() }
                .keyboardShortcut(.space, modifiers: [])
            Button(VideoCompressionCopy.previousFrame) { model.stepFrame(-1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button(VideoCompressionCopy.nextFrame) { model.stepFrame(1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button(VideoCompressionCopy.previousVideo) { model.stepVideo(-1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button(VideoCompressionCopy.nextVideo) { model.stepVideo(1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            // Esc lives here: `onExitCommand` needs a focused view the panes
            // do not give (AC-24.22, `-ShotDexCompareKeys`). ⌘⌫ is the key
            // monitor in `startMonitors`.
            Button(String(localized: "Back", comment: "Mac toolbar"), action: close)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func startMonitors() {
        guard monitors.isEmpty else { return }
        if let flags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { event in
            isOptionHeld = event.modifierFlags.contains(.option)
            return event
        }) { monitors.append(flags) }
        // ⌘⌫ is Delete Original here. The menu's Move to Trash claims ⌘⌫
        // app-wide, and a monitor runs before any key equivalent (AC-24.22).
        if let delete = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 51,
                  event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  model.currentPair != nil, !model.isDeleting else { return event }
            Task { await model.deleteCurrentOriginal() }
            return nil
        }) { monitors.append(delete) }
        if let wheel = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { event in
            guard event.modifierFlags.contains(.command), paneSize.width > 0 else { return event }
            let factor = 1 + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
            let zoomed = VideoCompareRules.zoom(scale: scale, offset: offset, to: scale * factor,
                                                about: .zero, paneSize: paneSize)
            scale = zoomed.scale
            offset = zoomed.offset
            return nil
        }) { monitors.append(wheel) }
    }
}

/// A player's picture scaled and moved inside a fixed frame: the layer is
/// laid out larger than the view (no view transform, which AppKit draws
/// poorly), so both panes zoom by the same numbers.
struct MacZoomedPlayerView: NSViewRepresentable {
    let player: AVPlayer
    let scale: CGFloat
    let offset: CGSize

    func makeNSView(context: Context) -> ZoomView {
        let view = ZoomView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: ZoomView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        view.scale = scale
        view.offset = offset
        view.needsLayout = true
    }

    final class ZoomView: NSView {
        let playerLayer = AVPlayerLayer()
        var scale: CGFloat = 1
        var offset: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspect
            layer?.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            // AppKit's y runs up; the offset is in SwiftUI's, which runs down.
            playerLayer.frame = CGRect(x: bounds.midX - size.width / 2 + offset.width,
                                       y: bounds.midY - size.height / 2 - offset.height,
                                       width: size.width, height: size.height)
            CATransaction.commit()
        }
    }
}
