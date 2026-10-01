import SwiftUI
import UIKit

/// The Share modal (FS-02.06 §9): a small card in the middle of the scene,
/// over the share sheet, from the moment a destination asks until the last
/// file is written. "Downloading from iCloud · 63% · 24 MB", a determinate
/// bar and Cancel; a failure, the room message or the left-out list in the
/// same card. Centered in the scene's safe area, so on the Duo's cover it is
/// never under the 84 pt rail.
struct OriginalDownloadModal: View {
    let batch: LazyShareBatch

    var body: some View {
        ZStack {
            // Holds every touch: nothing under the card can be tapped while
            // the share is being prepared.
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            card
                .padding(AppTheme.Spacing.xl)
                .frame(maxWidth: 320)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
                .overlay(RoundedRectangle.app(AppTheme.Radius.lg).stroke(Color(.separator), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
                .padding(AppTheme.Spacing.xl)
                .accessibilityElement(children: .contain)
                .accessibilityAddTraits(.isModal)
        }
        .animation(EditorTheme.animation, value: batch.stage)
    }

    @ViewBuilder private var card: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            switch (batch.stage, batch.preparation?.state.phase) {
            case (.leftOut(let names, let sharing), _):
                leftOut(names: names, sharing: sharing)
            case (.preparing, .failed?):
                if let state = batch.preparation?.state { failure(state) }
            case (.preparing, .notEnoughSpace(let needed, let free)?):
                Text(OriginalPreparationState.notEnoughSpaceMessage(needed: needed, free: free))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button("OK") { batch.cancel() }
                    .buttonStyle(.borderedProminent)
            case (.preparing, _):
                downloading
            default:
                writing
            }
        }
    }

    private var downloading: some View {
        let state = batch.preparation?.state
        let hasDownloads = (state?.downloadCount ?? 0) > 0
        return VStack(spacing: AppTheme.Spacing.md) {
            Text(hasDownloads ? (state?.shareLine ?? "") : String(localized: "Preparing…"))
                .font(.headline.monospacedDigit())
                .multilineTextAlignment(.center)
            if hasDownloads {
                ProgressView(value: state?.fraction ?? 0)
                    .accessibilityLabel(OriginalPreparationState.accessibilityProgress(state?.fraction ?? 0))
            } else {
                ProgressView()
            }
            if batch.preparation?.isStalled == true {
                Label(OriginalPreparationState.stallMessage, systemImage: "exclamationmark.icloud")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
            Button("Cancel", role: .cancel) { batch.cancel() }
                .padding(.top, AppTheme.Spacing.xs)
        }
    }

    private var writing: some View {
        let done: Int = if case .writing(let done) = batch.stage { done } else { batch.sources.count }
        return VStack(spacing: AppTheme.Spacing.md) {
            Text("Preparing \(min(batch.sources.count, done + 1)) of \(batch.sources.count)…")
                .font(.headline.monospacedDigit())
            ProgressView(value: Double(done), total: Double(max(1, batch.sources.count)))
            Button("Cancel", role: .cancel) { batch.cancel() }
                .padding(.top, AppTheme.Spacing.xs)
        }
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
