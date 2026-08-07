import SwiftUI


struct EditorHistogramSparkline: View {
    let histogram: PhotoHistogram

    var body: some View {
        ZStack {
            EditorHistogramShape(values: histogram.luminance, isFilled: true)
                .fill(Color.white.opacity(0.32))
            EditorHistogramShape(values: histogram.red, isFilled: false)
                .stroke(EditorTheme.histogramRed.opacity(0.9), lineWidth: 1)
                .blendMode(.screen)
            EditorHistogramShape(values: histogram.green, isFilled: false)
                .stroke(EditorTheme.histogramGreen.opacity(0.9), lineWidth: 1)
                .blendMode(.screen)
            EditorHistogramShape(values: histogram.blue, isFilled: false)
                .stroke(EditorTheme.histogramBlue.opacity(0.9), lineWidth: 1)
                .blendMode(.screen)
        }
        .drawingGroup()
    }
}

/// One histogram trace as a `Shape`, so the card and the pill draw it the same
/// way at any size.
struct EditorHistogramShape: Shape {
    let values: [Double]
    let isFilled: Bool

    func path(in rect: CGRect) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            if isFilled { path.move(to: CGPoint(x: 0, y: rect.height)) }
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: rect.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: rect.height * CGFloat(1 - min(1, max(0, value)))
                )
                if index == 0, !isFilled {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            if isFilled {
                path.addLine(to: CGPoint(x: rect.width, y: rect.height))
                path.closeSubpath()
            }
        }
    }
}
