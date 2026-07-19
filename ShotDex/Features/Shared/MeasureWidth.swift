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
}
