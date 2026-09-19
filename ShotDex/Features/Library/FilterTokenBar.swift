import SwiftUI

/// Capsule used by active search/filter bars. The visible xmark stays compact
/// while the native button keeps a 44pt touch target.
struct ActiveConditionChip: View {
    let label: String
    var removalAccessibilityLabel: String?
    var onRemove: (() -> Void)?
    /// A chip that does something other than remove itself (the match-mode
    /// switch). Mutually exclusive with `onRemove`.
    var onTap: (() -> Void)?
    /// Full-strength label. A chip that carries a condition is the content;
    /// one that carries a setting about the conditions reads a step quieter.
    var isEmphasised = true

    /// How far the chip row dissolves at its trailing edge, and therefore how
    /// much room the row leaves after its last chip so that chip can still be
    /// scrolled out of the fade.
    static let scrollFadeWidth: CGFloat = 28

    var body: some View {
        if let onRemove {
            Button(action: onRemove) {
                chipContent(showsRemove: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removalAccessibilityLabel ?? "Remove \(label)")
            .accessibilityHint("Removes this condition")
        } else if let onTap {
            Button(action: onTap) {
                chipContent(showsRemove: false)
            }
            .buttonStyle(.plain)
        } else {
            chipContent(showsRemove: false)
                .accessibilityLabel(label)
        }
    }

    private func chipContent(showsRemove: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.footnote)
                .lineLimit(1)
                .foregroundStyle(isEmphasised ? Color(.label) : Color(.secondaryLabel))

            if showsRemove {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, showsRemove ? 10 : 12)
        .padding(.vertical, 7)
        // Glass, not a flat fill: the bar these chips sit in has no background
        // of its own, so a chip floats directly over the photos and a
        // translucent system fill all but disappears against a bright one.
        .glassBackground(Capsule())
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
}

extension View {
    /// Dissolves the trailing edge of a horizontally scrolling chip row.
    ///
    /// The row ends right beside the pinned Edit/Clear capsule, and a chip cut
    /// off there by a straight edge reads as a chip *hidden behind the buttons*
    /// — which is what it looked like. A fade reads as a row that keeps going,
    /// and it is the only affordance a scroll view without a scroll bar has.
    /// It costs nothing when the chips fit: there is no content at that edge to
    /// fade out.
    func fadingTrailingEdge(_ width: CGFloat = ActiveConditionChip.scrollFadeWidth) -> some View {
        mask {
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(
                    colors: [.black, .black.opacity(0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: width)
            }
        }
    }
}

/// Horizontal chips describing active search and filter conditions, with a
/// trailing Clear button that stays outside the scroll view.
struct FilterTokenBar: View {
    @Binding var criteria: FilterCriteria
    /// Read-only header (smart-album detail): show conditions but hide Clear
    /// and disable removal.
    var readOnly = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tokens) { token in
                        if readOnly {
                            ActiveConditionChip(label: token.label)
                        } else {
                            ActiveConditionChip(
                                label: token.label,
                                removalAccessibilityLabel: token.removalAccessibilityLabel,
                                onRemove: { remove(token) }
                            )
                        }
                    }
                }
                .padding(.leading)
                .padding(.trailing, ActiveConditionChip.scrollFadeWidth)
                .padding(.vertical, 6)
            }
            .fadingTrailingEdge()

            if !readOnly {
                Button("Clear") {
                    criteria = .empty
                }
                .font(.footnote.weight(.medium))
                .tint(.primary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .glassBackground(Capsule())
                .padding(.trailing, AppTheme.Size.floatingChromeMargin)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
        }
        // No background. The bar is floating chrome over the grid, like the
        // toolbar above it: a full-width fill — opaque or glass — draws a band
        // with a cut edge across the photos, and a second one against the
        // toolbar's own transparent strip, which is the seam Photos does not
        // have. The grid keeps its first row clear of the chips through its top
        // content inset instead (see `LibraryScreen.photoGrid`), and Clear
        // carries its own glass capsule so it stays legible once photos do
        // scroll behind it.
    }

    private struct FilterToken: Identifiable {
        var id: String
        var label: String
        var removalAccessibilityLabel: String
        var clear: (inout FilterCriteria) -> Void
    }

    private func remove(_ token: FilterToken) {
        var updated = criteria
        token.clear(&updated)
        criteria = updated
    }

    private var tokens: [FilterToken] {
        var result: [FilterToken] = []
        for brand in criteria.cameraBrands.sorted() {
            result.append(
                FilterToken(
                    id: "brand-\(brand)",
                    label: brand,
                    removalAccessibilityLabel: "Remove camera brand filter \(brand)"
                ) { $0.cameraBrands.remove(brand) }
            )
        }
        for body in criteria.cameraBodies.sorted() {
            result.append(
                FilterToken(
                    id: "body-\(body)",
                    label: body,
                    removalAccessibilityLabel: "Remove camera filter \(body)"
                ) { $0.cameraBodies.remove(body) }
            )
        }
        for lens in criteria.lenses.sorted() {
            result.append(
                FilterToken(
                    id: "lens-\(lens)",
                    label: lens,
                    removalAccessibilityLabel: "Remove lens filter \(lens)"
                ) { $0.lenses.remove(lens) }
            )
        }
        for format in criteria.sensorFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(
                FilterToken(
                    id: "sensor-\(format.rawValue)",
                    label: format.displayName,
                    removalAccessibilityLabel: "Remove sensor format filter \(format.displayName)"
                ) { $0.sensorFormats.remove(format) }
            )
        }

        // Free-typed contains terms remain individually editable without the
        // verbose "Brand:" / "Camera:" / "Lens:" prefixes.
        for (index, term) in criteria.cameraBrandTerms.enumerated() {
            result.append(
                FilterToken(
                    id: "brand-term-\(index)-\(term)",
                    label: term,
                    removalAccessibilityLabel: "Remove camera brand search term \(term)"
                ) { $0.cameraBrandTerms.removeAll { $0 == term } }
            )
        }
        for (index, term) in criteria.cameraBodyTerms.enumerated() {
            result.append(
                FilterToken(
                    id: "body-term-\(index)-\(term)",
                    label: term,
                    removalAccessibilityLabel: "Remove camera search term \(term)"
                ) { $0.cameraBodyTerms.removeAll { $0 == term } }
            )
        }
        for (index, term) in criteria.lensTerms.enumerated() {
            result.append(
                FilterToken(
                    id: "lens-term-\(index)-\(term)",
                    label: term,
                    removalAccessibilityLabel: "Remove lens search term \(term)"
                ) { $0.lensTerms.removeAll { $0 == term } }
            )
        }

        if !criteria.isoRange.isEmpty {
            result.append(
                FilterToken(
                    id: "iso",
                    label: rangeLabel("ISO", criteria.isoRange) { NumericFieldKind.int.format($0) },
                    removalAccessibilityLabel: "Remove ISO filter"
                ) { $0.isoRange = NumericRangeFilter() }
            )
        }
        if !criteria.shutterRange.isEmpty {
            result.append(
                FilterToken(
                    id: "shutter",
                    label: rangeLabel("shutter", criteria.shutterRange) {
                        MetadataFormatter.shutterSpeed($0) ?? String($0)
                    },
                    removalAccessibilityLabel: "Remove shutter speed filter"
                ) { $0.shutterRange = NumericRangeFilter() }
            )
        }
        if !criteria.apertureRange.isEmpty {
            result.append(
                FilterToken(
                    id: "aperture",
                    label: rangeLabel("f", criteria.apertureRange) { NumericFieldKind.double.format($0) },
                    removalAccessibilityLabel: "Remove aperture filter"
                ) { $0.apertureRange = NumericRangeFilter() }
            )
        }
        if !criteria.focalRange.isEmpty {
            let prefix = criteria.focalLengthMode == .equivalent ? "focal eq" : "focal"
            result.append(
                FilterToken(
                    id: "focal",
                    label: rangeLabel(prefix, criteria.focalRange) {
                        MetadataFormatter.focalLength($0) ?? String($0)
                    },
                    removalAccessibilityLabel: "Remove focal length filter"
                ) { $0.focalRange = NumericRangeFilter() }
            )
        }
        for kind in criteria.mediaKinds.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(
                FilterToken(
                    id: "media-\(kind.rawValue)",
                    label: kind.displayName,
                    removalAccessibilityLabel: "Remove media type filter \(kind.displayName)"
                ) { $0.mediaKinds.remove(kind) }
            )
        }
        for subtype in criteria.mediaSubtypes.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(
                FilterToken(
                    id: "subtype-\(subtype.rawValue)",
                    label: subtype.title,
                    removalAccessibilityLabel: "Remove capture kind filter \(subtype.title)"
                ) { $0.mediaSubtypes.remove(subtype) }
            )
        }
        if criteria.favoritesOnly {
            result.append(
                FilterToken(
                    id: "favorite",
                    label: "Favorite",
                    removalAccessibilityLabel: "Remove favorite filter"
                ) { $0.favoritesOnly = false }
            )
        }
        if let text = criteria.searchText, !text.isEmpty {
            for (index, term) in SearchParser.editableTokens(in: text).enumerated() {
                result.append(
                    FilterToken(
                        id: "search-\(index)-\(term)",
                        label: term,
                        removalAccessibilityLabel: "Remove search term \(term)"
                    ) {
                        $0.searchText = SearchParser.removingEditableToken(at: index, from: text)
                    }
                )
            }
        }
        return result
    }

    private func rangeLabel(
        _ prefix: String,
        _ range: NumericRangeFilter,
        format: (Double) -> String
    ) -> String {
        switch (range.lowerBound, range.upperBound) {
        case let (lower?, upper?) where lower == upper:
            return "\(prefix) \(format(lower))"
        case let (lower?, upper?):
            return "\(prefix) \(format(lower))–\(format(upper))"
        case let (lower?, nil):
            return "\(prefix) ≥ \(format(lower))"
        case let (nil, upper?):
            return "\(prefix) ≤ \(format(upper))"
        case (nil, nil):
            return prefix
        }
    }
}
