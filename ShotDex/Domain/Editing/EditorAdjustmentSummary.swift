import Foundation

/// Human-readable descriptions of what a recipe holds and of what changed
/// between two recipes. The mask list uses the first for its row subtitles and
/// the History sheet uses the second for its step labels, so neither has to be
/// tracked while the user drags.
enum EditorAdjustmentSummary {
    /// `Exposure +0.80 · Shadows +12`, or nil when nothing is set.
    static func text(for adjustments: PhotoAdjustments, limit: Int = 3) -> String? {
        let parts = changedKinds(from: .zero, to: adjustments).map { kind in
            "\(EditorAdjustmentCatalog.shortTitle(of: kind)) "
                + EditorAdjustmentCatalog.displayText(adjustments[kind], of: kind)
        }
        guard !parts.isEmpty else { return nil }
        guard parts.count > limit else { return parts.joined(separator: " · ") }
        let shown = parts.prefix(limit).joined(separator: " · ")
        return "\(shown) +\(parts.count - limit)"
    }

    /// Label for one History step: what the move from `previous` to `current`
    /// did. Mask-scoped changes are prefixed with the mask's name so a step reads
    /// `Subject 1 · Exposure +0.80`.
    static func describeChange(
        from previous: PhotoEditRecipe,
        to current: PhotoEditRecipe
    ) -> String {
        if current.isIdentity, !previous.isIdentity { return "Reset" }

        if current.masks.count != previous.masks.count {
            let previousIDs = Set(previous.masks.map(\.id))
            if let added = current.masks.first(where: { !previousIDs.contains($0.id) }) {
                return "Added \(added.name)"
            }
            let currentIDs = Set(current.masks.map(\.id))
            if let removed = previous.masks.first(where: { !currentIDs.contains($0.id) }) {
                return "Deleted \(removed.name)"
            }
        }

        for mask in current.masks {
            guard let old = previous.masks.first(where: { $0.id == mask.id }) else { continue }
            if let change = firstChange(from: old.adjustments, to: mask.adjustments) {
                return "\(mask.name) · \(change)"
            }
            if old.isInverted != mask.isInverted {
                return "\(mask.name) · \(mask.isInverted ? "Invert" : "Remove Invert")"
            }
            if old.isVisible != mask.isVisible {
                return "\(mask.name) · \(mask.isVisible ? "Show" : "Hide")"
            }
            if old.components.count != mask.components.count {
                return "\(mask.name) · Shapes"
            }
            if old.components != mask.components {
                return "\(mask.name) · Shape"
            }
            if old.name != mask.name {
                return "Renamed \(mask.name)"
            }
        }

        if previous.cleanUpStrokes != current.cleanUpStrokes {
            return describeCleanUpChange(
                from: previous.cleanUpStrokes,
                to: current.cleanUpStrokes
            )
        }
        if let change = firstChange(from: previous.adjustments, to: current.adjustments) {
            return change
        }
        if previous.color != current.color {
            return describeColorChange(from: previous.color, to: current.color)
        }
        if previous.filter != current.filter {
            return "Filter \(current.filter.displayName)"
        }
        if abs(previous.filterIntensity - current.filterIntensity) > 0.0001 {
            return "Filter Intensity "
                + String(format: "%.0f%%", current.filterIntensity * 100)
        }
        if previous.crop != current.crop {
            return describeCrop(from: previous.crop, to: current.crop)
        }
        if previous.source != current.source {
            return "Source \(current.source.displayName)"
        }
        return "Edit"
    }

    private static func describeColorChange(
        from previous: PhotoColorRecipe,
        to current: PhotoColorRecipe
    ) -> String {
        if previous.mixer != current.mixer {
            for band in ColorMixerBand.allCases {
                for property in ColorMixerProperty.allCases
                where abs(previous.mixer[band][property] - current.mixer[band][property])
                    > 0.0001 {
                    let value = Int((current.mixer[band][property] * 100).rounded())
                    return "Mixer · \(band.displayName) \(property.displayName) "
                        + (value > 0 ? "+\(value)" : "\(value)")
                }
            }
            return "Mixer"
        }
        if previous.points.count < current.points.count { return "Added Point Color" }
        if previous.points.count > current.points.count { return "Removed Point Color" }
        if previous.points != current.points { return "Point Color" }
        if previous.grading != current.grading {
            if abs(previous.grading.blending - current.grading.blending) > 0.0001 {
                return "Grading · Blending \(Int((current.grading.blending * 100).rounded()))"
            }
            if abs(previous.grading.balance - current.grading.balance) > 0.0001 {
                let value = Int((current.grading.balance * 100).rounded())
                return "Grading · Balance " + (value > 0 ? "+\(value)" : "\(value)")
            }
            for region in ColorGradingRegion.allCases
            where previous.grading[region] != current.grading[region] {
                return "Grading · \(region.displayName)"
            }
            return "Grading"
        }
        return "Color"
    }

    /// Names the removal, not the mechanism: the History sheet is read as "what
    /// did I do", and "Removed an Object" answers that where "Clean Up · Stroke"
    /// does not.
    private static func describeCleanUpChange(
        from previous: [CleanUpStroke],
        to current: [CleanUpStroke]
    ) -> String {
        if current.count > previous.count {
            let previousIDs = Set(previous.map(\.id))
            let added = current.first { !previousIDs.contains($0.id) }
            switch added?.mode {
            case .remove: return "Removed an Object"
            case .clone: return "Cloned an Area"
            case .heal: return "Healed an Area"
            case nil: return "Clean Up"
            }
        }
        if current.count < previous.count {
            return current.isEmpty && previous.count > 1
                ? "Cleared Clean Up"
                : "Deleted Clean Up"
        }
        for stroke in current {
            guard let old = previous.first(where: { $0.id == stroke.id }) else { continue }
            if old.usesModel != stroke.usesModel {
                return stroke.usesModel ? "Clean Up · AI Fill" : "Clean Up · Auto Fill"
            }
            if old.sourceOffsetX != stroke.sourceOffsetX
                || old.sourceOffsetY != stroke.sourceOffsetY {
                return "Clean Up · Source"
            }
            if abs(old.opacity - stroke.opacity) > 0.0001 {
                return "Clean Up · Opacity "
                    + String(format: "%.0f%%", stroke.opacity * 100)
            }
        }
        return "Clean Up"
    }

    private static func describeCrop(
        from previous: PhotoCropRecipe,
        to current: PhotoCropRecipe
    ) -> String {
        if previous.quarterTurns != current.quarterTurns { return "Rotate" }
        if previous.flippedHorizontally != current.flippedHorizontally { return "Flip" }
        if abs(previous.straightenDegrees - current.straightenDegrees) > 0.0001 {
            return String(format: "Straighten %+.1f°", current.straightenDegrees)
        }
        if previous.aspect != current.aspect { return "Crop \(current.aspect.displayName)" }
        return "Crop"
    }

    private static func firstChange(
        from previous: PhotoAdjustments,
        to current: PhotoAdjustments
    ) -> String? {
        guard let kind = changedKinds(from: previous, to: current).first else { return nil }
        return "\(EditorAdjustmentCatalog.shortTitle(of: kind)) "
            + EditorAdjustmentCatalog.displayText(current[kind], of: kind)
    }

    private static func changedKinds(
        from previous: PhotoAdjustments,
        to current: PhotoAdjustments
    ) -> [PhotoAdjustmentKind] {
        PhotoAdjustmentKind.allCases.filter { kind in
            abs(current[kind] - previous[kind]) > 0.0001
        }
    }
}
