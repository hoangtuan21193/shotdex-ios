import SwiftUI

/// Every piece of a widget's face, each at its own position.
///
/// Shared by the widget and by the editor's preview, so what is arranged in
/// Settings is what the Home Screen draws. Pieces that share a position are
/// drawn as one stack — which is exactly how a widget that has never been
/// rearranged looked, and still looks.
struct PhotoWidgetArrangedFace<Overlay: View>: View {
    let date: Date
    let settings: PhotoWidgetSettings
    let size: CGSize
    var weather: WeatherSnapshot?
    var calendarSnapshot: CalendarSnapshot?
    var isCompact = false
    /// How bright the picture is behind the text, so the **Smart** colour can
    /// be worked out per block rather than once for the whole widget: a clock
    /// dragged onto a bright sky and a date left on dark rock want opposite
    /// answers, and one colour for both is how the old fixed swatches failed.
    var lumaGrid: PhotoWidgetLumaGrid?
    /// Width ÷ height of that picture — needed to know which part of it the
    /// widget is actually showing.
    var imageAspectRatio: Double = 1
    /// Drawn over each group, given the group's pieces: the editor uses it for
    /// the selection outline and handles; the widget passes nothing.
    @ViewBuilder var overlay: ([PhotoWidgetComponent], CGSize) -> Overlay
    /// Reports where each group ended up, so the editor can hit-test a touch
    /// against the piece under it.
    var onLayout: ([PhotoWidgetComponent], CGRect) -> Void = { _, _ in }

    /// The margin a piece keeps from the widget's own edges.
    static var inset: CGFloat { 4 }

    private var groups: [(anchor: PhotoWidgetSettings.Anchor, components: [PhotoWidgetComponent])] {
        PhotoWidgetLayout.groups(
            PhotoWidgetComponent.components(settings: settings),
            anchors: settings.componentAnchorsByComponent,
            blockAnchor: settings.anchor
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A widget with nothing turned on still draws its "ShotDex" line,
            // and that line has no group of its own.
            if groups.isEmpty {
                PhotoWidgetFace(
                    date: date, settings: settings, width: size.width,
                    weather: weather, calendarSnapshot: calendarSnapshot,
                    isCompact: isCompact, components: [],
                    textColor: smartColor(forRect: CGRect(origin: .zero, size: size))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.anchor.alignment)
            }
            ForEach(groups, id: \.anchor.hashValue) { group in
                PhotoWidgetPlacedGroup(
                    date: date,
                    settings: settings,
                    size: size,
                    weather: weather,
                    calendarSnapshot: calendarSnapshot,
                    isCompact: isCompact,
                    anchor: group.anchor,
                    components: group.components,
                    smartColor: smartColor(forRect:),
                    overlay: overlay,
                    onLayout: onLayout
                )
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// The Smart colour for one block, or nil when the user picked a fixed
    /// swatch (then the hex decides) or when there is nothing to measure.
    private func smartColor(forRect rect: CGRect) -> Color? {
        guard WidgetTextColor.isSmart(hex: settings.textColorHex) else { return nil }
        guard let lumaGrid else { return .white }
        let imageRect = PhotoWidgetImageLayer.normalizedImageRect(
            for: rect,
            in: size,
            aspectRatio: imageAspectRatio,
            scale: settings.photoScale,
            offsetX: settings.photoOffsetX,
            offsetY: settings.photoOffsetY
        )
        // Dimming is drawn over the photo, so it is part of what the text
        // stands on — a picture dimmed to 60% is a dark background whatever
        // the pixels underneath say.
        let luma = lumaGrid.luma(inNormalizedRect: imageRect) * (1 - settings.photoDimming)
        return WidgetTextColor.smartColor(luma: luma)
    }
}

/// One group, measured and then placed at its anchor.
private struct PhotoWidgetPlacedGroup<Overlay: View>: View {
    let date: Date
    let settings: PhotoWidgetSettings
    let size: CGSize
    var weather: WeatherSnapshot?
    var calendarSnapshot: CalendarSnapshot?
    var isCompact: Bool
    let anchor: PhotoWidgetSettings.Anchor
    let components: [PhotoWidgetComponent]
    /// Asked once the block has been measured and placed, because the answer
    /// depends on where it ended up.
    let smartColor: (CGRect) -> Color?
    @ViewBuilder var overlay: ([PhotoWidgetComponent], CGSize) -> Overlay
    var onLayout: ([PhotoWidgetComponent], CGRect) -> Void

    @State private var contentSize: CGSize = .zero

    private var inset: CGFloat { PhotoWidgetArrangedFace<EmptyView>.inset }

    var body: some View {
        PhotoWidgetFace(
            date: date,
            settings: settings,
            width: size.width,
            weather: weather,
            calendarSnapshot: calendarSnapshot,
            isCompact: isCompact,
            components: components,
            textColor: smartColor(placedRect)
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentSize = proxy.size }
                    .onChange(of: proxy.size) { _, new in contentSize = new }
            }
        }
        .overlay { overlay(components, contentSize) }
        .padding(inset)
        .offset(origin)
        .onChange(of: origin) { _, _ in report() }
        .onChange(of: contentSize) { _, _ in report() }
        .onAppear { report() }
    }

    /// Top-left of the group inside the widget, from its anchor and its own
    /// measured size — the same arithmetic the widget and the editor both use,
    /// so a piece cannot sit in two different places.
    private var origin: CGSize {
        let available = CGSize(
            width: max(0, size.width - contentSize.width - inset * 2),
            height: max(0, size.height - contentSize.height - inset * 2)
        )
        return CGSize(width: available.width * anchor.x, height: available.height * anchor.y)
    }

    /// Where this block sits inside the widget, inset included — the same
    /// rectangle `report()` hands the editor.
    private var placedRect: CGRect {
        CGRect(
            x: origin.width,
            y: origin.height,
            width: contentSize.width + inset * 2,
            height: contentSize.height + inset * 2
        )
    }

    private func report() {
        onLayout(components, placedRect)
    }
}

extension PhotoWidgetSettings {
    /// The stored positions, keyed by the component rather than by its raw
    /// string — the string is what goes in the file, this is what code reads.
    var componentAnchorsByComponent: [PhotoWidgetComponent: Anchor] {
        var result: [PhotoWidgetComponent: Anchor] = [:]
        for (key, anchor) in componentAnchors {
            guard let component = PhotoWidgetComponent(rawValue: key) else { continue }
            result[component] = anchor
        }
        return result
    }
}
