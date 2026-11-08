import SwiftUI

/// A smart album's header in the Library window (board `MAC_SmartAlbum`,
/// FS-19.07 §11): its conditions as chips — a click opens the editor — and
/// the count on the left, the On Server and originals lines on the right.
/// The album itself is the Library grid on `LibraryPlace.rules`, so it has
/// the Library's toolbar, list, filter, share, inspector, viewer and the
/// delete that asks the server first (§9).
struct MacSmartAlbumHeader: View {
    let album: SmartAlbum
    /// What the grid shows while a filter or search narrows the album; nil
    /// when it shows the whole album.
    let shown: Int?
    /// The Library's rows: a delete or an index pass changes the album.
    let generation: Int
    let edit: () -> Void
    /// The originals check moved photos in or out (FS-06.10 §3): read again.
    let reload: () -> Void
    @Environment(MacDependencies.self) private var dependencies
    @State private var sourceNames: [String: String] = [:]
    @State private var onServerLines: [String] = []
    /// When an `Original is …` album last read again for the check.
    @State private var lastOriginalReload = Date.distantPast
    /// The check pass the grid last read again for: a task restarted for
    /// another reason (names read) does not reload.
    @State private var reloadedGeneration = 0
    /// The album whose opening already asked the check for a pass.
    @State private var kickedAlbumId: String?
    /// The album's own size, whatever narrows the grid.
    @State private var total: Int?

    var body: some View {
        // Chips and count centred on the lines at the right, one or three (board).
        HStack(alignment: .center, spacing: 8) {
            ForEach(album.query.validRules) { rule in
                chip(rule.displaySummary(naming: sourceNames), symbol: symbol(rule.field))
            }
            // A nested group: one chip, its conditions joined by its and/or.
            ForEach(album.query.validGroups) { group in
                chip(group.displaySummary(naming: sourceNames), symbol: "line.3.horizontal.decrease")
            }
            Text(countLine)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .frame(height: 24)
                .padding(.leading, 4)
            // Said, not only hinted on the chips: the conditions can be changed here.
            Button(String(localized: "Edit…", comment: "Mac smart album header: edit the conditions"), action: edit)
                .buttonStyle(.link)
                .font(.system(size: 13))
                .frame(height: 24)
                .help(String(localized: "Edit Smart Album…", comment: "Mac: edit the open smart album"))
            Spacer(minLength: 12)
            if !onServerLines.isEmpty || originalCheck != nil {
                VStack(alignment: .trailing, spacing: 1) {
                    // The counts keep to one line; the sentences after them
                    // (a hash mismatch names a device, FS-19.07 §12.4) wrap.
                    if let first = onServerLines.first {
                        // A click shows what the check is doing (Activity › Background).
                        Button {
                            MacWindowRequest.showsActivity = true
                            NotificationCenter.default.post(name: .macShowActivity, object: nil)
                        } label: {
                            HStack(spacing: 4) {
                                Text(first).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Show what the check is doing", comment: "Mac smart album: the On Server line opens Activity"))
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    // The originals check, under the On Server counts
                    // (FS-06.10 §3): its own element, the two tick apart.
                    if let originalCheck {
                        HStack(spacing: 6) {
                            originalGlyph(originalCheck)
                            Text(originalCheck.line).lineLimit(1)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(originalCheck.line.replacingOccurrences(of: " · ", with: ", "))
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    ForEach(Array(onServerLines.dropFirst().enumerated()), id: \.offset) { _, line in
                        Text(line).multilineTextAlignment(.trailing)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider() }
        // The album's size: again when its rules or the Library's rows change.
        .task(id: TotalKey(query: album.query, generation: generation)) {
            let queries = dependencies.libraryQueries
            let query = album.query
            total = try? await queries.count(matching: query)
        }
        .task(id: album.query) {
            let store = SourceStore(database: dependencies.database)
            sourceNames = await Task.detached {
                Dictionary(((try? store.sources()) ?? []).map { ($0.id, $0.name) }) { first, _ in first }
            }.value
        }
        // The check's progress: again on each of its passes.
        .task(id: OnServerKey(query: album.query, generation: dependencies.onServerCheck.generation, rows: generation, names: sourceNames)) {
            onServerLines = await SmartAlbumDetailModel.onServerLines(
                query: album.query, check: dependencies.onServerCheck, database: dependencies.database,
                sourceNames: sourceNames, isLimited: dependencies.photoLibrary.authorizationState == .limited)
            // Only an album with a server condition moves with the check, once per pass batch.
            // An album that asks about a server starts a pass if none runs (user 2026-11-08).
            if !onServerLines.isEmpty, kickedAlbumId != album.id {
                kickedAlbumId = album.id
                dependencies.backupControl.appCameForward()
            }
            let generation = dependencies.onServerCheck.generation
            if !onServerLines.isEmpty, generation > 0, generation != reloadedGeneration {
                reloadedGeneration = generation
                reload()
            }
        }
        // An album on the Original rule asks for fresh answers (FS-06.10 §4)
        // for as long as it is open — keyed by album, because the sidebar
        // swaps albums in this same view without a disappear.
        .task(id: album.id) {
            guard album.query.usesOriginal else { return }
            let check = dependencies.originalPresenceCheck
            check.screenOpened()
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            check.screenClosed()
        }
        // Each batch of the original check can move photos in or out (§3).
        // At most one reload every 3 s: a pass runs ~275 batches.
        .task(id: album.query.usesOriginal ? dependencies.originalPresenceCheck.generation : 0) {
            guard album.query.usesOriginal else { return }
            let wait = 3 - Date().timeIntervalSince(lastOriginalReload)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            lastOriginalReload = Date()
            reload()
        }
    }

    private struct OnServerKey: Equatable {
        let query: SmartAlbumQuery
        let generation: Int
        /// A delete changes the counts before the next check pass.
        let rows: Int
        let names: [String: String]
    }

    private struct TotalKey: Equatable {
        let query: SmartAlbumQuery
        let generation: Int
    }

    /// "40 photos"; "12 of 40 photos" while a filter or search narrows the grid.
    private var countLine: String {
        guard let total else { return shown.map { "\($0.formatted())" } ?? "" }
        if let shown, shown != total {
            return String(localized: "\(shown.formatted()) of \(total.formatted()) photos",
                          comment: "Mac smart album header: photos shown by a filter of the album's")
        }
        return total == 1 ? String(localized: "1 photo", comment: "Mac toolbar subtitle")
                          : String(localized: "\(total.formatted()) photos", comment: "Mac toolbar subtitle")
    }

    /// A condition, read-only (board): a click opens the editor on it.
    private func chip(_ text: String, symbol: String) -> some View {
        Button(action: edit) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(text).font(.system(size: 12)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(MacTheme.fill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Condition: \(text)", comment: "Mac smart album: a condition chip; the condition"))
        .help(String(localized: "Edit Smart Album…", comment: "Mac: edit the open smart album"))
    }

    private func symbol(_ field: RuleField) -> String {
        switch field {
        case .alsoOnServer, .source: "externaldrive.connected.to.line.below"
        case .original: "icloud"
        default: "line.3.horizontal.decrease"
        }
    }

    /// The original check's line and how far it is, for an album on the
    /// Original rule (FS-06.10 §3).
    private var originalCheck: (line: String, fraction: Double?)? {
        guard album.query.usesOriginal else { return nil }
        let check = dependencies.originalPresenceCheck
        let finishedAt = check.pass?.finishedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        let line = OriginalPresenceProgressLine.text(checked: check.progress.checked, total: check.progress.total,
                                                     finishedAt: finishedAt)
        let isDone = finishedAt != nil && check.progress.checked >= check.progress.total
        let fraction = check.progress.total > 0 ? min(1, Double(check.progress.checked) / Double(check.progress.total)) : 0
        return (line, isDone ? nil : fraction)
    }

    /// A ring while the check runs, a check mark once it is through (board
    /// `MAC_SmartAlbum`, `original` tweak).
    @ViewBuilder
    private func originalGlyph(_ check: (line: String, fraction: Double?)) -> some View {
        if let fraction = check.fraction {
            ZStack {
                Circle().stroke(MacTheme.fill2, lineWidth: 1.5)
                Circle().trim(from: 0, to: fraction)
                    .stroke(MacTheme.accent, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 12, height: 12)
            .accessibilityHidden(true)
        } else {
            // The ring's 12 pt box, so the text does not move when it turns.
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 12, height: 12)
                .accessibilityHidden(true)
        }
    }
}
