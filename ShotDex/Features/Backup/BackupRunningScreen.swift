import SwiftUI

/// One job in detail (FS-22.02 §5, board `PH_BackupRunning` 5/5): progress,
/// Pause, the watching line, the file in flight, totals, files not copied and
/// the backed-up files. On iPad it is the right-hand pane of the list.
struct BackupRunningScreen: View {
    let jobId: String
    var isEmbedded = false

    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.openURL) private var openURL
    @State private var keepsScreenOn = false

    private var coordinator: BackupCoordinator { dependencies.backupCoordinator }
    private var job: BackupJob? { coordinator.jobs.first { $0.id == jobId } }

    var body: some View {
        if let job {
            content(job)
        } else {
            ContentUnavailableView(String(localized: "Backup Deleted", comment: "Backup detail: the job is gone"), systemImage: "clock.arrow.circlepath")
        }
    }

    private func content(_ job: BackupJob) -> some View {
        let info = BackupJobInfo(job: job, dependencies: dependencies)
        let state = coordinator.states[job.id] ?? BackupJobState(jobId: job.id)
        let progress = coordinator.runningJobId == job.id ? coordinator.progress[job.id] : nil
        let failed = (try? dependencies.backups.failedEntries(jobId: job.id)) ?? []
        return List {
            Section {
                header(job, info: info, state: state, progress: progress)
            }
            if #unavailable(iOS 26.0) {
                Section {
                    Toggle(String(localized: "Keep Screen On", comment: "Backup detail switch: hold the screen awake while copying (before iOS 26)"), isOn: $keepsScreenOn)
                }
            }
            if let progress, let file = progress.currentFile {
                Section(String(localized: "Now", comment: "Backup detail section: the file being copied")) {
                    LabeledContent {
                        EmptyView()
                    } label: {
                        Text(file).monospacedDigit()
                        Text(phaseText(progress.phase)).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                totals(state: state, progress: progress, backedUp: coordinator.backedUpItems[job.id] ?? 0)
            }
            Section {
                if !failed.isEmpty {
                    NavigationLink {
                        BackupFailedFilesScreen(entries: failed) { coordinator.retry(job.id) }
                    } label: {
                        Label(String(localized: "\(failed.count) Files Not Copied", comment: "Backup detail row: files that failed"), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.primary)
                    }
                    .tint(.orange)
                }
                NavigationLink {
                    BackupFilesScreen(jobId: job.id)
                } label: {
                    LabeledContent(String(localized: "Backed-Up Files", comment: "Backup detail row: the list of copied files"),
                                   value: String(localized: "Show", comment: "Backup detail: open the list"))
                }
            } footer: {
                Text(footnote(state: state, progress: progress))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(isEmbedded ? "" : "\(info.sourceName) → \(info.connectionName)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: keepsScreenOn) { _, on in
            var updated = job
            updated.settings.keepsScreenOn = on
            try? dependencies.backups.update(updated)
            coordinator.keepScreenOnChanged(job.id, on: on)
        }
        .onAppear { keepsScreenOn = job.settings.keepsScreenOn }
    }

    private func header(_ job: BackupJob, info: BackupJobInfo, state: BackupJobState, progress: BackupProgress?) -> some View {
        let status = info.status
        let percent = Int(((status.fraction ?? (state.status == .watching ? 1 : 0)) * 100).rounded())
        return VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            if isEmbedded {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(info.sourceName) → \(info.connectionName)").font(.title3.weight(.semibold))
                        Text(info.subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { coordinator.backUpNow(job.id) } label: {
                        Label(String(localized: "Back Up Now", comment: "Backup: compare the source now"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            if state.status == .uploading || state.status == .watching {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Text(state.status == .uploading && progress?.isFirstRun == false
                         ? String(localized: "\(progress?.total ?? 0) new", comment: "Backup detail: new files being copied")
                         : "\(percent)%")
                        .font(.largeTitle.weight(.bold))
                        .monospacedDigit()
                    Text(state.status == .watching
                         ? String(localized: "Up to date in \(job.folder)", comment: "Backup detail: nothing left to copy")
                         : String(localized: "Backing up to \(job.folder)", comment: "Backup detail: where files go"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                // Waiting, paused or stopped: the same words as the card.
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(status.tone.color == .secondary ? Color.primary : status.tone.color)
                    Text(status.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if state.status == .uploading || state.status == .watching || status.fraction != nil {
                ProgressView(value: status.fraction ?? (state.status == .watching ? 1 : 0))
            }
            if let action = status.action {
                Button {
                    switch action {
                    case .pause: coordinator.pause(job.id)
                    case .resume: coordinator.resume(job.id)
                    case .retry: coordinator.retry(job.id)
                    case .openSettings:
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    case .editServer: break
                    }
                } label: {
                    Label(action.title, systemImage: action == .pause ? "pause" : "play")
                        .frame(maxWidth: .infinity, minHeight: AppTheme.Size.minTouch)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
            if state.status == .watching || state.status == .uploading {
                Label {
                    Text(String(localized: "Watching · new photos back up as they appear", comment: "Backup detail: the job keeps watching its source"))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "eye").foregroundStyle(.green)
                }
                .font(.footnote)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func totals(state: BackupJobState, progress: BackupProgress?, backedUp: Int) -> some View {
        Group {
            if let progress, progress.total > 0 {
                LabeledContent(String(localized: "Backed Up", comment: "Backup detail row"),
                               value: String(localized: "\(progress.done.formatted()) of \(progress.total.formatted())", comment: "Backup detail: files done of files"))
                LabeledContent(String(localized: "Size", comment: "Backup detail row"),
                               value: "\(progress.bytesDone.formatted(.byteCount(style: .file))) of \(progress.bytesTotal.formatted(.byteCount(style: .file)))")
                if let rate = coordinator.bytesPerSecond[jobId] {
                    LabeledContent(String(localized: "Speed", comment: "Backup detail row"),
                                   value: "\(Int64(rate).formatted(.byteCount(style: .file)))/s")
                    let minutes = max(1, Int((Double(progress.bytesTotal - progress.bytesDone) / rate / 60).rounded()))
                    LabeledContent(String(localized: "Time Left", comment: "Backup detail row"),
                                   value: String(localized: "About \(minutes) min", comment: "Backup detail: time left"))
                }
            } else {
                LabeledContent(String(localized: "Backed Up", comment: "Backup detail row"),
                               value: String(localized: "\(backedUp.formatted()) items", comment: "Backup card: how many items are backed up"))
                if let checked = state.lastCheckedAt {
                    LabeledContent(String(localized: "Last Checked", comment: "Backup detail row"),
                                   value: Date(timeIntervalSince1970: TimeInterval(checked)).formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .monospacedDigit()
    }

    private func phaseText(_ phase: BackupProgress.Phase?) -> String {
        switch phase {
        case .downloading: String(localized: "Downloading from iCloud", comment: "Backup detail: the original is being fetched")
        case .verifying: String(localized: "Checking", comment: "Backup detail: the copy is read back and compared")
        default: String(localized: "Uploading", comment: "Backup detail: the file is being sent")
        }
    }

    private func footnote(state: BackupJobState, progress: BackupProgress?) -> String {
        if #available(iOS 26.0, *) {
            let left = (progress?.total ?? 0) - (progress?.done ?? 0)
            let base = String(localized: "Keeps running when you leave ShotDex. If iOS stops it, the backup resumes from the last file it finished — nothing is copied twice.", comment: "Backup detail footnote, iOS 26")
            return left > 20 ? base + " " + String(localized: "Leave ShotDex open to finish faster.", comment: "Backup detail: a long queue goes faster with the app open") : base
        }
        return String(localized: "Runs while ShotDex is open, and in the background when iOS allows. If it stops, the backup resumes from the last file it finished — nothing is copied twice.", comment: "Backup detail footnote, before iOS 26")
    }
}

/// Files that were not copied, with why, and Retry (FS-22.02 §2).
struct BackupFailedFilesScreen: View {
    let entries: [BackupLedgerEntry]
    var retry: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(entries, id: \.id) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text((entry.resourceKey as NSString).lastPathComponent.split(separator: ":").last.map(String.init) ?? entry.resourceKey)
                        Text(entry.lastError ?? "").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text(String(localized: "Each file is tried on the next three runs. Retry tries them all again now.", comment: "Files Not Copied footer"))
            }
            Section {
                Button(String(localized: "Retry", comment: "Backup: try the failed files again")) {
                    retry()
                    dismiss()
                }
            }
        }
        .navigationTitle(String(localized: "Files Not Copied", comment: "Screen title"))
    }
}

/// The newest backed-up files and where each went.
struct BackupFilesScreen: View {
    let jobId: String
    @Environment(AppDependencies.self) private var dependencies

    var body: some View {
        let entries = (try? dependencies.backups.handledEntries(jobId: jobId)) ?? []
        List(entries, id: \.id) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(((entry.remotePath ?? "") as NSString).lastPathComponent)
                Text(entry.remotePath ?? "").font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView(String(localized: "Nothing Backed Up Yet", comment: "Backed-Up Files empty state"), systemImage: "tray")
            }
        }
        .navigationTitle(String(localized: "Backed-Up Files", comment: "Screen title"))
    }
}
