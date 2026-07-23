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
