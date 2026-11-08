import SwiftUI

/// The selected job's progress (board `MAC_Backup` inspector, 5/5 of iOS):
/// ring, Pause/Resume, Watching line, the file in flight, the counts.
struct MacBackupInspector: View {
    let job: BackupJob
    var edit: () -> Void
    @Environment(MacDependencies.self) private var dependencies
    /// Files not copied, read off the main actor every 10 s while shown —
    /// not in the body on every progress tick (hang report 2026-11-08).
    @State private var failedCount = 0

    private var coordinator: BackupCoordinator { dependencies.backupCoordinator }
    private var control: MacBackupControl { dependencies.backupControl }

    var body: some View {
        let info = MacBackupJobInfo(job: job, dependencies: dependencies)
        let status = info.status
        let progress = coordinator.progress[job.id]
        let isRunning = coordinator.runningJobId == job.id
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(info.sourceName) → \(info.connectionName)").font(.headline).lineLimit(1)
                        Text(info.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button(String(localized: "Edit…", comment: "Mac Backup: edit a job"), action: edit)
                }
                Divider()
                HStack(spacing: 16) {
                    ring(status: status)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(status.title).font(.subheadline.weight(.semibold)).foregroundStyle(status.tone.macColor)
                        Text(status.detail).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        if coordinator.states[job.id]?.status == .pausedByUser {
                            Button { control.resume(job.id) } label: {
                                Label(BackupStatusText.Action.resume.title, systemImage: "play.fill")
                            }
                        } else if isRunning {
                            Button { control.pause(job.id) } label: {
                                Label(BackupStatusText.Action.pause.title, systemImage: "pause.fill")
                            }
                        } else if let action = status.action, action == .retry {
                            Button(action.title) { control.retry(job.id) }
                        }
                    }
                }
                Label(String(localized: "Watching · new photos back up as they appear", comment: "Backup: the job keeps watching after this run"),
                      systemImage: "eye")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if isRunning, let progress {
                    Divider()
                    section(String(localized: "Now", comment: "Mac Backup inspector: the file in flight"))
                    if let file = progress.currentFile {
                        Text(file).font(.callout).lineLimit(1).truncationMode(.middle)
                    }
                    section(String(localized: "Progress", comment: "Mac Backup inspector: counts"))
                    row(String(localized: "Backed Up", comment: "Mac Backup inspector"),
                        String(localized: "\(progress.done.formatted()) of \(progress.total.formatted())", comment: "Mac Backup inspector: files done of total"))
                    if progress.bytesTotal > 0 {
                        row(String(localized: "Size", comment: "Mac Backup inspector"),
                            String(localized: "\(progress.bytesDone.formatted(.byteCount(style: .file))) of \(progress.bytesTotal.formatted(.byteCount(style: .file)))", comment: "Mac Backup inspector: bytes done of total"))
                    }
                    if let speed = coordinator.bytesPerSecond[job.id] {
                        row(String(localized: "Speed", comment: "Mac Backup inspector"),
                            String(localized: "\(Int64(speed).formatted(.byteCount(style: .file)))/s", comment: "Mac Backup inspector: upload speed"))
                    }
                }
                if failedCount > 0 {
                    Divider()
                    Label(failedCount == 1
                          ? String(localized: "1 File Not Copied", comment: "Backup: files that failed")
                          : String(localized: "\(failedCount) Files Not Copied", comment: "Backup: files that failed"),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text("If it stops, the backup resumes from the last file it finished — nothing is copied twice.",
                     comment: "Mac Backup inspector: footnote")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .task(id: job.id) {
            let backups = dependencies.backups
            let jobId = job.id
            while !Task.isCancelled {
                failedCount = await Task.detached(priority: .utility) { ((try? backups.failedEntries(jobId: jobId)) ?? []).count }.value
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func ring(status: BackupStatusText) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 8)
            Circle().trim(from: 0, to: status.fraction ?? 1)
                .stroke(MacTheme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let fraction = status.fraction {
                Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                    .font(.title2.weight(.semibold)).monospacedDigit()
            } else {
                Image(systemName: "checkmark").font(.title2.weight(.semibold)).foregroundStyle(MacTheme.accent)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}
