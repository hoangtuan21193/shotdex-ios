import AVFoundation
import Photos
import SwiftUI

/// Payload for the trim cover. Carries the asset outright, per the rule that a
/// `fullScreenCover(item:)` never reads state from outside itself.
struct VideoTrimPresentation: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

/// Trims a video down to one range and writes it back over the original.
///
/// A tier-D tool: it works directly on frames, so it takes the whole screen on
/// a black ground, with Cancel and Save in the top bar.
struct VideoTrimScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let asset: PHAsset
    /// Called after a successful write, so the viewer can reload the clip.
    var onTrimmed: () -> Void = {}

    @State private var model = VideoTrimModel()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            stage
            panel
        }
        .background(EditorTheme.background)
        .preferredColorScheme(.dark)
        .task { await model.load(asset: asset, photoLibrary: photoLibrary) }
        .onDisappear { model.tearDown() }
        .alert(
            "Couldn’t Trim",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            ),
            presenting: model.errorMessage
        ) { _ in
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .foregroundStyle(.white)
            Spacer()
            Text("Trim")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Button("Save") {
                Task {
                    if await model.save(asset: asset) {
                        onTrimmed()
                        dismiss()
                    }
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(model.canSave ? EditorTheme.accent : EditorTheme.dimText)
            .disabled(!model.canSave)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EditorTheme.hairline).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var stage: some View {
        ZStack {
            Color.black
            if let player = model.player {
                TrimPlayerView(player: player)
            } else {
                ProgressView().tint(.white)
            }
            if model.isSaving {
                // A trim writes over the original, so the screen locks until
                // PhotoKit has answered — the same rule the batch tools follow.
                Color.black.opacity(0.6)
                ProgressView("Saving…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { model.togglePlayPause() }
        .disabled(model.isSaving)
    }

    private var panel: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    model.togglePlayPause()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(model.selectionLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(EditorTheme.secondaryText)

                Spacer()

                Button("Reset") { model.reset() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(model.isTrimmed ? .white : EditorTheme.dimText)
                    .frame(width: 44, height: 44)
                    .disabled(!model.isTrimmed)
            }

            VideoTrimStrip(model: model)
                .frame(height: 56)

            Text("The original stays in your library. Revert in Photos brings the whole clip back.")
                .font(.caption2)
                .foregroundStyle(EditorTheme.dimText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) {
            Rectangle().fill(EditorTheme.panelTopHairline).frame(height: 0.5)
        }
        .disabled(model.isSaving)
    }
}

/// The strip: thumbnails across the clip, a bright window over the kept range,
/// dimmed ends, and a handle at each edge.
private struct VideoTrimStrip: View {
    @Bindable var model: VideoTrimModel

    /// Wide enough to grab with a thumb without swallowing the frames beside
    /// it. Photos uses about the same.
    private let handleWidth: CGFloat = 16

    /// The strip's own coordinate space. A `DragGesture` reports its location
    /// relative to the view it is attached to, and every position here only
    /// means something measured against the full strip.
    private static let space = "VideoTrimStrip"

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let startX = model.position(of: model.start, in: width)
            let endX = model.position(of: model.end, in: width)

            ZStack(alignment: .leading) {
                filmstrip
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                // Everything outside the kept range reads as discarded.
                Color.black.opacity(0.6)
                    .frame(width: max(0, startX))
                Color.black.opacity(0.6)
                    .frame(width: max(0, width - endX))
                    .offset(x: endX)

                RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                    .stroke(EditorTheme.accent, lineWidth: 3)
                    .frame(width: max(handleWidth * 2, endX - startX))
                    .offset(x: startX)

                // The playhead, so the frame on screen has a place on the strip.
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
                    .offset(x: model.position(of: model.currentTime, in: width) - 1)
                    .opacity(model.duration > 0 ? 1 : 0)

                handle(at: startX, isStart: true)
                handle(at: endX - handleWidth, isStart: false)
            }
            .coordinateSpace(name: Self.space)
            // One gesture for the whole strip rather than one per handle.
            //
            // Per-handle gestures did not fire at all: a 16pt bar positioned
            // with `.offset` is a hit target SwiftUI would not reliably find,
            // and widening it with `contentShape` did not help. Deciding which
            // handle to move from where the finger lands is also the better
            // interaction — there is no small target to hit, and the nearer
            // handle is always the one the user meant.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { value in
                        model.dragHandle(
                            toX: value.location.x,
                            from: value.startLocation.x,
                            width: width
                        )
                    }
                    .onEnded { _ in model.endHandleDrag() }
            )
        }
    }

    private var filmstrip: some View {
        HStack(spacing: 0) {
            if model.thumbnails.isEmpty {
                Rectangle().fill(EditorTheme.control)
            } else {
                ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
            }
        }
    }

    private func handle(at x: CGFloat, isStart: Bool) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(EditorTheme.accent)
            .frame(width: handleWidth)
            .overlay {
                Capsule()
                    .fill(.black.opacity(0.55))
                    .frame(width: 2, height: 18)
            }
            .offset(x: x)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(isStart ? "Trim start" : "Trim end")
            .accessibilityValue(
                MetadataFormatter.duration(isStart ? model.start : model.end)
            )
            .accessibilityAdjustableAction { direction in
                model.nudgeHandle(isStart: isStart, forward: direction == .increment)
            }
    }
}

/// Bare `AVPlayerLayer`, no AVKit chrome: the screen has its own transport, and
/// AVKit would place a second set of controls over the frame being trimmed.
private struct TrimPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PlayerContainerView, context: Context) {
        if view.playerLayer.player !== player {
            view.playerLayer.player = player
        }
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
