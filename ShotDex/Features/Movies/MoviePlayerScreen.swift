import SwiftUI

/// Full-screen playback (FS-23.02 §2): black, a spinner only after 350 ms,
/// and a card that says why when a movie can't play. Transport, tracks and
/// subtitles join in plan tasks 18–23.
struct MoviePlayerScreen: View {
    @State var model: MoviePlayerModel
    let videoView: UIView
    @Environment(\.dismiss) private var dismiss
    @State private var showsSpinner = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(view: videoView).ignoresSafeArea()
            if let reason = model.failureReason {
                failureCard(reason)
            } else if showsSpinner {
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    if model.needsSpinner(at: context.date) {
                        ProgressView().tint(.white).controlSize(.large)
                    }
                }
            }
        }
        .overlay(alignment: .top) { topBar }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .task {
            model.start()
            try? await Task.sleep(for: .milliseconds(350))
            showsSpinner = true
        }
        .onDisappear { model.close() }
        .accessibilityElement(children: .contain)
    }

    private var topBar: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
            }
            .tint(.white)
            .accessibilityLabel(String(localized: "Close", comment: "Movie player: close"))
            Text(model.movie.displayTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Text(MoviePlayerText.position(model.timeMs, of: model.durationMs))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityLabel(String(localized: "Position", comment: "Movie player: VoiceOver name of the time label"))
                .accessibilityValue(MoviePlayerText.position(model.timeMs, of: model.durationMs))
        }
        .padding(.horizontal, AppTheme.Spacing.md)
    }

    private func failureCard(_ reason: String) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.yellow)
            Text(String(localized: "Can't Play This Movie", comment: "Movie player: playback failed"))
                .font(.headline)
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Close", comment: "Movie player: close after an error")) { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top, AppTheme.Spacing.sm)
        }
        .padding(AppTheme.Spacing.lg)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// The engine's own view, placed in SwiftUI.
private struct VideoSurface: UIViewRepresentable {
    let view: UIView
    func makeUIView(context: Context) -> UIView { view }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

enum MoviePlayerText {
    /// `47:12 / 2:04:01`.
    static func position(_ ms: Int64, of total: Int64) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = total >= 3_600_000 ? .hourMinuteSecond : .minuteSecond
        let now = Duration.milliseconds(ms).formatted(.time(pattern: pattern))
        guard total > 0 else { return now }
        return "\(now) / \(Duration.milliseconds(total).formatted(.time(pattern: pattern)))"
    }
}
