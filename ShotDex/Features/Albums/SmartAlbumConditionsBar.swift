import SwiftUI

/// Read-only header shown atop a smart album's detail grid: the live match
/// count, the match mode when there is more than one rule, and each condition
/// rendered as a token. The editable counterpart is `SmartAlbumRuleRow`.
struct SmartAlbumConditionsBar: View {
    /// A condition the Filter menu added on top of the saved query (FS-06.09).
    struct FilterChip: Identifiable {
        var id: String
        var label: String
        var removalAccessibilityLabel: String
        var onRemove: () -> Void
    }

    let query: SmartAlbumQuery
    let matchCount: Int
    /// The saved query's own count, set while the Filter menu narrows the
    /// album: the header then reads "6 of 20 photos".
    var unfilteredCount: Int?
    /// Appended after the saved rules on the same row. They are glass and
    /// removable where the saved rules are flat and fixed — deliberately two
    /// looks on one line, so what belongs to the album and what is a passing
    /// filter can be told apart at a glance.
    var filterChips: [FilterChip] = []
    /// Source names by id, so a Source condition reads by name.
    var sourceNames: [String: String] = [:]
    /// The on-server check's progress under the conditions (FS-19.07 §7).
    var statusLines: [String] = []
    /// Checked out of total while the on-server check has photos left; the
    /// row then shows `Checking` and a bar instead of the sentence.
    var checkingFraction: Double?
    /// The original-on-device check's line (FS-06.10 §3), under the first
    /// on-server line, with the device's glyph so the two read apart.
    var originalLine: String?
    /// Keep in Photos (FS-06.12 §3), with the Move to Shared Library hint.
    var photosAlbumLine: PhotosAlbumSyncLine.Line?
    /// The album's name, drawn at the right end when the navigation bar
    /// shows none (regular width); its date line under it.
    var title: String?
    var subtitle: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var countsLineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 1 }
    /// Opens the album's editor — the popover's Edit button (FS-06.08 §3c D4).
    var onEditConditions: (() -> Void)?
    var onEditFilter: (() -> Void)?
    var onClearFilter: (() -> Void)?

    private var rules: [SmartAlbumRule] { query.validRules }

    @State private var isShowingStatus = false

    /// One row (user 2026-11-11: "the header still takes too much room —
    /// put the album name on the right, the count and the other numbers on
    /// the left, and drop words when it is long"): count and every status
    /// on the left, cut at the tail; the name and date on the right. The
    /// saved conditions and every status in full open from the left part.
    /// Filter chips, which can be removed, get a second row while a filter
    /// is on.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                summaryButton
                Spacer(minLength: 0)
                if let onClearFilter {
                    // The same capsule as AdvancedSearchBar's Edit/Clear.
                    HStack(spacing: 16) {
                        if let onEditFilter {
                            Button("Edit", action: onEditFilter)
                        }
                        Button("Clear", action: onClearFilter)
                    }
                    .font(.footnote.weight(.medium))
                    .tint(.primary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .glassBackground(Capsule())
                    .fixedSize(horizontal: true, vertical: false)
                }
                if let title {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(title)
                            .font(.headline)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    // The name is what the screen is: it keeps its width and
                    // the numbers give way.
                    .layoutPriority(1)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
            }
            .frame(minHeight: 44)
            if !filterChips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(filterChips) { chip in
                            ActiveConditionChip(
                                label: chip.label,
                                removalAccessibilityLabel: chip.removalAccessibilityLabel,
                                onRemove: chip.onRemove
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
        .background(.bar)
    }

    /// The saved rules, as one line each.
    private var ruleSummaries: [String] {
        rules.map { $0.displaySummary(naming: sourceNames) } + query.validGroups.map { $0.displaySummary(naming: sourceNames) }
    }

    private var countLabel: Text {
        if let unfilteredCount {
            return Text(verbatim: FilteredCountLabel.text(shown: matchCount, of: unfilteredCount))
        }
        return Text("\(matchCount) photo")
    }

    private func savedChip(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemFill), in: Capsule())
            .foregroundStyle(Color(.label))
    }

    /// One status and the glyph that tells it from the others.
    private struct StatusPart: Identifiable {
        var id: Int
        var symbol: String?
        var text: String
    }

    /// The counts, one per check: on server, original on this device, Keep
    /// in Photos.
    private var statusParts: [StatusPart] {
        var parts: [StatusPart] = []
        if let first = statusLines.first { parts.append(StatusPart(id: 0, symbol: nil, text: first)) }
        if let originalLine { parts.append(StatusPart(id: 1, symbol: Self.deviceSymbol, text: originalLine)) }
        if let photosAlbumLine { parts.append(StatusPart(id: 2, symbol: "rectangle.stack", text: photosAlbumLine.text)) }
        return parts
    }

    /// The sentences behind the line: a mismatch names a device (§12.4),
    /// edits missing on the server, the Shared Library hint.
    private var statusNotes: [String] {
        Array(statusLines.dropFirst()) + (photosAlbumLine?.showsHint == true ? [PhotosAlbumSyncLine.hint] : [])
    }

    /// Count first, then every status, on one line cut at the tail; tapped,
    /// it opens the rules and every status in full.
    private var summaryButton: some View {
        Button {
            isShowingStatus = true
        } label: {
            // Short (user 2026-11-11: "too much text — Checking and a
            // progress bar is enough"): the count, then `Checking` with a
            // bar while photos are left, else the check's own short line
            // (`Checked 3 min ago`, a wait). Everything else is in the popover.
            HStack(spacing: 8) {
                countLabel
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                    .fixedSize()
                if let checkingFraction {
                    Text("Checking", comment: "Smart album header: the on-server check has photos left; a progress bar follows")
                        .font(.caption)
                        .lineLimit(1)
                        .fixedSize()
                    ProgressView(value: checkingFraction)
                        .progressViewStyle(.linear)
                        .frame(minWidth: 40, maxWidth: 120)
                        .accessibilityHidden(true)
                } else if let first = statusLines.first {
                    Text(first)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: statusNotes.isEmpty && statusParts.count < 2 ? "chevron.down" : "info.circle")
                    .imageScale(.small)
                    .font(.caption)
                    .foregroundStyle(statusNotes.isEmpty && statusParts.count < 2 ? Color(.tertiaryLabel) : Color.accentColor)
                    .accessibilityHidden(true)
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(([countText] + statusParts.map(\.text) + statusNotes).joined(separator: ". ").replacingOccurrences(of: " · ", with: ", "))
        .accessibilityHint(Text("Shows the album's conditions and each status in full", comment: "Smart album header: the summary line opens its details"))
        .accessibilityAddTraits(.updatesFrequently)
        .popover(isPresented: $isShowingStatus, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Conditions", comment: "Smart album header popover: the saved rules")
                            .font(.footnote.weight(.semibold))
                        Spacer()
                        if rules.count + query.validGroups.count > 1 {
                            Text("Match \(query.matchMode.word)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        if let onEditConditions {
                            // The saved conditions are one tap from their
                            // editor, as in Photos (FS-06.08 §3c D4).
                            Button {
                                isShowingStatus = false
                                onEditConditions()
                            } label: {
                                Text(String(localized: "Edit…", comment: "Smart album header popover: opens Edit Smart Album"))
                                    .font(.footnote.weight(.semibold))
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(String(localized: "Edit Smart Album", comment: "VoiceOver: the popover's Edit button"))
                        }
                    }
                    ForEach(Array(ruleSummaries.enumerated()), id: \.offset) { _, summary in
                        savedChip(summary)
                    }
                }
                if !statusLines.isEmpty {
                    OnServerActivityView()
                }
                if !statusParts.isEmpty || !statusNotes.isEmpty {
                    Divider()
                    ForEach(statusParts) { part in
                        Label {
                            Text(part.text)
                        } icon: {
                            Image(systemName: part.symbol ?? "server.rack")
                        }
                    }
                    ForEach(Array(statusNotes.enumerated()), id: \.offset) { _, note in
                        Text(note).foregroundStyle(.secondary)
                    }
                }
            }
            .font(.footnote)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 380, alignment: .leading)
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
    }

    private var countText: String {
        if let unfilteredCount { return FilteredCountLabel.text(shown: matchCount, of: unfilteredCount) }
        return String(localized: "\(matchCount) photo")
    }

}

extension SmartAlbumConditionsBar {
    /// The glyph of the device the originals are checked on.
    static var deviceSymbol: String {
        #if os(macOS)
        "laptopcomputer"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        #endif
    }
}

/// What the on-server check is doing now, read once a second: the file it
/// downloads from iCloud or reads off the server, how far, and how fast.
struct OnServerActivityView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let now = OnServerActivity.shared.current, let line = Self.title(now) {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line)
                                .lineLimit(2)
                            if let detail = Self.detail(now, at: context.date) {
                                Text(detail)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: Self.symbol(now.kind))
                    }
                    if let total = now.bytesTotal, total > 0 {
                        ProgressView(value: Double(min(now.bytesDone, total)), total: Double(total))
                            .progressViewStyle(.linear)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func title(_ now: OnServerActivity.Snapshot) -> String? {
        switch now.kind {
        case .listing(let source):
            String(localized: "Listing files on \(source)", comment: "On-server check popover: the server's file list is being read")
        case .downloading where now.otherFiles > 0:
            String(localized: "Downloading from iCloud: \(now.fileName ?? "") and \(now.otherFiles) more",
                   comment: "On-server check popover: several Photos originals downloading at once — the newest file name and how many others")
        case .downloading:
            String(localized: "Downloading from iCloud: \(now.fileName ?? "")",
                   comment: "On-server check popover: a Photos original being downloaded to compare it, with its file name")
        case .reading:
            String(localized: "Reading from the server: \(now.fileName ?? "")",
                   comment: "On-server check popover: a server file being read to compare it, with its file name")
        case .working(let what):
            what.isEmpty ? nil : what
        }
    }

    /// `1.2 MB of 3.4 MB · 850 KB/s`, or how long a listing has taken.
    static func detail(_ now: OnServerActivity.Snapshot, at date: Date) -> String? {
        var parts: [String] = []
        if case .listing = now.kind {
            let seconds = Int(date.timeIntervalSince(now.startedAt))
            parts.append(Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
        } else if let total = now.bytesTotal, total > 0 {
            parts.append(String(localized: "\(now.bytesDone.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))",
                                comment: "On-server check popover: bytes done of the file's size"))
        }
        if let rate = now.bytesPerSecond, rate > 0, now.fileName != nil {
            parts.append(String(localized: "\(Int64(rate).formatted(.byteCount(style: .file)))/s",
                                comment: "On-server check popover: network speed"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func symbol(_ kind: OnServerActivity.Kind) -> String {
        switch kind {
        case .listing: "list.bullet"
        case .downloading: "icloud.and.arrow.down"
        case .reading: "server.rack"
        case .working: "gearshape"
        }
    }
}
