import SwiftUI

/// Full-screen point tone-curve editor. A square plot with the identity diagonal,
/// a thirds grid, the live curve and its draggable control points. Drag a point to
/// move it (endpoints slide along their edge, interior points stay between their
/// neighbours); drag on empty graph to drop a new point; double-tap a point to
/// remove it. A channel picker switches between the RGB master and R / G / B.
struct EditorCurveEditor: View {
    @Bindable var controller: PhotoEditorController
    let onClose: () -> Void

    @State private var channel: ToneCurveChannel = .rgb
    @State private var grabbed: Int?

    private var points: [CurvePoint] { controller.recipe.curve[channel] }

    private var channelColor: Color {
        switch channel {
        case .rgb: .white
        case .red: EditorTheme.histogramRed
        case .green: EditorTheme.histogramGreen
        case .blue: EditorTheme.histogramBlue
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            topBar
            channelPicker
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                plot(side: side)
                    .frame(width: side, height: side)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text("Drag to shape · drag on empty graph to add · double-tap a point to remove")
                .font(.system(size: 11))
                .foregroundStyle(EditorTheme.dimText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EditorTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var topBar: some View {
        HStack {
            Button("Reset") { controller.resetCurve(channel) }
                .font(.system(size: 15))
                .foregroundStyle(
                    points == ToneCurveAdjustments.linear
                        ? EditorTheme.dimText
                        : EditorTheme.accent
                )
                .disabled(points == ToneCurveAdjustments.linear)

            Spacer()
            Text("Curve")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()

            Button("Done", action: onClose)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(EditorTheme.accent)
        }
        .frame(height: 44)
        .padding(.top, 8)
    }

    private var channelPicker: some View {
        HStack(spacing: 8) {
            ForEach(ToneCurveChannel.allCases) { option in
                Button(option.displayName) { channel = option }
                    .buttonStyle(EditorChipButtonStyle(isSelected: channel == option))
            }
        }
    }

    private func plot(side: CGFloat) -> some View {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        return ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(EditorTheme.hairline, lineWidth: 1)
            gridPath(rect).stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            Path {
                $0.move(to: CGPoint(x: 0, y: side))
                $0.addLine(to: CGPoint(x: side, y: 0))
            }
            .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            curvePath(rect).stroke(channelColor, lineWidth: 2)
            ForEach(points.indices, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .overlay { Circle().strokeBorder(channelColor, lineWidth: 2) }
                    .shadow(color: .black.opacity(0.5), radius: 3)
                    .position(viewPoint(points[index], in: rect))
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(deleteGesture(rect))
        .gesture(dragGesture(rect))
    }

    // MARK: Paths

    private func gridPath(_ rect: CGRect) -> Path {
        Path { path in
            for fraction in [1.0 / 3, 2.0 / 3] {
                let x = rect.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: rect.height))
                let y = rect.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: rect.width, y: y))
            }
        }
    }

    private func curvePath(_ rect: CGRect) -> Path {
        let lut = ToneCurveMath.lut(points: points, count: 128)
        return Path { path in
            for (index, value) in lut.enumerated() {
                let x = rect.width * CGFloat(index) / CGFloat(lut.count - 1)
                let y = rect.height * (1 - CGFloat(value))
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
    }

    // MARK: Gestures

    private func dragGesture(_ rect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if grabbed == nil {
                    controller.beginContinuousChange()
                    if let index = nearestPointIndex(to: value.startLocation, in: rect) {
                        grabbed = index
                    } else {
                        var updated = points
                        let new = clamped(
                            index: nil,
                            to: curvePoint(value.location, in: rect),
                            in: updated
                        )
                        let insertion = updated.firstIndex { $0.x > new.x } ?? updated.count
                        updated.insert(new, at: insertion)
                        controller.setCurve(updated, for: channel)
                        grabbed = insertion
                    }
                }
                guard let index = grabbed, index < points.count else { return }
                var updated = points
                updated[index] = clamped(
                    index: index,
                    to: curvePoint(value.location, in: rect),
                    in: updated
                )
                controller.setCurve(updated, for: channel)
            }
            .onEnded { _ in
                controller.endContinuousChange()
                grabbed = nil
            }
    }

    private func deleteGesture(_ rect: CGRect) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                guard let index = nearestPointIndex(to: value.location, in: rect),
                      index != 0, index != points.count - 1
                else { return }
                controller.beginContinuousChange()
                var updated = points
                updated.remove(at: index)
                controller.setCurve(updated, for: channel)
                controller.endContinuousChange()
            }
    }

    // MARK: Geometry

    private func viewPoint(_ point: CurvePoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + CGFloat(point.x) * rect.width,
            y: rect.maxY - CGFloat(point.y) * rect.height
        )
    }

    private func curvePoint(_ location: CGPoint, in rect: CGRect) -> CurvePoint {
        guard rect.width > 0, rect.height > 0 else { return CurvePoint(x: 0, y: 0) }
        return CurvePoint(
            x: min(1, max(0, Double((location.x - rect.minX) / rect.width))),
            y: min(1, max(0, Double((rect.maxY - location.y) / rect.height)))
        )
    }

    private func nearestPointIndex(to location: CGPoint, in rect: CGRect) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for index in points.indices {
            let distance = hypot(
                viewPoint(points[index], in: rect).x - location.x,
                viewPoint(points[index], in: rect).y - location.y
            )
            if distance < (best?.distance ?? .greatestFiniteMagnitude) {
                best = (index, distance)
            }
        }
        guard let best, best.distance <= 26 else { return nil }
        return best.index
    }

    /// Constrain a dragged/added point: endpoints keep their x on the edge, interior
    /// points stay strictly between their neighbours, everything clamps to 0…1 in y.
    private func clamped(index: Int?, to point: CurvePoint, in current: [CurvePoint]) -> CurvePoint {
        let y = min(1, max(0, point.y))
        guard let index else {
            // A new interior point: keep it off the very edges.
            return CurvePoint(x: min(0.99, max(0.01, point.x)), y: y)
        }
        if index == 0 { return CurvePoint(x: 0, y: y) }
        if index == current.count - 1 { return CurvePoint(x: 1, y: y) }
        let lower = current[index - 1].x + 0.001
        let upper = current[index + 1].x - 0.001
        return CurvePoint(x: min(upper, max(lower, point.x)), y: y)
    }
}
