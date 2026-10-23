import SwiftUI

extension View {
    /// Reports this view's width into `width` via a single background
    /// GeometryReader. Grids use this to size tiles from one measurement
    /// instead of hosting a GeometryReader in every cell (the scroll/pinch
    /// hitch at grid scale).
    func measureWidth(into width: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { width.wrappedValue = geo.size.width }
                    .onChange(of: geo.size.width) { _, newValue in
                        width.wrappedValue = newValue
                    }
            }
        )
    }

    /// Reports this view's height into `height` via a background GeometryReader.
    /// The selection bar uses this so the grid can inset by the bar's measured
    /// height. (Avoids `onGeometryChange`, which is iOS 18+.)
    func measureHeight(into height: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { height.wrappedValue = geo.size.height }
                    .onChange(of: geo.size.height) { _, newValue in
                        height.wrappedValue = newValue
                    }
            }
        )
    }
}

/// Where a sheet or tool stops being one column (`DESIGN.md` §10.1c).
///
/// Measured on the view itself, not taken from the size class: the inner
/// display of an iPhone Duo is regular width at 951pt, and so is a 704pt iPad
/// form sheet whose rows would be cut in two.
enum WideLayout {
    static let minimumWidth: CGFloat = 860
}

/// A form that turns into two columns of sections once it is wide enough
/// (`DESIGN.md` §10.1c: a wider screen gets more content, not longer rows).
///
/// Narrower than `WideLayout.minimumWidth` it is a single `Form`, the leading
/// sections above the trailing ones — the phone, and an iPad form sheet.
/// Wider, each half is its own `Form` with its own scroll, 20pt from the
/// edges and 20pt apart.
struct AdaptiveFormColumns<Leading: View, Trailing: View>: View {
    /// The leading column's width, margins excluded; nil splits in halves.
    var leadingWidth: CGFloat?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    @State private var width: CGFloat = 0

    var body: some View {
        Group {
            if width >= WideLayout.minimumWidth {
                HStack(alignment: .top, spacing: 0) {
                    Form { leading() }
                        .contentMargins(.leading, AppTheme.Spacing.xl, for: .scrollContent)
                        .contentMargins(.trailing, AppTheme.Spacing.xl / 2, for: .scrollContent)
                        .frame(width: leadingWidth.map { $0 + AppTheme.Spacing.xl * 1.5 })
                        .frame(maxWidth: leadingWidth == nil ? .infinity : nil)
                    Form { trailing() }
                        .contentMargins(.leading, AppTheme.Spacing.xl / 2, for: .scrollContent)
                        .contentMargins(.trailing, AppTheme.Spacing.xl, for: .scrollContent)
                        .frame(maxWidth: .infinity)
                }
                .background(Color(.systemGroupedBackground))
            } else {
                Form {
                    leading()
                    trailing()
                }
            }
        }
        .measureWidth(into: $width)
    }
}
