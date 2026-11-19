import SwiftUI

/// Where the photos go, how they are named, what they carry (FS-20 §6): a
/// panel under the grid on a phone (`PH_Ingest`), the inspector beside it
/// on a wide screen (`IP_Ingest`). Rows push their editor.
struct IngestOptionsPanel: View {
    @Bindable var model: IngestModel
    let isWide: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !isWide {
                Capsule().fill(Color(.tertiaryLabel)).frame(width: 36, height: 5).padding(.top, AppTheme.Spacing.sm)
                Text("Import Options", tableName: IngestCopy.table, comment: "Import from Card: the options panel title")
                    .font(.headline)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
            Form {
                Section {
                    NavigationLink {
                        IngestDestinationScreen(model: model)
                    } label: {
                        LabeledContent(String(localized: "Destination", table: IngestCopy.table, comment: "Import option row"),
                                       value: model.destination?.name ?? String(localized: "Choose", table: IngestCopy.table,
                                                                                comment: "Import option: nothing chosen yet"))
                    }
                    NavigationLink {
                        IngestFoldersScreen(model: model)
                    } label: {
                        LabeledContent(String(localized: "Folders", table: IngestCopy.table, comment: "Import option row"),
                                       value: IngestCopy.foldersSummary(model.settings.folders))
                    }
                    NavigationLink {
                        IngestBackupScreen(model: model)
                    } label: {
                        LabeledContent(String(localized: "Backup", table: IngestCopy.table, comment: "Import option row"),
                                       value: backupValue)
                    }
                    NavigationLink {
                        IngestFileNamesScreen(model: model)
                    } label: {
                        LabeledContent(String(localized: "File Names", table: IngestCopy.table, comment: "Import option row"),
                                       value: IngestCopy.nameTitle(model.settings.template))
                    }
                    NavigationLink {
                        IngestMetadataScreen(model: model)
                    } label: {
                        LabeledContent(String(localized: "Metadata", table: IngestCopy.table, comment: "Import option row"),
                                       value: IngestCopy.metadataSummary(model.settings.metadata))
                    }
                    Toggle(String(localized: "Eject After Import", table: IngestCopy.table, comment: "Import option row"),
                           isOn: $model.settings.ejectsAfterImport)
                } footer: {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        if let footer = model.readiness.footer {
                            Text(footer).foregroundStyle(.red)
                        } else if let destination = model.destination {
                            Text(IngestCopy.summaryFooter(count: model.checkedCount, bytes: model.checkedBytes, destination: destination.name))
                        }
                        if let message = model.endingMessage {
                            Text(message).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                }
                if let summary = model.lastSummary, !summary.remaining.isEmpty || !summary.failed.isEmpty || summary.backupIncomplete {
                    Section {
                        if !summary.remaining.isEmpty {
                            Button(String(localized: "Import Remaining", table: IngestCopy.table, comment: "Card import: copy what a stopped run left")) {
                                model.importRemaining()
                            }
                        }
                        if !summary.failed.isEmpty {
                            Button(String(localized: "Retry Failed", table: IngestCopy.table, comment: "Card import: copy the files that failed again")) {
                                model.retryFailed()
                            }
                        }
                        if let line = IngestCopy.backupLine(summary) {
                            Button(String(localized: "Back Up Remaining", table: IngestCopy.table, comment: "Card import: finish the backup")) {
                                model.backUpRemaining()
                            }
                            .accessibilityHint(Text(verbatim: line))
                        }
                    } footer: {
                        if let line = IngestCopy.backupLine(summary) { Text(line) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .contentMargins(.top, isWide ? AppTheme.Spacing.lg : 0, for: .scrollContent)
            .listSectionSpacing(.compact)
            .frame(height: isWide ? nil : IngestMetrics.panelFormHeight)
            .frame(maxHeight: isWide ? .infinity : nil)
            Button {
                model.startImport()
            } label: {
                Text(IngestCopy.importButton(count: model.checkedCount))
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: AppTheme.Size.primaryActionHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!model.readiness.canImport)
            .padding(.horizontal)
            .padding(.bottom, AppTheme.Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: isWide ? 0 : AppTheme.Radius.xl,
                                          topTrailingRadius: isWide ? 0 : AppTheme.Radius.xl))
        .shadow(color: .black.opacity(isWide ? 0 : 0.12), radius: 12, y: -2)
    }

    private var backupValue: String {
        guard model.settings.backsUp, let folder = model.settings.backupFolder else {
            return String(localized: "Off", table: IngestCopy.table, comment: "Import option: backup off")
        }
        return model.backupRoot == nil
            ? String(localized: "Not connected", table: IngestCopy.table, comment: "Import option: backup drive unplugged")
            : folder.title
    }
}

/// The run (FS-20 §7, `PH_IngestProgress`): how far, Copy · Verify ·
/// Backup, the file in hand, Pause and Stop Import….
struct IngestProgressPanel: View {
    @Bindable var model: IngestModel
    @Binding var isConfirmingStop: Bool
    /// Regular width under the grid (iPad portrait, Duo inner): one hero
    /// line and bar, Copy · Verify · Backup side by side, capped at 560pt
    /// and short enough for the Duo's 669pt.
    var isHero = false

    /// The hero block's width on a wide screen.
    static let heroWidth: CGFloat = 560

    var body: some View {
        if isHero { hero } else { stacked }
    }

    private var stacked: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            VStack(spacing: AppTheme.Spacing.xs) {
                Text("Importing from \(model.card.name)", tableName: IngestCopy.table, comment: "Card import progress title")
                    .font(.headline)
                Text(IngestCopy.progressLine(model.liveProgress))
                    .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            VStack(spacing: AppTheme.Spacing.sm) {
                bar(String(localized: "Copy", table: IngestCopy.table, comment: "Card import progress row"), model.liveProgress.fraction)
                bar(String(localized: "Verify", table: IngestCopy.table, comment: "Card import progress row"),
                    model.progress.total > 0 ? Double(model.verifiedCount) / Double(model.progress.total) : 0)
                if model.settings.backsUp {
                    bar(String(localized: "Backup", table: IngestCopy.table, comment: "Card import progress row"),
                        model.progress.total > 0 ? Double(model.backedUpCount) / Double(model.progress.total) : 0)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.lg))
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    model.isPaused ? model.resume() : model.pause()
                } label: {
                    Text(model.isPaused
                         ? String(localized: "Resume", table: IngestCopy.table, comment: "Card import: carry on after Pause")
                         : String(localized: "Pause", table: IngestCopy.table, comment: "Card import: wait after the file in hand"))
                        .frame(maxWidth: .infinity, minHeight: AppTheme.Size.primaryActionHeight)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.primary)
                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
                    Text("Stop Import…", tableName: IngestCopy.table, comment: "Card import: stop the run")
                        .frame(maxWidth: .infinity, minHeight: AppTheme.Size.primaryActionHeight)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.red)
            }
            Text("You can leave this screen; the \(model.card.name) row in Collections shows progress.", tableName: IngestCopy.table,
                 comment: "Card import progress footer")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private var hero: some View {
        let live = model.liveProgress
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Importing \(live.done.formatted()) of \(live.total.formatted())", tableName: IngestCopy.table,
                 comment: "Card import progress headline on a wide screen: photos done of the batch")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            ProgressView(value: min(1, max(0, live.fraction)))
                .padding(.vertical, AppTheme.Spacing.xs)
            Text(heroDetail(live))
                .font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(spacing: AppTheme.Spacing.lg) {
                stage(String(localized: "Copy", table: IngestCopy.table, comment: "Card import progress row"), live.fraction)
                stage(String(localized: "Verify", table: IngestCopy.table, comment: "Card import progress row"),
                      model.progress.total > 0 ? Double(model.verifiedCount) / Double(model.progress.total) : 0)
                if model.settings.backsUp {
                    stage(String(localized: "Backup", table: IngestCopy.table, comment: "Card import progress row"),
                          model.progress.total > 0 ? Double(model.backedUpCount) / Double(model.progress.total) : 0)
                }
            }
            .padding(.top, AppTheme.Spacing.xs)
            HStack(spacing: AppTheme.Spacing.md) {
                Button {
                    model.isPaused ? model.resume() : model.pause()
                } label: {
                    Text(model.isPaused
                         ? String(localized: "Resume", table: IngestCopy.table, comment: "Card import: carry on after Pause")
                         : String(localized: "Pause", table: IngestCopy.table, comment: "Card import: wait after the file in hand"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.primary)
                Button(role: .destructive) {
                    isConfirmingStop = true
                } label: {
                    Text("Stop Import…", tableName: IngestCopy.table, comment: "Card import: stop the run")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(.red)
            }
            .padding(.top, AppTheme.Spacing.sm)
        }
        .frame(maxWidth: Self.heroWidth, alignment: .leading)
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
        .overlay(alignment: .top) { Divider() }
    }

    /// "48.2 GB of 61.0 GB · About 4 min left" — the time only once the
    /// run's own pace says something.
    private func heroDetail(_ live: IngestProgress) -> String {
        let bytes = String(localized: "\(IngestCopy.bytes(live.bytesDone)) of \(IngestCopy.bytes(live.bytesTotal))", table: IngestCopy.table,
                           comment: "Card import progress on a wide screen: bytes done of the batch")
        if model.isPaused {
            return bytes + " · " + String(localized: "Paused", table: IngestCopy.table, comment: "Card import progress: the run is paused")
        }
        guard let seconds = model.secondsLeft else { return bytes }
        let left = Duration.seconds(max(60, seconds))
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
        return bytes + " · " + String(localized: "About \(left) left", table: IngestCopy.table,
                                      comment: "Card import progress: time left at this run's pace, e.g. About 4 min left")
    }

    /// One stage as a compact column: name and percent over a thin bar.
    private func stage(_ title: String, _ fraction: Double) -> some View {
        let clamped = min(1, max(0, fraction))
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text(title)
                Spacer(minLength: AppTheme.Spacing.xs)
                Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.footnote)
            ProgressView(value: clamped)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func bar(_ title: String, _ fraction: Double) -> some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading)
            ProgressView(value: min(1, max(0, fraction)))
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

extension IngestMetrics {
    /// The options panel's list on a phone: six rows and the footer, the
    /// grid keeps the rest (`PH_Ingest`).
    static let panelFormHeight: CGFloat = 364
}
