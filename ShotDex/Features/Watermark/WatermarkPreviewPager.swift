import ShotDexKit
import SwiftUI

/// The photos of the batch, one page each, with the stamp drawn by the same
/// raster as the files get (FS-05.04 §4). Swiped sideways; a pill counts
/// `i / N` on the phone layouts.
struct WatermarkPreviewPager: View {
    @Bindable var model: WatermarkModel
    let pill: Bool
    /// Before and After and Zoom on the preview's top corners — every
    /// layout but the iPad's, whose toolbar holds them (FS-05.04 §4a).
    var showsCornerTools = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        WatermarkPreviewPageView(model: model, page: page)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { model.currentIndex },
                set: { if let index = $0 { model.currentIndex = index } }
            ))
            // Zoomed, one finger pans the picture instead of turning pages.
            .scrollDisabled(model.pages.count < 2 || model.zoom != .fit)
        }
        // The next page must not show beyond the preview — under the Duo
        // cover's rail it would read as part of the screen.
        .clipped()
        .overlay(alignment: .bottom) {
            if pill, model.pages.count > 1 {
                Text(WatermarkCopy.pagePill(model.currentIndex + 1, of: model.pages.count))
                    .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .editorGlass(Capsule())
                    .padding(.bottom, 10)
                    .accessibilityLabel(WatermarkCopy.pageCounter(model.currentIndex + 1, of: model.pages.count))
            }
        }
        .overlay(alignment: .top) {
            // The top corners: the bottom ones hold the default stamp and
            // the page pill.
            if showsCornerTools {
                HStack {
                    WatermarkBeforeAfterButton(model: model, diameter: 36)
                    Spacer()
                    WatermarkZoomMenu(model: model, height: 36)
                }
                // The disc sits 10 from the corner inside its 44pt target.
                .padding(.top, 6)
                .padding(.leading, 6)
                .padding(.trailing, 10)
            }
        }
    }
}

/// Before and After (FS-05.04 §4a): a switch; on shows the bare picture,
/// the button in the editor's active look — white, black glyph.
struct WatermarkBeforeAfterButton: View {
    @Bindable var model: WatermarkModel
    /// The glass disc on the phone layouts; nil inside the iPad's capsule.
    var diameter: CGFloat?

    var body: some View {
        Button {
            model.showsBefore.toggle()
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: diameter == nil ? 18 : 15, weight: .medium))
                .foregroundStyle(model.showsBefore ? Color.black : Color.white.opacity(0.9))
                .frame(width: diameter ?? 44, height: diameter ?? 40)
                .background {
                    if model.showsBefore {
                        Capsule().fill(.white)
                    } else if let diameter {
                        Color.clear.frame(width: diameter, height: diameter).editorGlass(Circle())
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.isEnabled)
        .opacity(model.isEnabled ? 1 : EditorTheme.rowDisabled)
        .accessibilityLabel(WatermarkCopy.beforeAndAfter())
        .accessibilityAddTraits(model.showsBefore ? .isSelected : [])
    }
}

/// Zoom: Fit · 200% · 400%, the level written on the control.
struct WatermarkZoomMenu: View {
    @Bindable var model: WatermarkModel
    /// The glass capsule's height on the phone layouts; nil inside the
    /// iPad's capsule.
    var height: CGFloat?

    var body: some View {
        Menu {
            Picker(WatermarkCopy.zoom(), selection: Binding(get: { model.zoom }, set: { model.setZoom($0) })) {
                ForEach(WatermarkZoom.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Text(model.zoom.title)
                    .font(.system(size: height == nil ? 17 : 14, weight: height == nil ? .regular : .semibold).monospacedDigit())
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: height == nil ? 12 : 10, weight: .semibold))
                    .foregroundStyle(EditorTheme.secondaryText)
            }
            .foregroundStyle(.white)
            .padding(.leading, 12)
            .padding(.trailing, 10)
            .frame(height: height ?? 40)
            .background {
                if height != nil { Color.clear.editorGlass(Capsule()) }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WatermarkCopy.zoom())
        .accessibilityValue(model.zoom.title)
    }
}

private struct WatermarkPreviewPageView: View {
    @Bindable var model: WatermarkModel
    let page: WatermarkPreviewPage
    @Environment(\.displayScale) private var displayScale
    /// The finger's travel during a pan, before it is kept.
    @State private var dragging: CGSize = .zero

    private var isZoomed: Bool { model.zoom != .fit && page.id == model.currentPage?.id }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if let image = model.image(for: page) {
                    let imageSize = CGSize(width: image.width, height: image.height)
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(isZoomed ? model.zoom.scale : 1)
                        .offset(isZoomed ? offset(imageSize: imageSize, displaySize: size, extra: dragging) : .zero)
                        .gesture(pan(imageSize: imageSize, displaySize: size), including: isZoomed ? .all : .subviews)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .task(id: DetailKey(zoom: model.zoom, index: model.currentIndex, size: size)) {
                guard isZoomed else { return }
                let edge = WatermarkZoom.detailLongEdge(
                    exportSize: page.exportSize, displaySize: size, scale: model.zoom.scale, screenScale: displayScale
                )
                await model.loadDetail(for: page, longEdge: edge)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(page.filename)
        .task { await model.load(page) }
    }

    private struct DetailKey: Equatable {
        let zoom: WatermarkZoom
        let index: Int
        let size: CGSize
    }

    private func offset(imageSize: CGSize, displaySize: CGSize, extra: CGSize) -> CGSize {
        WatermarkZoom.offset(
            focus: model.zoomFocus(for: page, displaySize: displaySize),
            pan: CGSize(width: model.pan.width + extra.width, height: model.pan.height + extra.height),
            imageSize: imageSize, displaySize: displaySize, scale: model.zoom.scale
        )
    }

    /// One finger moves the zoomed picture; what is kept is the pan the
    /// clamp allowed, so dragging past an edge doesn't store slack.
    private func pan(imageSize: CGSize, displaySize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { dragging = $0.translation }
            .onEnded { value in
                let kept = offset(imageSize: imageSize, displaySize: displaySize, extra: value.translation)
                let centred = WatermarkZoom.offset(
                    focus: model.zoomFocus(for: page, displaySize: displaySize), pan: .zero,
                    imageSize: imageSize, displaySize: displaySize, scale: model.zoom.scale, clamps: false
                )
                model.pan = CGSize(width: kept.width - centred.width, height: kept.height - centred.height)
                dragging = .zero
            }
    }
}

/// The landscape iPad's strip of the batch under the preview (board
/// `IP22_Watermark`): tap a photo to preview the stamp on it.
struct WatermarkFilmstrip: View {
    @Bindable var model: WatermarkModel

    var body: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                        Button {
                            model.currentIndex = index
                        } label: {
                            thumbnail(page)
                                .frame(width: 88, height: 60)
                                .clipShape(RoundedRectangle.app(AppTheme.Radius.sm - 2))
                                .overlay {
                                    RoundedRectangle.app(AppTheme.Radius.sm - 2)
                                        .stroke(.white, lineWidth: index == model.currentIndex ? 2 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(WatermarkCopy.photoNumber(index + 1, current: index == model.currentIndex))
                        .task { await model.load(page) }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            Text(WatermarkCopy.pageCounter(model.currentIndex + 1, of: model.pages.count))
                .font(.system(size: 15).monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
                .padding(.trailing, AppTheme.Spacing.lg)
        }
        .frame(maxHeight: .infinity)
        .background(EditorTheme.panelSolid)
        .overlay(alignment: .top) { Rectangle().fill(EditorTheme.panelDivider).frame(height: 1) }
    }

    @ViewBuilder
    private func thumbnail(_ page: WatermarkPreviewPage) -> some View {
        if let image = model.bases[page.id] {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
        } else {
            EditorTheme.control
        }
    }
}
