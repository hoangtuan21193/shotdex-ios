import ShotDexKit
import SwiftUI

/// The photos of the batch, one page each, with the stamp drawn by the same
/// raster as the files get (FS-05.04 §4). Swiped sideways; a pill counts
/// `i / N` on the phone layouts.
struct WatermarkPreviewPager: View {
    @Bindable var model: WatermarkModel
    let pill: Bool

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
            .scrollDisabled(model.pages.count < 2)
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
    }
}

private struct WatermarkPreviewPageView: View {
    @Bindable var model: WatermarkModel
    let page: WatermarkPreviewPage

    var body: some View {
        ZStack {
            if let image = model.image(for: page) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement()
        .accessibilityLabel(page.filename)
        .task { await model.load(page) }
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
