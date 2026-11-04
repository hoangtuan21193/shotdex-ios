import Foundation

/// One active quick-filter condition as a removable chip: the Library's
/// token bar and the smart album's conditions bar on iOS, the filter bar on
/// the Mac (FS-18.02 §5). Apart from SwiftUI so both platforms — and the
/// tests — read the same list.
///
/// `label` is the iOS chip, one string ("ISO 3200–12800"). The Mac chip
/// splits it into a dim `field` and the `value` (board `MAC_FilterPopover`:
/// "Camera  Canon EOS R6 Mark II"); a condition that names itself ("Picks",
/// "★ ≥ 3") has no field.
struct ActiveFilterToken: Identifiable {
    var id: String
    var label: String
    var field: String?
    var value: String
    var removalAccessibilityLabel: String
    var clear: (inout FilterCriteria) -> Void

    init(
        id: String,
        label: String,
        field: String? = nil,
        value: String? = nil,
        removalAccessibilityLabel: String,
        clear: @escaping (inout FilterCriteria) -> Void
    ) {
        self.id = id
        self.label = label
        self.field = field
        self.value = value ?? label
        self.removalAccessibilityLabel = removalAccessibilityLabel
        self.clear = clear
    }

    /// Every condition `criteria` holds, in chip order.
    static func tokens(for criteria: FilterCriteria) -> [ActiveFilterToken] {
        var result: [ActiveFilterToken] = []
        let brandField = String(localized: "Brand", comment: "Mac filter bar chip key: camera brand")
        let cameraField = String(localized: "Camera", comment: "Mac filter bar chip key: camera body")
        let lensField = String(localized: "Lens", comment: "Mac filter bar chip key: lens")
        for brand in criteria.cameraBrands.sorted() {
            result.append(
                ActiveFilterToken(
                    id: "brand-\(brand)",
                    label: brand,
                    field: brandField,
                    removalAccessibilityLabel: "Remove camera brand filter \(brand)"
                ) { $0.cameraBrands.remove(brand) }
            )
        }
        for body in criteria.cameraBodies.sorted() {
            result.append(
                ActiveFilterToken(
                    id: "body-\(body)",
                    label: body,
                    field: cameraField,
                    removalAccessibilityLabel: "Remove camera filter \(body)"
                ) { $0.cameraBodies.remove(body) }
            )
        }
        for lens in criteria.lenses.sorted() {
            result.append(
                ActiveFilterToken(
                    id: "lens-\(lens)",
                    label: lens,
                    field: lensField,
                    removalAccessibilityLabel: "Remove lens filter \(lens)"
                ) { $0.lenses.remove(lens) }
            )
        }
        for format in criteria.sensorFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(
                ActiveFilterToken(
                    id: "sensor-\(format.rawValue)",
                    label: format.displayName,
                    field: String(localized: "Sensor", comment: "Mac filter bar chip key: sensor format"),
                    removalAccessibilityLabel: "Remove sensor format filter \(format.displayName)"
                ) { $0.sensorFormats.remove(format) }
            )
        }

        // Free-typed contains terms remain individually editable without the
        // verbose "Brand:" / "Camera:" / "Lens:" prefixes.
        for (index, term) in criteria.cameraBrandTerms.enumerated() {
            result.append(
                ActiveFilterToken(
                    id: "brand-term-\(index)-\(term)",
                    label: term,
                    field: brandField,
                    removalAccessibilityLabel: "Remove camera brand search term \(term)"
                ) { $0.cameraBrandTerms.removeAll { $0 == term } }
            )
        }
        for (index, term) in criteria.cameraBodyTerms.enumerated() {
            result.append(
                ActiveFilterToken(
                    id: "body-term-\(index)-\(term)",
                    label: term,
                    field: cameraField,
                    removalAccessibilityLabel: "Remove camera search term \(term)"
                ) { $0.cameraBodyTerms.removeAll { $0 == term } }
            )
        }
        for (index, term) in criteria.lensTerms.enumerated() {
            result.append(
                ActiveFilterToken(
                    id: "lens-term-\(index)-\(term)",
                    label: term,
                    field: lensField,
                    removalAccessibilityLabel: "Remove lens search term \(term)"
                ) { $0.lensTerms.removeAll { $0 == term } }
            )
        }

        if !criteria.isoRange.isEmpty {
            let value = rangeValue(criteria.isoRange) { NumericFieldKind.int.format($0) }
            result.append(
                ActiveFilterToken(
                    id: "iso",
                    label: "ISO \(value)",
                    field: String(localized: "ISO", comment: "Mac filter bar chip key: ISO range"),
                    value: value,
                    removalAccessibilityLabel: "Remove ISO filter"
                ) { $0.isoRange = NumericRangeFilter() }
            )
        }
        if !criteria.shutterRange.isEmpty {
            let value = rangeValue(criteria.shutterRange) { MetadataFormatter.shutterSpeed($0) ?? String($0) }
            result.append(
                ActiveFilterToken(
                    id: "shutter",
                    label: "shutter \(value)",
                    field: String(localized: "Shutter", comment: "Mac filter bar chip key: shutter speed range"),
                    value: value,
                    removalAccessibilityLabel: "Remove shutter speed filter"
                ) { $0.shutterRange = NumericRangeFilter() }
            )
        }
        if !criteria.apertureRange.isEmpty {
            result.append(
                ActiveFilterToken(
                    id: "aperture",
                    label: "f \(rangeValue(criteria.apertureRange) { NumericFieldKind.double.format($0) })",
                    field: String(localized: "Aperture", comment: "Mac filter bar chip key: aperture range"),
                    value: rangeValue(criteria.apertureRange) { "f/" + NumericFieldKind.double.format($0) },
                    removalAccessibilityLabel: "Remove aperture filter"
                ) { $0.apertureRange = NumericRangeFilter() }
            )
        }
        if !criteria.focalRange.isEmpty {
            let isEquivalent = criteria.focalLengthMode == .equivalent
            let value = rangeValue(criteria.focalRange) { MetadataFormatter.focalLength($0) ?? String($0) }
            result.append(
                ActiveFilterToken(
                    id: "focal",
                    label: "\(isEquivalent ? "focal eq" : "focal") \(value)",
                    field: isEquivalent
                        ? String(localized: "Focal (FF)", comment: "Mac filter bar chip key: full-frame equivalent focal length range")
                        : String(localized: "Focal", comment: "Mac filter bar chip key: focal length range"),
                    value: value,
                    removalAccessibilityLabel: "Remove focal length filter"
                ) { $0.focalRange = NumericRangeFilter() }
            )
        }
        for kind in criteria.mediaKinds.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(
                ActiveFilterToken(
                    id: "media-\(kind.rawValue)",
                    label: kind.displayName,
                    removalAccessibilityLabel: "Remove media type filter \(kind.displayName)"
                ) { $0.mediaKinds.remove(kind) }
            )
        }
        for subtype in criteria.mediaSubtypes.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(
                ActiveFilterToken(
                    id: "subtype-\(subtype.rawValue)",
                    label: subtype.title,
                    removalAccessibilityLabel: "Remove capture kind filter \(subtype.title)"
                ) { $0.mediaSubtypes.remove(subtype) }
            )
        }
        if let month = criteria.captureMonth {
            let name = month.abbreviatedName()
            result.append(
                ActiveFilterToken(
                    id: "month",
                    label: name,
                    removalAccessibilityLabel: "Remove month filter \(name)"
                ) { $0.captureMonth = nil }
            )
        }
        if criteria.favoritesOnly {
            result.append(
                ActiveFilterToken(
                    id: "favorite",
                    label: "Favorite",
                    removalAccessibilityLabel: "Remove favorite filter"
                ) { $0.favoritesOnly = false }
            )
        }
        if criteria.originalOnDeviceOnly {
            let title = OriginalPresence.filterTitle
            result.append(
                ActiveFilterToken(
                    id: "originalOnDevice",
                    label: title,
                    removalAccessibilityLabel: "Remove filter \(title)"
                ) { $0.originalOnDeviceOnly = false }
            )
        }
        if let rating = criteria.ratingFilter {
            result.append(
                ActiveFilterToken(
                    id: "rating",
                    label: MarkCopy.ratingChip(rating),
                    removalAccessibilityLabel: MarkCopy.ratingChipAccessibility(rating)
                ) { $0.ratingFilter = nil }
            )
        }
        for flag in PhotoFlagFilter.allCases where criteria.flags.contains(flag) {
            result.append(
                ActiveFilterToken(
                    id: "flag-\(flag.rawValue)",
                    label: MarkCopy.flagFilterName(flag),
                    removalAccessibilityLabel: MarkCopy.flagChipAccessibility(flag)
                ) { $0.flags.remove(flag) }
            )
        }
        if let text = criteria.searchText, !text.isEmpty {
            for (index, term) in SearchParser.editableTokens(in: text).enumerated() {
                result.append(
                    ActiveFilterToken(
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

    /// "3200–12800", "≥ 400", "85mm" — the range without its field.
    static func rangeValue(_ range: NumericRangeFilter, format: (Double) -> String) -> String {
        switch (range.lowerBound, range.upperBound) {
        case let (lower?, upper?) where lower == upper:
            format(lower)
        case let (lower?, upper?):
            "\(format(lower))–\(format(upper))"
        case let (lower?, nil):
            "≥ \(format(lower))"
        case let (nil, upper?):
            "≤ \(format(upper))"
        case (nil, nil):
            ""
        }
    }
}
