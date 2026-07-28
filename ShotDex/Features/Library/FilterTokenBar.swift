import SwiftUI

/// Capsule used by active search/filter bars. The visible xmark stays compact
/// while the native button keeps a 44pt touch target.
struct ActiveConditionChip: View {
    let label: String
    var removalAccessibilityLabel: String?
    var onRemove: (() -> Void)?

    var body: some View {
        if let onRemove {
            Button(action: onRemove) {
                chipContent(showsRemove: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(removalAccessibilityLabel ?? "Remove \(label)")
            .accessibilityHint("Removes this condition")
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
        .background(Color(.secondarySystemFill), in: Capsule())
        .frame(minHeight: 44)
        .contentShape(Capsule())
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
                .padding(.trailing, 8)
                .padding(.vertical, 6)
            }

            if !readOnly {
                HStack(spacing: 0) {
                    Divider()
                        .frame(height: 24)
                        .padding(.trailing, 12)

                    Button("Clear") {
                        criteria = .empty
                    }
                    .font(.footnote.weight(.medium))
                    .frame(minHeight: 44)
                }
                .padding(.trailing, 12)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
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
