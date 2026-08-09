import AVFoundation
import Photos
import SwiftUI

/// Trim controls for a video clip: a filmstrip of frames with draggable
/// leading/trailing handles (Photos-style, yellow). The bar spans the full
/// source duration; the selected window maps linearly onto it. Lives in the
/// clip-edit detail panel — a separate sheet would break the
/// drag-handle-then-listen loop.
struct VideoTrimBar: View {
    @Bindable var model: VideoStudioModel
    let clip: VideoClip

    @State private var thumbnails: [UIImage] = []
    /// In-flight handle values while dragging (committed via model on end).
    @State private var draftStart: Double?
    @State private var draftEnd: Double?

    private let barHeight: CGFloat = 36
    private let handleWidth: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let source = max(clip.sourceDuration ?? 0.01, 0.01)
            let start = draftStart ?? clip.trimStart
            let end = draftEnd ?? (clip.trimEnd ?? source)
            let startX = CGFloat(start / source) * width
            let endX = CGFloat(end / source) * width

            ZStack(alignment: .leading) {
                filmstrip(width: width)
                // Dimmed trimmed-away regions.
                Rectangle()
                    .fill(.black.opacity(0.62))
                    .frame(width: max(0, startX))
                Rectangle()
                    .fill(.black.opacity(0.62))
                    .frame(width: max(0, width - endX))
                    .offset(x: endX)
                // Selection frame.
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(.yellow, lineWidth: 2)
                    .frame(width: max(handleWidth * 2, endX - startX))
                    .offset(x: startX)
                trimHandle(systemImage: "chevron.compact.left")
                    .offset(x: startX)
                    .gesture(handleDrag(width: width, source: source, isStart: true))
                trimHandle(systemImage: "chevron.compact.right")
                    .offset(x: endX - handleWidth)
                    .gesture(handleDrag(width: width, source: source, isStart: false))
            }
        }
        .frame(height: barHeight)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: clip.assetID) { await loadThumbnails() }
    }

    private func filmstrip(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            if thumbnails.isEmpty {
                Rectangle().fill(EditorTheme.control)
            } else {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, frame in
                    Image(uiImage: frame)
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(thumbnails.count), height: barHeight)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: barHeight)
    }

    private func trimHandle(systemImage: String) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.yellow)
            .frame(width: handleWidth, height: barHeight)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
            .contentShape(Rectangle().inset(by: -8))
    }

    private func handleDrag(width: CGFloat, source: Double, isStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if draftStart == nil, draftEnd == nil {
                    model.beginUndoGroup()
                }
                let seconds = min(max(Double(value.location.x / width) * source, 0), source)
                if isStart {
                    draftStart = min(seconds, (draftEnd ?? clip.trimEnd ?? source) - VideoClip.minimumClipDuration)
                } else {
                    draftEnd = max(seconds, (draftStart ?? clip.trimStart) + VideoClip.minimumClipDuration)
                }
            }
            .onEnded { _ in
                let start = draftStart ?? clip.trimStart
                let end = draftEnd ?? (clip.trimEnd ?? source)
                model.setTrim(start: start, end: end, for: clip.id)
                model.endUndoGroup()
                draftStart = nil
                draftEnd = nil
            }
    }

    /// Six evenly spaced frames from the source — enough to orient a trim,
    /// cheap enough to regenerate when the selected clip changes.
    private func loadThumbnails() async {
        guard case .video(let asset, _, _, let duration, _, _)? = model.sources[clip.id],
              duration > 0
        else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        var frames: [UIImage] = []
        for index in 0..<6 {
            let seconds = duration * (Double(index) + 0.5) / 6
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            if let cgImage = try? await generator.image(at: time).image {
                frames.append(UIImage(cgImage: cgImage))
            }
        }
        thumbnails = frames
    }
}
