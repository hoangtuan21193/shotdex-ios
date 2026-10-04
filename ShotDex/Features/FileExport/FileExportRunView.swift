import SwiftUI

/// The sheet while an export runs (`PH35_ExportRunning`): `Exporting k of n`,
/// a bar, bytes and time left, the file being made and its step; Cancel
/// asks first (FS-03.07c §2).
struct FileExportRunningView: View {
    @Bindable var model: FileExportModel
    @State private var isConfirmingStop = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text(model.progress.headline)
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        ProgressView(value: model.progress.fraction)
                            .accessibilityValue(Text("\(Int((model.progress.fraction * 100).rounded()))%"))
                        Text(model.progress.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(AppTheme.Spacing.lg)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.md))
                    .accessibilityElement(children: .combine)

                    if let name = model.progress.currentName {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text(ExportCopy.now.uppercased())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AppTheme.Spacing.lg)
                            HStack(alignment: .center, spacing: AppTheme.Spacing.sm) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: name).lineLimit(1).truncationMode(.middle)
                                    if let detail = stepDetail {
                                        Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer(minLength: AppTheme.Spacing.sm)
                                if let step = model.progress.step {
                                    Text(ExportCopy.step(step)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, AppTheme.Spacing.lg)
                            .frame(minHeight: AppTheme.Size.minTouch)
                            .padding(.vertical, AppTheme.Spacing.xs)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.md))
                            .accessibilityElement(children: .combine)
                        }
                    }

                    Text(ExportCopy.keepOpen(model.folders.current?.name ?? ""))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppTheme.Spacing.lg)
                }
                .padding(AppTheme.Spacing.lg)
            }
            Button(role: .destructive) {
                isConfirmingStop = true
            } label: {
                Text(String(localized: "Cancel", table: ExportCopy.table, comment: "Export: stop the run (asks first)"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Size.primaryActionHeight)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .padding(AppTheme.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog(ExportCopy.stopTitle, isPresented: $isConfirmingStop, titleVisibility: .visible) {
            Button(ExportCopy.stop, role: .destructive) { model.cancel() }
            Button(ExportCopy.keepExporting, role: .cancel) {}
        } message: {
            Text(ExportCopy.stopMessage)
        }
    }

    private var stepDetail: String? {
        switch model.progress.step {
        case .preparing(let fraction?)?: ExportCopy.downloadingFromICloud(fraction)
        default: model.progress.currentTarget.map(ExportCopy.toTarget)
        }
    }
}

/// The summary (`PH36_ExportSummary`): what arrived, what did not and why,
/// and the way on — Export Remaining, Retry Failed, or another folder.
struct FileExportSummaryView: View {
    @Bindable var model: FileExportModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    Image(systemName: summary.isClean ? "checkmark" : "exclamationmark.triangle")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(summary.isClean ? Color.green : Color.orange)
                        .frame(width: 56, height: 56)
                        .background((summary.isClean ? Color.green : Color.orange).opacity(0.18), in: Circle())
                        .accessibilityHidden(true)
                    VStack(spacing: AppTheme.Spacing.sm) {
                        Text(verbatim: summary.headline)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        if !summary.detail.isEmpty {
                            Text(verbatim: summary.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .accessibilityElement(children: .combine)

                    if !summary.failures.isEmpty {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            Text(ExportCopy.notExportedHeader.uppercased())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AppTheme.Spacing.lg)
                            VStack(spacing: 0) {
                                ForEach(Array(summary.failures.enumerated()), id: \.offset) { index, failure in
                                    if index > 0 { Divider().padding(.leading, AppTheme.Spacing.lg) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: failure.name).lineLimit(1).truncationMode(.middle)
                                        Text(verbatim: failure.reason).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch, alignment: .leading)
                                    .padding(.horizontal, AppTheme.Spacing.lg)
                                    .padding(.vertical, AppTheme.Spacing.xs)
                                    .accessibilityElement(children: .combine)
                                }
                            }
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.md))
                        }
                    }
                }
                .padding(AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.lg)
            }
            VStack(spacing: AppTheme.Spacing.md) {
                if summary.offersExportRemaining {
                    Button(ExportCopy.exportRemaining) { model.exportRemaining() }
                        .buttonStyle(SummaryButtonStyle(isProminent: false))
                        .disabled(model.isFolderNotConnected)
                } else if summary.offersRetry {
                    Button(ExportCopy.retryFailed) { model.retryFailed() }
                        .buttonStyle(SummaryButtonStyle(isProminent: false))
                }
                if summary.offersAnotherFolder {
                    Button(ExportCopy.chooseAnotherFolder) { model.isPickingFolder = true }
                        .buttonStyle(SummaryButtonStyle(isProminent: false))
                }
                Button(ExportCopy.done, action: onDone)
                    .buttonStyle(SummaryButtonStyle(isProminent: true))
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var summary: FileExportSummary {
        FileExportSummary(
            plan: model.plan, report: model.report, preflight: model.preflightFailure,
            folder: model.folders.current
        )
    }
}

/// A full-width 50pt summary button: the filled one is Done.
private struct SummaryButtonStyle: ButtonStyle {
    let isProminent: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isProminent ? Color.white : Color.accentColor)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Size.primaryActionHeight)
            .background(
                isProminent ? Color.accentColor : Color.accentColor.opacity(0.15),
                in: RoundedRectangle.app(AppTheme.Radius.md)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
