import SwiftUI

/// Horizontal tokens describing the active filter conditions, with the
/// match count and a Clear All button.
struct FilterTokenBar: View {
    @Binding var criteria: FilterCriteria
    let matchCount: Int
    /// Read-only header (smart-album detail): show conditions but hide the
    /// Clear All button and disable tap-to-remove.
    var readOnly = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("\(matchCount) photos")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(tokens, id: \.label) { token in
                    tokenView(token)
                }

                if !readOnly {
                    Button("Clear All") {
                        criteria = .empty
                    }
                    .font(.footnote.weight(.medium))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    private struct FilterToken {
        var label: String
        var clear: (inout FilterCriteria) -> Void
    }

    private func tokenView(_ token: FilterToken) -> some View {
        HStack(spacing: 4) {
            Text(token.label)
                .lineLimit(1)
            if !readOnly {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .onTapGesture {
            guard !readOnly else { return }
            var updated = criteria
            token.clear(&updated)
            criteria = updated
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter: \(token.label)")
        .accessibilityHint(readOnly ? "" : "Double tap to remove")
        .accessibilityAddTraits(readOnly ? [] : .isButton)
    }

    private var tokens: [FilterToken] {
        var result: [FilterToken] = []
        for brand in criteria.cameraBrands.sorted() {
            result.append(FilterToken(label: brand) { $0.cameraBrands.remove(brand) })
        }
        for body in criteria.cameraBodies.sorted() {
            result.append(FilterToken(label: body) { $0.cameraBodies.remove(body) })
        }
        for lens in criteria.lenses.sorted() {
            result.append(FilterToken(label: lens) { $0.lenses.remove(lens) })
        }
        for format in criteria.sensorFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(FilterToken(label: format.displayName) { $0.sensorFormats.remove(format) })
        }
        // Free-typed contains-terms (from smart albums): show so the applied
        // LIKE conditions are visible and individually removable.
        for term in criteria.cameraBrandTerms {
            result.append(FilterToken(label: "Brand: \(term)") { $0.cameraBrandTerms.removeAll { $0 == term } })
        }
        for term in criteria.cameraBodyTerms {
            result.append(FilterToken(label: "Camera: \(term)") { $0.cameraBodyTerms.removeAll { $0 == term } })
        }
        for term in criteria.lensTerms {
            result.append(FilterToken(label: "Lens: \(term)") { $0.lensTerms.removeAll { $0 == term } })
        }
        if !criteria.isoRange.isEmpty {
            result.append(FilterToken(label: rangeLabel("ISO", criteria.isoRange, format: { String(Int($0)) })) {
                $0.isoRange = NumericRangeFilter()
            })
        }
        if !criteria.shutterRange.isEmpty {
            result.append(FilterToken(label: rangeLabel("Shutter", criteria.shutterRange, format: {
                FormatUtils.shutterSpeed($0) ?? String($0)
            })) {
                $0.shutterRange = NumericRangeFilter()
            })
        }
        if !criteria.apertureRange.isEmpty {
            result.append(FilterToken(label: rangeLabel("Aperture", criteria.apertureRange, format: {
                FormatUtils.aperture($0) ?? String($0)
            })) {
                $0.apertureRange = NumericRangeFilter()
            })
        }
        if !criteria.focalRange.isEmpty {
            let prefix = criteria.focalLengthMode == .equivalent ? "FF Eq." : "Focal"
            result.append(FilterToken(label: rangeLabel(prefix, criteria.focalRange, format: {
                FormatUtils.focalLength($0) ?? String($0)
            })) {
                $0.focalRange = NumericRangeFilter()
            })
        }
        if let text = criteria.searchText, !text.isEmpty {
            result.append(FilterToken(label: "“\(text)”") { $0.searchText = nil })
        }
        return result
    }

    private func rangeLabel(
        _ prefix: String,
        _ range: NumericRangeFilter,
        format: (Double) -> String
    ) -> String {
        switch (range.lowerBound, range.upperBound) {
        case let (.some(lower), .some(upper)):
            return "\(prefix) \(format(lower))–\(format(upper))"
        case let (.some(lower), nil):
            return "\(prefix) ≥ \(format(lower))"
        case let (nil, .some(upper)):
            return "\(prefix) ≤ \(format(upper))"
        default:
            return prefix
        }
    }
}
