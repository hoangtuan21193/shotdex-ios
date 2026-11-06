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
    /// The original-on-device check's line (FS-06.10 §3), under the first
    /// on-server line, with the device's glyph so the two read apart.
    var originalLine: String?
    /// Keep in Photos (FS-06.12 §3), with the Move to Shared Library hint.
    var photosAlbumLine: PhotosAlbumSyncLine.Line?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var countsLineLimit: Int? { dynamicTypeSize.isAccessibilitySize ? nil : 1 }
    var onEditFilter: (() -> Void)?
    var onClearFilter: (() -> Void)?

    private var rules: [SmartAlbumRule] { query.validRules }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let unfilteredCount {
                    Text(FilteredCountLabel.text(shown: matchCount, of: unfilteredCount))
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("\(matchCount) photo")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
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
                if rules.count > 1 {
                    Text("Match \(query.matchMode.word)")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(rules) { rule in
                        Text(rule.displaySummary(naming: sourceNames))
                            .font(.footnote)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemFill), in: Capsule())
                            .foregroundStyle(Color(.label))
                    }
                    ForEach(filterChips) { chip in
                        ActiveConditionChip(
                            label: chip.label,
                            removalAccessibilityLabel: chip.removalAccessibilityLabel,
                            onRemove: chip.onRemove
                        )
                    }
                }
            }
            if !statusLines.isEmpty || originalLine != nil || photosAlbumLine != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let first = statusLines.first {
                        // The first line is counts and keeps to one — at
                        // accessibility sizes it wraps rather than lose the
                        // count; the sentences after it (a mismatch names a
                        // device, §12.4) always wrap.
                        Text(first)
                            .lineLimit(countsLineLimit)
                            .truncationMode(.tail)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    if let originalLine {
                        // Its own element: the two checks tick apart.
                        Label(originalLine, systemImage: Self.deviceSymbol)
                            .labelStyle(StatusLineLabelStyle())
                            .lineLimit(countsLineLimit)
                            .truncationMode(.tail)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(originalLine.replacingOccurrences(of: " · ", with: ", "))
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                    ForEach(Array(statusLines.dropFirst().enumerated()), id: \.offset) { _, line in
                        Text(line)
                    }
                    if let photosAlbumLine {
                        Label(photosAlbumLine.text, systemImage: "rectangle.stack")
                            .labelStyle(StatusLineLabelStyle())
                            .lineLimit(countsLineLimit)
                            .truncationMode(.tail)
                            .accessibilityAddTraits(.updatesFrequently)
                        if photosAlbumLine.showsHint {
                            Text(PhotosAlbumSyncLine.hint)
                        }
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
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

/// A status line's glyph sits tight against its text, at the text's size.
private struct StatusLineLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
    }
}
