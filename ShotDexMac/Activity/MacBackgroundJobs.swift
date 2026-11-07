import SwiftUI

/// Activity › Background (user 2026-11-08: "nothing shows what runs in the
/// background — index, hashing…"): every job ShotDex runs on its own, one
/// row each while it runs or waits — the library index, place lookup, a
/// source being read, the On Server check (matching photos with server
/// files by SHA-256), Backup, the originals check, a card import. Read from
/// the jobs' own observable state, so a row moves with its job and nothing
/// is queried here.
struct MacBackgroundJobs: View {
    @Environment(MacDependencies.self) private var dependencies

    struct Row: Identifiable {
        var id: String
        var symbol: String
        var title: String
        var detail: String?
        /// Nil: going, how far unknown.
        var fraction: Double?
        var isWaiting = false
    }

    var body: some View {
        let rows = Self.rows(dependencies)
        VStack(alignment: .leading, spacing: 6) {
            Text("Background", comment: "Mac Activity: work ShotDex does on its own (index, checks, backups)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                if rows.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                        Text("Nothing running — the library, checks and backups are up to date.",
                             comment: "Mac Activity › Background: no background job is running or waiting")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider() }
                        MacBackgroundRow(row: row)
                    }
                }
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Background", comment: "Mac Activity: work ShotDex does on its own (index, checks, backups)"))
        }
    }

    /// What runs or waits now, in the order a person would look for it.
    @MainActor
    static func rows(_ dependencies: MacDependencies) -> [Row] {
        var rows: [Row] = []
        if let library = dependencies.library {
            if let progress = library.indexProgress, progress.total > 0 {
                var detail = String(localized: "\(progress.processed.formatted()) of \(progress.total.formatted()) photos",
                                    comment: "Mac Activity › Background: index progress")
                if let left = library.indexThroughput?.remaining {
                    let minutes = max(1, Int(left.components.seconds / 60))
                    detail += " · " + String(localized: "about \(minutes) min left", comment: "Mac Activity › Background: time left")
                }
                rows.append(Row(id: "index", symbol: "arrow.triangle.2.circlepath",
                                title: String(localized: "Indexing the library", comment: "Mac Activity › Background: the index reads photos' metadata"),
                                detail: detail, fraction: progress.fraction))
            } else if library.isIndexing {
                rows.append(Row(id: "index", symbol: "arrow.triangle.2.circlepath",
                                title: String(localized: "Indexing the library", comment: "Mac Activity › Background: the index reads photos' metadata")))
            } else if library.pendingICloudCount > 0 {
                rows.append(Row(id: "index", symbol: "icloud",
                                title: String(localized: "Index waiting for iCloud", comment: "Mac Activity › Background: photos whose metadata iCloud has not sent yet"),
                                detail: String(localized: "\(library.pendingICloudCount.formatted()) photos", comment: "Mac Activity › Background: a count of photos"),
                                isWaiting: true))
            }
            if let left = library.placeLookupRemaining, left > 0 {
                rows.append(Row(id: "places", symbol: "mappin.and.ellipse",
                                title: String(localized: "Finding places", comment: "Mac Activity › Background: turning GPS into town names"),
                                detail: String(localized: "\(left.formatted()) photos left", comment: "Mac Activity › Background: photos still to do")))
            }
        }
        if let read = dependencies.sourcesModel.readProgress {
            rows.append(Row(id: "read", symbol: "folder",
                            title: String(localized: "Reading \(read.sourceName)", comment: "Mac Activity › Background: a folder, drive or server source is being read"),
                            detail: read.footLine, fraction: read.total > 0 ? read.fraction : nil,
                            isWaiting: read.isPaused || read.isDisconnected))
        }
        let check = dependencies.onServerCheck
        if dependencies.onServerStatus.isShown(check) {
            rows.append(Row(id: "onServer", symbol: "externaldrive.connected.to.line.below",
                            title: String(localized: "Matching photos with the server (SHA-256)",
                                          comment: "Mac Activity › Background: the On Server check hashes iCloud originals and server files to find the same photos"),
                            detail: dependencies.onServerStatus.line, fraction: dependencies.onServerStatus.fraction,
                            isWaiting: !check.isRunning && (!check.waits.isEmpty || check.photosWait != nil)))
        }
        let backups = dependencies.backupCoordinator
        if let id = backups.runningJobId, let job = backups.jobs.first(where: { $0.id == id }) {
            let progress = backups.progress[id]
            var detail: String?
            if let progress, progress.total > 0 {
                detail = String(localized: "\(progress.done.formatted()) of \(progress.total.formatted())", comment: "Mac Activity › Background: items done of all")
                if let file = progress.currentFile { detail! += " · " + file }
            }
            let folder = job.folder.isEmpty ? "/" : job.folder
            rows.append(Row(id: "backup", symbol: "clock.arrow.circlepath",
                            title: String(localized: "Backing up to \(folder)", comment: "Mac Activity › Background: a backup job is copying"),
                            detail: detail, fraction: progress.flatMap(Self.fraction)))
        }
        let originals = dependencies.originalPresenceCheck
        if originals.isRunning {
            let progress = originals.progress
            rows.append(Row(id: "originals", symbol: "internaldrive",
                            title: String(localized: "Checking which originals are on this Mac", comment: "Mac Activity › Background: the originals check"),
                            detail: progress.total > 0
                                ? String(localized: "\(progress.checked.formatted()) of \(progress.total.formatted()) photos", comment: "Mac Activity › Background: a count of photos checked")
                                : nil,
                            fraction: progress.total > 0 ? min(1, Double(progress.checked) / Double(progress.total)) : nil))
        }
        if let ingest = dependencies.cards.center.running {
            rows.append(Row(id: "ingest", symbol: "sdcard",
                            title: String(localized: "Importing from \(ingest.card.name)", comment: "Mac Activity › Background: a card import"),
                            detail: IngestCopy.progressLine(ingest.progress), fraction: ingest.progress.fraction,
                            isWaiting: ingest.isPaused))
        }
        return rows
    }
}

extension MacBackgroundJobs {
    /// By bytes, else by items; nil when neither is known.
    static func fraction(_ progress: BackupProgress) -> Double? {
        if progress.bytesTotal > 0 { return min(1, Double(progress.bytesDone) / Double(progress.bytesTotal)) }
        guard progress.total > 0 else { return nil }
        return min(1, Double(progress.done) / Double(progress.total))
    }
}

private struct MacBackgroundRow: View {
    let row: MacBackgroundJobs.Row

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.symbol)
                .font(.system(size: 13))
                .foregroundStyle(row.isWaiting ? Color.secondary : MacTheme.accent)
                .frame(width: 20, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if let detail = row.detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).monospacedDigit()
                }
                if row.isWaiting {
                    EmptyView()
                } else if let fraction = row.fraction {
                    ProgressView(value: fraction).progressViewStyle(.linear).tint(MacTheme.accent).controlSize(.mini)
                } else {
                    ProgressView().progressViewStyle(.linear).tint(MacTheme.accent).controlSize(.mini)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
