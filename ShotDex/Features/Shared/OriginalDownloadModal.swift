import SwiftUI
import UIKit

/// The Share modal (FS-02.06 §9): a card in the middle of the scene, over
/// the share sheet, from the moment a destination asks until the last file
/// is written. While it runs it is the shared `JobProgressCard` — 380 pt on
/// regular width, "Downloading 3 of 12 from iCloud", a full-width bar,
/// "42% · 24 MB" and Cancel; a failure, the room message or the left-out
/// list take the same place at the same width. Centered in the scene's safe
/// area, so on the Duo's cover it is never under the 84 pt rail.
struct OriginalDownloadModal: View {
    let batch: LazyShareBatch

    var body: some View {
        card
            .jobProgressScrim(opacity: 0.35)
            .animation(EditorTheme.animation, value: batch.stage)
    }

    @ViewBuilder private var card: some View {
        switch (batch.stage, batch.preparation?.state.phase) {
        case (.leftOut(let names, let sharing), _):
            leftOut(names: names, sharing: sharing)
                .jobCardChrome(.system)
        case (.preparing, .failed?):
            if let state = batch.preparation?.state {
                failure(state)
                    .jobCardChrome(.system)
            }
        case (.preparing, .notEnoughSpace(let needed, let free)?):
            VStack(spacing: AppTheme.Spacing.md) {
                Text(OriginalPreparationState.notEnoughSpaceMessage(needed: needed, free: free))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("OK") { batch.cancel() }
                    .buttonStyle(.borderedProminent)
            }
            .jobCardChrome(.system)
        case (.preparing, _):
            downloading
        default:
            writing
        }
    }

    private var downloading: some View {
        let state = batch.preparation?.state
        let hasDownloads = (state?.downloadCount ?? 0) > 0
        return JobProgressCard(
            title: hasDownloads ? (state?.downloadHeadline ?? "") : String(localized: "Preparing…"),
            fraction: hasDownloads ? (state?.fraction ?? 0) : nil,
            detail: hasDownloads ? state?.downloadDetail : nil,
            style: .system,
            onCancel: { batch.cancel() }
        ) {
            if batch.preparation?.isStalled == true {
                Label(OriginalPreparationState.stallMessage, systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var writing: some View {
        let done: Int = if case .writing(let done) = batch.stage { done } else { batch.sources.count }
        let total = batch.sources.count
        return JobProgressCard(
            title: String(localized: "Preparing \(min(total, done + 1)) of \(total)…",
                          comment: "Share modal: files being written for the share sheet"),
            fraction: Double(done) / Double(max(1, total)),
            style: .system,
            onCancel: { batch.cancel() }
        )
    }

    private func failure(_ state: OriginalPreparationState) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(state.failureTitle)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(state.failureNamesText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: AppTheme.Spacing.sm) {
                if state.continueCount > 0 {
                    Button {
                        batch.preparation?.choose(.continueWithout)
                    } label: {
                        Text("Share \(state.continueCount)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    batch.preparation?.choose(.retry)
                } label: {
                    Text("Retry").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                // Neutral beside Share N, the one accent button (DESIGN.md §3.1).
                .tint(state.continueCount > 0 ? Color.primary : nil)
                Button("Cancel", role: .cancel) { batch.cancel() }
            }
            .padding(.top, AppTheme.Spacing.xs)
        }
    }

    private func leftOut(names: [String], sharing: Int) -> some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text(sharing == 0 ? "Unable to Share" : "Not Everything Can Be Shared")
                .font(.headline)
            Text("These couldn't be prepared and were left out: \(OriginalPreparationState.names(names))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if sharing > 0 {
                Button {
                    batch.shareRest()
                } label: {
                    Text("Share \(sharing)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel", role: .cancel) { batch.cancel() }
            } else {
                Button("OK") { batch.cancel() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// The line a processing modal shows before its own work (FS-02.06 §9):
/// "Downloading from iCloud · 3 of 12 · 42%" over a determinate bar. Resize
/// and Collage put it inside the modal they already have.
struct OriginalDownloadLine: View {
    let state: OriginalPreparationState
    var textColor: Color = .secondary

    var body: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            ProgressView(value: state.fraction)
                .accessibilityLabel(OriginalPreparationState.accessibilityProgress(state.fraction))
            Text(state.progressLine)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Job progress card

/// The one modal progress card (iPad progress review 2026-11-20): every job
/// that locks the screen — Share's iCloud download, Resize, the editor's
/// batch save, Panorama, Focus/HDR stacks — draws this, so progress is the
/// obvious thing on a 13" display instead of a spinner lost in a corner.
///
/// 380 pt wide on regular width (320 on a compact phone), centred by its
/// caller; a `.title3` semibold headline ("Saving 2 of 5"), a determinate bar
/// the full width of the card — the bar is the sign of life, so there is no
/// spinner beside it — one `.footnote` detail line, and Cancel as a 44 pt
/// row. With no fraction yet (checking, deleting, writing) a spinner stands
/// where the bar goes. The detail line adds "About N min left" itself once
/// the bar has moved for a few seconds.
struct JobProgressCard<Accessory: View>: View {
    let title: String
    let fraction: Double?
    var detail: String?
    var cancelTitle: String = String(localized: "Cancel", comment: "Progress card: stops the running job")
    var cancelRole: ButtonRole? = .cancel
    var isCancelDisabled = false
    var style: JobCardStyle = .editor
    var onCancel: (() -> Void)?
    @ViewBuilder var accessory: () -> Accessory

    @State private var startedAt = Date()

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text(title)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                // The bar or spinner below carries the title as its label (with
                // the value on the bar), so VoiceOver reads it once.
                .accessibilityHidden(true)
            if let fraction {
                ProgressView(value: min(1, max(0, fraction)))
                    .progressViewStyle(.linear)
                    .tint(tint)
                    .accessibilityLabel(title)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(style == .editor ? .white : nil)
                    .accessibilityLabel(title)
            }
            if let line = detailLine {
                Text(line)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(secondaryText)
                    .multilineTextAlignment(.center)
            }
            accessory()
            if let onCancel {
                Button(role: cancelRole, action: onCancel) {
                    Text(cancelTitle)
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .foregroundStyle(cancelRole == .destructive ? Color.red : tint)
                .disabled(isCancelDisabled)
                .opacity(isCancelDisabled ? 0.4 : 1)
            }
        }
        .jobCardChrome(style)
        .onChange(of: fraction ?? -1) { old, new in
            // A new phase starts its bar again (download, then work): the
            // estimate starts again with it.
            if new < old || old < 0 { startedAt = Date() }
        }
    }

    private var detailLine: String? {
        let estimate = Self.timeLeft(fraction: fraction, since: startedAt)
        switch (detail, estimate) {
        case (let detail?, let estimate?): return "\(detail) · \(estimate)"
        case (let detail?, nil): return detail
        case (nil, let estimate?): return estimate
        default: return nil
        }
    }

    /// "About 3 min left" from how long the bar took to get where it is, once
    /// there is enough of it to go on (5% and 3 s); nil before that.
    static func timeLeft(fraction: Double?, since start: Date, now: Date = Date()) -> String? {
        guard let fraction, fraction >= 0.05, fraction < 1 else { return nil }
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 3 else { return nil }
        return TimeLeftFormat.string(seconds: elapsed * (1 - fraction) / fraction)
    }

    private var primaryText: Color { style == .editor ? .white : .primary }
    private var secondaryText: Color { style == .editor ? EditorTheme.secondaryText : .secondary }
    private var tint: Color { style == .editor ? EditorTheme.accent : .accentColor }
}

extension JobProgressCard where Accessory == EmptyView {
    init(
        title: String,
        fraction: Double?,
        detail: String? = nil,
        cancelTitle: String = String(localized: "Cancel", comment: "Progress card: stops the running job"),
        cancelRole: ButtonRole? = .cancel,
        isCancelDisabled: Bool = false,
        style: JobCardStyle = .editor,
        onCancel: (() -> Void)? = nil
    ) {
        self.init(
            title: title, fraction: fraction, detail: detail, cancelTitle: cancelTitle,
            cancelRole: cancelRole, isCancelDisabled: isCancelDisabled, style: style,
            onCancel: onCancel, accessory: { EmptyView() }
        )
    }
}

/// The card's width, padding and surface, shared by `JobProgressCard` and the
/// outcomes that replace it in the same place (a failure, "not enough space"),
/// so the card does not jump size when the job ends.
private struct JobCardChrome: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let style: JobCardStyle

    func body(content: Content) -> some View {
        content
            .padding(AppTheme.Spacing.xl)
            .frame(maxWidth: sizeClass == .regular ? JobCardMetrics.regularWidth : JobCardMetrics.compactWidth)
            .background(background, in: RoundedRectangle.app(AppTheme.Radius.lg))
            .overlay(
                RoundedRectangle.app(AppTheme.Radius.lg)
                    .stroke(style == .editor ? EditorTheme.panelTopHairline : Color(.separator),
                            lineWidth: style == .editor ? 1 : 0.5)
            )
            .shadow(color: .black.opacity(style == .editor ? 0.5 : 0.3), radius: 30, y: 12)
            .padding(AppTheme.Spacing.xl)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
    }

    private var background: Color {
        style == .editor ? EditorTheme.panelSolid : Color(.secondarySystemBackground)
    }
}

enum JobCardStyle {
    /// Light/dark system card — the Share modal over app chrome.
    case system
    /// The editor's dark panel (tier D: Resize, editor, Panorama, stacks).
    case editor
}

enum JobCardMetrics {
    /// Wide enough that the bar reads at arm's length on a 13" iPad.
    static let regularWidth: CGFloat = 380
    /// A phone keeps the card it had: 320 fits 402 pt with the outer margins.
    static let compactWidth: CGFloat = 320
}

extension View {
    func jobCardChrome(_ style: JobCardStyle) -> some View {
        modifier(JobCardChrome(style: style))
    }

    /// The scrim every progress card sits on: black, swallows every touch,
    /// so nothing under the job can change what it is writing (DESIGN.md §10.3).
    func jobProgressScrim(opacity: Double = 0.6) -> some View {
        ZStack {
            Color.black.opacity(opacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            self
        }
    }
}

extension OriginalPreparationState {
    /// The card headline while originals come down: "Downloading 3 of 12
    /// from iCloud", or the plain line for one photo.
    var downloadHeadline: String {
        downloadCount > 1
            ? String(localized: "Downloading \(currentOrdinal) of \(downloadCount) from iCloud",
                     comment: "Progress card headline: k of n originals coming down from iCloud")
            : String(localized: "Downloading from iCloud", comment: "Progress card headline: one original coming down from iCloud")
    }

    /// The card's detail line: "42% · 24 MB".
    var downloadDetail: String {
        if let totalBytes {
            String(localized: "\(percent)% · \(Self.bytes(totalBytes))",
                   comment: "Progress card detail: overall percent and the size being downloaded")
        } else {
            String(localized: "\(percent)%", comment: "Progress card detail: overall percent")
        }
    }
}
