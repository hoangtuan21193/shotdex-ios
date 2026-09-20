import SwiftUI
import ShotDexKit

/// The point tone curve, as a plot you drag.
///
/// The photo editor has one, but it is welded to `PhotoEditorController` and
/// draws over the photo stage; this is the same maths (`ToneCurveMath.lut`,
/// the same `CurvePoint` list) in a square that fits an inspector column.
///
/// Rules, and they are the ones a curve has to obey to stay a curve: the two
/// ends stay put, points never pass each other, and a point dragged out of
/// the plot is removed rather than clamped to the wall — dragging a point
/// away is how every curve editor deletes one.
struct VideoCurvePlot: View {
    @Bindable var model: VideoStudioModel
    let channel: ToneCurveChannel

    /// Index of the point under the finger, if any.
    @State private var grabbed: Int?

    private var points: [CurvePoint] { model.recipe.curve[channel] }

    private var stroke: Color {
        switch channel {
        case .rgb: .white
        case .red: EditorTheme.histogramRed
        case .green: EditorTheme.histogramGreen
        case .blue: EditorTheme.histogramBlue
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let plot = CGRect(x: 0, y: 0, width: side, height: side)
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(EditorTheme.control)
                grid(in: plot)
                diagonal(in: plot)
                curvePath(in: plot)
                    .stroke(stroke, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                ForEach(points.indices, id: \.self) { index in
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 0.5))
                        .frame(width: 9, height: 9)
                        .position(position(points[index], in: plot))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(drag(in: plot))
            .accessibilityElement()
            .accessibilityLabel(Text("Tone curve", comment: "Video Studio colour: the draggable curve plot"))
            .accessibilityValue(Text("\(points.count) points", comment: "Video Studio colour: how many points the curve has"))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: Drawing

    private func grid(in plot: CGRect) -> some View {
        Path { path in
            for step in 1..<4 {
                let t = CGFloat(step) / 4
                path.move(to: CGPoint(x: plot.width * t, y: 0))
                path.addLine(to: CGPoint(x: plot.width * t, y: plot.height))
                path.move(to: CGPoint(x: 0, y: plot.height * t))
                path.addLine(to: CGPoint(x: plot.width, y: plot.height * t))
            }
        }
        .stroke(EditorTheme.hairline, lineWidth: 0.5)
    }

    private func diagonal(in plot: CGRect) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: plot.height))
            path.addLine(to: CGPoint(x: plot.width, y: 0))
        }
        .stroke(EditorTheme.dimText, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
    }

    /// Drawn from the same 256-sample table the renderer uses, so the line on
    /// screen is the line being applied — not a spline that only looks like it.
    private func curvePath(in plot: CGRect) -> Path {
        let lut = ToneCurveMath.lut(points: points, count: 128)
        return Path { path in
            for (index, value) in lut.enumerated() {
                let x = plot.width * CGFloat(index) / CGFloat(lut.count - 1)
                let y = plot.height * (1 - CGFloat(value))
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
    }

    private func position(_ point: CurvePoint, in plot: CGRect) -> CGPoint {
        CGPoint(x: plot.width * point.x, y: plot.height * (1 - point.y))
    }

    // MARK: Gesture

    private func drag(in plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var working = points
                if grabbed == nil {
                    model.pushUndo()
                    grabbed = grabOrInsert(at: value.location, in: plot, into: &working)
                }
                guard let index = grabbed, working.indices.contains(index) else { return }
                let x = min(max(0, value.location.x / plot.width), 1)
                let y = min(max(0, 1 - value.location.y / plot.height), 1)
                // The ends own their x: a curve whose black point slid inward
                // is a curve with no black point.
                let isEnd = index == 0 || index == working.count - 1
                let lower = index == 0 ? 0 : working[index - 1].x + 0.02
                let upper = index == working.count - 1 ? 1 : working[index + 1].x - 0.02
                working[index] = CurvePoint(
                    x: isEnd ? working[index].x : min(max(x, lower), upper),
                    y: y
                )
                model.setCurve(channel, points: working)
            }
            .onEnded { value in
                defer { grabbed = nil }
                guard let index = grabbed, points.indices.contains(index) else { return }
                // Dragged off the plot: that is how a curve editor deletes a
                // point. Never the two ends.
                let outside = !plot.insetBy(dx: -24, dy: -24).contains(value.location)
                guard outside, index != 0, index != points.count - 1 else { return }
                var working = points
                working.remove(at: index)
                model.setCurve(channel, points: working)
            }
    }

    /// The point under the finger, or a new one inserted in curve order.
    private func grabOrInsert(
        at location: CGPoint,
        in plot: CGRect,
        into working: inout [CurvePoint]
    ) -> Int? {
        if let nearest = working.indices.min(by: {
            position(working[$0], in: plot).distanceSquared(to: location)
                < position(working[$1], in: plot).distanceSquared(to: location)
        }), position(working[nearest], in: plot).distanceSquared(to: location) <= 22 * 22 {
            return nearest
        }
        let x = min(max(0.02, location.x / plot.width), 0.98)
        let y = min(max(0, 1 - location.y / plot.height), 1)
        let insertAt = working.firstIndex { $0.x > x } ?? working.count
        working.insert(CurvePoint(x: x, y: y), at: insertAt)
        model.setCurve(channel, points: working)
        return insertAt
    }
}

private extension CGPoint {
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return dx * dx + dy * dy
    }
}
