import ShotDexKit

/// A mask's subtitle (FS-03.13c §2): every area in order, each after the
/// sign of how it combines — "Sky − Brush". A mask is named "Mask n" whatever
/// it holds, so this line is where its kind is read.
enum MaskAreaSummary {
    static func subtitle(for mask: PhotoMask) -> String {
        // Background is Subject inverted: one area, read as what the user
        // chose.
        if mask.isInverted, mask.components.count == 1, mask.components[0].kind == .subject {
            return EditorNewMaskOption.background.shortTitle
        }
        var text = ""
        for (index, component) in mask.components.enumerated() {
            if index > 0 { text += " \(sign(of: component.operation)) " }
            text += name(of: component)
        }
        return text
    }

    /// The area's short name: the chooser's tile title, or who and which part
    /// for a People area.
    static func name(of component: PhotoMaskComponent) -> String {
        if component.kind == .people {
            let who = component.personIndex.map { "Person \($0)" } ?? "People"
            return component.personPart.map { "\(who) \($0.displayName)" } ?? who
        }
        let option = EditorNewMaskOption.allCases.first { $0 != .background && $0.componentKind == component.kind }
        return option?.shortTitle ?? component.kind.displayName
    }

    static func sign(of operation: MaskBlendOperation) -> String {
        switch operation {
        case .add: "+"
        case .subtract: "−"
        case .intersect: "∩"
        }
    }
}
