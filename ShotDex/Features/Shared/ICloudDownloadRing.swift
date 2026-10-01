import SwiftUI

/// iOS-style "downloading from iCloud" indicator: a cloud glyph wrapped by a
/// circular progress ring. Determinate once the download reports a fraction,
/// otherwise a continuously rotating arc.
struct ICloudDownloadRing: View {
    /// 0…1; treated as indeterminate while it is 0 (or ≥ 1).
    let progress: Double
    @State private var spin = false

    private var isDeterminate: Bool { progress > 0 && progress < 1 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.25), lineWidth: 2)
            if isDeterminate {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.2), value: progress)
            } else {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            }
            Image(systemName: "icloud")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: 22, height: 22)
        .onAppear { spin = true }
        // No number beside the ring; VoiceOver gets one (FS-02.06 §8).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(OriginalPreparationState.accessibilityProgress(progress))
    }
}
