import Foundation

/// The separately placeable pieces of a photo widget's face.
///
/// They used to be one block: a VStack that moved as a unit. A clock in one
/// corner and the weather in the other is the arrangement people actually
/// want, so each piece now carries its own position.
enum PhotoWidgetComponent: String, Codable, CaseIterable, Identifiable, Sendable {
    case time
    case date
    case weather
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: "Time"
        case .date: "Date"
        case .weather: "Weather"
        case .calendar: "Calendar"
        }
    }

    /// Which pieces this widget draws at all, in the order they stack when
    /// they share a position.
    static func components(for kind: PhotoWidgetKind, settings: PhotoWidgetSettings) -> [PhotoWidgetComponent] {
        var components: [PhotoWidgetComponent] = []
        if settings.showsTime { components.append(.time) }
        if settings.showsDate { components.append(.date) }
        if kind.needsWeather { components.append(.weather) }
        if kind.needsCalendarEvents { components.append(.calendar) }
        return components
    }
}

/// Where each piece sits, and what to draw while one is being dragged.
///
/// All of it is arithmetic on fractions, which is why it lives here and is
/// unit-tested: "does the clock snap to the middle" should not be a question
/// answered by dragging it in a simulator.
enum PhotoWidgetLayout {
    /// Pieces at the same spot are drawn as one stack, which is what keeps a
    /// widget that has never been rearranged looking exactly as it did.
    /// Rounded first, because two drags can leave two anchors a ten-thousandth
    /// apart and they should still stack.
    static func groups(
        _ components: [PhotoWidgetComponent],
        anchors: [PhotoWidgetComponent: PhotoWidgetSettings.Anchor],
        blockAnchor: PhotoWidgetSettings.Anchor
    ) -> [(anchor: PhotoWidgetSettings.Anchor, components: [PhotoWidgetComponent])] {
        var order: [String] = []
        var byKey: [String: (anchor: PhotoWidgetSettings.Anchor, components: [PhotoWidgetComponent])] = [:]
        for component in components {
            let anchor = anchors[component] ?? blockAnchor
            let key = Self.key(for: anchor)
            if byKey[key] == nil {
                order.append(key)
                byKey[key] = (anchor, [])
            }
            byKey[key]?.components.append(component)
        }
        return order.compactMap { byKey[$0] }
    }

    static func key(for anchor: PhotoWidgetSettings.Anchor) -> String {
        String(format: "%.3f|%.3f", anchor.x, anchor.y)
    }
}

/// Where a dragged piece should land, and which guide lines to show for it.
///
/// Two kinds of pull: the middle of the widget, and lining up with a piece
/// already placed. Both are what a person is trying to do by eye anyway, and
/// both are impossible to hit by eye on a 158pt preview.
enum PhotoWidgetSnapping {
    /// How close, as a fraction of the free space, counts as "meant it".
    static let threshold: Double = 0.06

    struct Result: Equatable {
        var anchor: PhotoWidgetSettings.Anchor
        /// Guides to draw, as fractions across the widget.
        var verticalGuides: [Double]
        var horizontalGuides: [Double]

        var isSnapped: Bool { !verticalGuides.isEmpty || !horizontalGuides.isEmpty }
    }

    /// `others` are the anchors of the pieces not being dragged.
    static func snap(
        _ anchor: PhotoWidgetSettings.Anchor,
        others: [PhotoWidgetSettings.Anchor],
        threshold: Double = threshold
    ) -> Result {
        // The middle first: a centred piece is the most common intent, and it
        // wins ties against lining up with a neighbour.
        var candidatesX: [Double] = [0.5]
        var candidatesY: [Double] = [0.5]
        // The edges, so "hard against the corner" is reachable without
        // fighting the last pixel.
        candidatesX.append(contentsOf: [0, 1])
        candidatesY.append(contentsOf: [0, 1])
        candidatesX.append(contentsOf: others.map(\.x))
        candidatesY.append(contentsOf: others.map(\.y))

        var result = Result(anchor: anchor, verticalGuides: [], horizontalGuides: [])
        if let target = nearest(anchor.x, in: candidatesX, threshold: threshold) {
            result.anchor = PhotoWidgetSettings.Anchor(x: target, y: result.anchor.y)
            // An edge is the widget's own boundary; a line there is noise.
            if target > 0, target < 1 { result.verticalGuides = [target] }
        }
        if let target = nearest(anchor.y, in: candidatesY, threshold: threshold) {
            result.anchor = PhotoWidgetSettings.Anchor(x: result.anchor.x, y: target)
            if target > 0, target < 1 { result.horizontalGuides = [target] }
        }
        return result
    }

    private static func nearest(_ value: Double, in candidates: [Double], threshold: Double) -> Double? {
        var best: Double?
        var bestDistance = threshold
        for candidate in candidates {
            let distance = abs(candidate - value)
            if distance < bestDistance || (distance == bestDistance && candidate == 0.5) {
                best = candidate
                bestDistance = distance
            }
        }
        return best
    }
}
