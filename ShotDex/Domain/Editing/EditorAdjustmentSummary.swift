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

        if previous.overlays != current.overlays {
            return describeOverlayChange(from: previous.overlays, to: current.overlays)
        }
        if previous.drawing != current.drawing {
            return describeDrawingChange(from: previous.drawing, to: current.drawing)
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

    /// Named by what the layer says wherever possible, because a history full of
    /// "Text" steps is unreadable on a photo with three captions on it. Tokens are
    /// left unexpanded here: this file is pure, and the template is what the user
    /// typed.
    private static func describeOverlayChange(
        from previous: [PhotoOverlay],
        to current: [PhotoOverlay]
    ) -> String {
        if current.count > previous.count {
            let previousIDs = Set(previous.map(\.id))
            let added = current.filter { !previousIDs.contains($0.id) }
            if added.count > 1 { return "Applied Preset" }
            switch added.first?.kind {
            case .text: return "Added Text"
            case .image: return "Added Image"
            case nil: return "Text"
            }
        }
        if current.count < previous.count {
            let currentIDs = Set(current.map(\.id))
            let removed = previous.first { !currentIDs.contains($0.id) }
            return removed?.kind == .image ? "Deleted Image" : "Deleted Text"
        }
        for layer in current {
            guard let old = previous.first(where: { $0.id == layer.id }) else {
                // Same count but a different id: the set was replaced wholesale.
                return "Text"
            }
            guard old != layer else { continue }
            return describeOverlayEdit(from: old, to: layer)
        }
        // Same layers, different order.
        return "Reordered Layers"
    }

    private static func describeOverlayEdit(
        from previous: PhotoOverlay,
        to current: PhotoOverlay
    ) -> String {
        let name = label(for: current)
        if previous.text != current.text { return "\(name) · Content" }
        if previous.isVisible != current.isVisible {
            return "\(name) · \(current.isVisible ? "Show" : "Hide")"
        }
        if previous.fontPostScriptName != current.fontPostScriptName
            || previous.isBold != current.isBold
            || previous.isItalic != current.isItalic {
            return "\(name) · Font"
        }
        if previous.fill != current.fill { return "\(name) · Color" }
        if previous.outlineWidth != current.outlineWidth
            || previous.outlineColor != current.outlineColor {
            return "\(name) · Outline"
        }
        if previous.shadowOpacity != current.shadowOpacity
            || previous.shadowRadius != current.shadowRadius
            || previous.shadowOffsetY != current.shadowOffsetY {
            return "\(name) · Shadow"
        }
        if abs(previous.size - current.size) > 0.0001 { return "\(name) · Size" }
        if abs(previous.opacity - current.opacity) > 0.0001 {
            return "\(name) · Opacity " + String(format: "%.0f%%", current.opacity * 100)
        }
        if abs(previous.rotationDegrees - current.rotationDegrees) > 0.0001 {
            return String(format: "\(name) · Rotate %+.0f°", current.rotationDegrees)
        }
        if previous.center != current.center { return "\(name) · Move" }
        if previous.alignment != current.alignment { return "\(name) · Alignment" }
        if previous.imageID != current.imageID { return "\(name) · Image" }
        return name
    }

    /// Names a drawing change by what happened to the whole layer, since a freehand
    /// scribble has nothing to read back the way a caption does.
    private static func describeDrawingChange(
        from previous: PhotoDrawing?,
        to current: PhotoDrawing?
    ) -> String {
        let had = !(previous?.isEmpty ?? true)
        let has = !(current?.isEmpty ?? true)
        if !had, has { return "Added Drawing" }
        if had, !has { return "Cleared Drawing" }
        return "Edited Drawing"
    }

    private static func label(for overlay: PhotoOverlay) -> String {
        guard overlay.kind == .text else { return "Image" }
        let line = overlay.text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return "Text" }
        return String(line.prefix(18))
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
