import SwiftUI

/// The frame trim's chrome (FS-12.17 §4–5, board F6_P_PreciseTrim): the
/// floating pill with −1 / +1 Frame, the loupe over the held edge and the
/// label on the viewer. Every number comes from `FrameTrimSession`; these
/// views only draw it and call the model.

/// ‹ −1 Frame · "0:09.07" over "−4 frames" · +1 Frame ›: 248×48, radius 24,
/// floating 14 above the footer. A step that does not fit (the source's
/// end, a clip's 0.1 s, a still's 0.5–10 s) dims its button to 35 % and it
/// takes no touch.
struct VideoFrameTrimPill: View {
    @Bindable var model: VideoStudioModel

    var body: some View {
        if let trim = model.frameTrim {
            let metrics = VideoStudioMetrics.FrameTrim.self
            HStack(spacing: 6) {
                stepButton(-1, trim: trim)
                VStack(spacing: 2) {
                    Text(verbatim: VideoFrameGrid.hundredths(trim.edgeTime))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(verbatim: VideoStudioCopy.frameCount(trim.frames))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("frameTrimReadout")
                stepButton(1, trim: trim)
            }
            .padding(.horizontal, 4)
            .frame(width: metrics.pill.width, height: metrics.pill.height)
            .background(
                Capsule().fill(Color(red: 24 / 255, green: 24 / 255, blue: 26 / 255).opacity(0.92))
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 9, y: 6)
            .accessibilityIdentifier("frameTrimPill")
        }
    }

    private func stepButton(_ count: Int, trim: FrameTrimSession) -> some View {
        let fits = trim.canStep(by: count)
        let metrics = VideoStudioMetrics.FrameTrim.self
        return Button {
            if model.stepFrameTrim(count), VideoInputPreferences.shared.frameStepHaptics {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: count < 0 ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: count < 0 ? VideoStudioCopy.minusOneFrame : VideoStudioCopy.plusOneFrame)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: metrics.pillButton.width, height: metrics.pillButton.height)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(fits ? 1 : 0.35)
        .disabled(!fits)
        .accessibilityLabel(count < 0 ? VideoStudioCopy.minusOneFrame : VideoStudioCopy.plusOneFrame)
    }
}

/// The loupe (§5): a circle over the held edge with ten frames of the
/// source side by side — 13pt slices, 14 apart, five before the cut and
/// five from it on — a 3pt cut line in the selection colour, a frame ruler
/// along its top, and the edge's time at its foot. Grey bands and
/// "Offline" when the media is not on this device (§10).
struct VideoFrameTrimLoupe: View {
    let frames: [UIImage?]
    let label: String
    let diameter: CGFloat
    let isOffline: Bool

    var body: some View {
        let metrics = VideoStudioMetrics.FrameTrim.self
        // The strip runs 140 wide inside the circle, 8 past its left edge,
        // so the cut — between the fifth and sixth slice — is its middle.
        let stripWidth = CGFloat(10) * metrics.loupeStep
        let scale = diameter / metrics.loupeDiameterPhone
        ZStack(alignment: .topLeading) {
            Color.black
            ZStack(alignment: .topLeading) {
                ForEach(0..<10, id: \.self) { index in
                    slice(index < frames.count ? frames[index] : nil)
                        .frame(width: metrics.loupeSlice, height: metrics.loupeDiameterPhone)
                        .clipped()
                        .offset(x: CGFloat(index) * metrics.loupeStep)
                    // Ruler: a tick a frame, a long one every third.
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1, height: index % 3 == 0 ? 9 : 5)
                        .offset(x: CGFloat(index) * metrics.loupeStep + 7, y: 6)
                }
            }
            .frame(width: stripWidth, height: metrics.loupeDiameterPhone, alignment: .topLeading)
            .offset(x: (metrics.loupeDiameterPhone - stripWidth) / 2 + metrics.loupeStep / 2 - metrics.loupeSlice / 2 - 0.5)
            Rectangle()
                .fill(EditorTheme.timelineSelection)
                .frame(width: 3, height: metrics.loupeDiameterPhone)
                .shadow(color: EditorTheme.timelineSelection.opacity(0.9), radius: 4)
                .offset(x: metrics.loupeDiameterPhone / 2 - 1.5)
            Text(verbatim: isOffline ? VideoStudioCopy.offline : label)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 116, height: 20)
                .background(Capsule().fill(Color.black.opacity(0.75)))
                .offset(x: 4, y: 90)
        }
        .frame(width: metrics.loupeDiameterPhone, height: metrics.loupeDiameterPhone)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: diameter, height: diameter, alignment: .topLeading)
        .shadow(color: .black.opacity(0.7), radius: 17, y: 14)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: isOffline ? VideoStudioCopy.offline : label))
        .accessibilityIdentifier("frameTrimLoupe")
    }

    @ViewBuilder
    private func slice(_ image: UIImage?) -> some View {
        if let image, !isOffline {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(Color(white: isOffline ? 0.28 : 0.12))
        }
    }
}

/// "Last frame · 0:09.07" at the viewer's top-left (§4): which frame the
/// viewer shows while trimming, 22 tall on the phone.
struct VideoEdgeFrameLabel: View {
    let trim: FrameTrimSession
    var height: CGFloat = 22

    var body: some View {
        Text(verbatim: VideoStudioCopy.edgeFrameLabel(
            trailing: trim.edge == .trailing,
            at: VideoFrameGrid.hundredths(trim.edgeTime)
        ))
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(Capsule().fill(Color.black.opacity(0.6)))
        .accessibilityIdentifier("frameTrimViewerLabel")
    }
}
