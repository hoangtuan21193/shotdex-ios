import SwiftUI

/// Horizontal chips describing the active filter conditions, with the
/// match count and a Clear All button.
struct FilterChipsBar: View {
    @Binding var criteria: FilterCriteria
    let matchCount: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text("\(matchCount) photos")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)

                ForEach(chips, id: \.label) { chip in
                    chipView(chip)
                }

                Button("Clear All") {
                    criteria = .empty
                }
                .font(.footnote.weight(.medium))
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.systemBackground))
    }

    private struct Chip {
        var label: String
        var clear: (inout FilterCriteria) -> Void
    }

    private func chipView(_ chip: Chip) -> some View {
        HStack(spacing: 4) {
            Text(chip.label)
                .lineLimit(1)
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .onTapGesture {
            var updated = criteria
            chip.clear(&updated)
            criteria = updated
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Filter: \(chip.label)")
        .accessibilityHint("Double tap to remove")
        .accessibilityAddTraits(.isButton)
    }

    private var chips: [Chip] {
        var result: [Chip] = []
        for brand in criteria.cameraBrands.sorted() {
            result.append(Chip(label: brand) { $0.cameraBrands.remove(brand) })
        }
        for body in criteria.cameraBodies.sorted() {
            result.append(Chip(label: body) { $0.cameraBodies.remove(body) })
        }
        for lens in criteria.lenses.sorted() {
            result.append(Chip(label: lens) { $0.lenses.remove(lens) })
        }
        for format in criteria.sensorFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(Chip(label: format.displayName) { $0.sensorFormats.remove(format) })
        }
        if !criteria.isoRange.isEmpty {
            result.append(Chip(label: rangeLabel("ISO", criteria.isoRange, format: { String(Int($0)) })) {
                $0.isoRange = NumericRangeFilter()
            })
        }
        if !criteria.shutterRange.isEmpty {
            result.append(Chip(label: rangeLabel("Shutter", criteria.shutterRange, format: {
                FormatUtils.shutterSpeed($0) ?? String($0)
            })) {
                $0.shutterRange = NumericRangeFilter()
            })
        }
        if !criteria.apertureRange.isEmpty {
            result.append(Chip(label: rangeLabel("Aperture", criteria.apertureRange, format: {
                FormatUtils.aperture($0) ?? String($0)
            })) {
                $0.apertureRange = NumericRangeFilter()
            })
        }
        if !criteria.focalRange.isEmpty {
            let prefix = criteria.focalLengthMode == .equivalent ? "FF Eq." : "Focal"
            result.append(Chip(label: rangeLabel(prefix, criteria.focalRange, format: {
                FormatUtils.focalLength($0) ?? String($0)
            })) {
                $0.focalRange = NumericRangeFilter()
            })
        }
        if let text = criteria.searchText, !text.isEmpty {
            result.append(Chip(label: "“\(text)”") { $0.searchText = nil })
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
