import CoreImage
import Foundation

/// The map that pulls a panorama's curved edge out to a rectangle
/// (FS-14.02 §5).
///
/// A stitched panorama's boundary is a wave, not an edge: every frame is a
/// rectangle seen from a different angle, and the union of them curves. Auto
/// Crop answers that by throwing the wave away, which on a wide sweep costs a
/// fifth of the picture. Boundary Warp answers it by stretching instead — the
/// picture is pushed out to the rectangle and nothing is lost.
///
/// The stretch is a mesh, not a per-column pull. Pulling each column of
/// pixels up to the top edge on its own is one line of code and bends every
/// car and every building at the edge, which is what the spike measured.
/// A mesh spreads the stretch across the whole picture, so what each part of
/// it takes is small enough that a straight line stays straight.
public struct PanoramaWarpMesh: Sendable, Equatable {
    /// Vertices across and down, counting both edges: a 3×2 mesh has six.
    public let columns: Int
    public let rows: Int
    /// For each vertex of the **output** rectangle, in reading order, where it
    /// reads from in the blended panorama. Backward, because that is the
    /// direction a renderer asks in.
    public var source: [SIMD2<Float>]

    public init(columns: Int, rows: Int, source: [SIMD2<Float>]) {
        self.columns = columns
        self.rows = rows
        self.source = source
    }

    public func sourcePoint(column: Int, row: Int) -> SIMD2<Float> {
        source[row * columns + column]
    }
}

public enum PanoramaBoundaryWarp {

    /// Mesh resolution. Fine enough to follow a boundary that waves a few
    /// times across a sweep, coarse enough that the relaxation below is
    /// instant at any panorama size — the mesh is solved once, not per pixel.
    public static let columns = 41
    public static let rows = 25

    /// How far inside the picture an edge vertex is placed, past the first
    /// covered pixel — but never further than the picture is from the
    /// rectangle, so a panorama that already reaches the edge is not quietly
    /// zoomed.
    ///
    /// The map between two edge vertices is a straight line, and a boundary
    /// that bulges outward between them dips below that line — so the output
    /// reads from just outside the picture and the rectangle has a bright rim
    /// of nothing. A couple of pixels of margin costs nothing visible and
    /// removes the whole class of it.
    public static let edgeInset: Float = 3

    /// How many passes of smoothing the edge's own displacement gets.
    ///
    /// The edge is followed as an **envelope**, not traced: a boundary that
    /// waves sharply would make the map wave with it, and a map that waves is
    /// a map that bends the wall in the photograph. Smoothing the
    /// displacement along the edge takes the sharpness out; taking the
    /// envelope afterwards — never letting the smoothed line fall outside the
    /// picture — keeps the rectangle filled. What the envelope leaves over is
    /// what Auto Crop takes, which is what FS-14.02 §5 says should happen.
    static let edgeSmoothingPasses = 6

    /// How many rounds of relaxation the interior gets.
    ///
    /// Gauss-Seidel on a grid this size is converged long before this; the
    /// number is chosen so that the far corners of the largest mesh have heard
    /// from each other, which takes about as many rounds as the mesh is wide.
    static let relaxationRounds = 400

    /// Builds the map for a panorama whose covered pixels are `coverage`.
    ///
    /// `strength` is the slider, 0…1: 0 gives the identity map and 1 pulls the
    /// boundary all the way onto the rectangle. In between is a straight blend
    /// of the two, which is what makes the slider feel like an amount rather
    /// than a switch.
    public static func mesh(
        coverage: [Float],
        width: Int,
        height: Int,
        strength: Double = 1,
        columns: Int = columns,
        rows: Int = rows
    ) -> PanoramaWarpMesh? {
        guard width > 1, height > 1, columns > 2, rows > 2,
              coverage.count >= width * height
        else { return nil }
        let clamped = Float(max(0, min(1, strength)))

        var source = identity(width: width, height: height, columns: columns, rows: rows)
        guard clamped > 0 else {
            return PanoramaWarpMesh(columns: columns, rows: rows, source: source)
        }

        // 1. The edge vertices go looking for the picture. An output point on
        // the top edge reads from the first covered pixel below it, and so
        // round: that is what puts the boundary on the rectangle.
        var fixed = [Bool](repeating: false, count: columns * rows)

        // Each vertex answers for the whole cell around it, so it takes the
        // deepest the boundary gets anywhere in that cell. That is what makes
        // the straight line between two vertices stay inside the picture —
        // the alternative is sampling one line per vertex and finding out
        // afterwards, cell by cell, where the boundary bulged between them.
        // Rounded up, plus one: the window has to cover the whole gap to the
        // next vertex, and integer division rounds it down — which leaves a
        // pixel of boundary nobody looked at, and one pixel is enough for the
        // line between two vertices to clip the picture.
        let cellX = Int((Float(width - 1) / Float(columns - 1)).rounded(.up)) + 1
        let cellY = Int((Float(height - 1) / Float(rows - 1)).rounded(.up)) + 1
        let top = envelope(
            (0..<columns).map { column in
                deepest(
                    around: pixel(column, of: columns, over: width), reach: cellX,
                    limit: width, coverage: coverage, width: width, height: height,
                    from: .top, inward: true
                )
            },
            inward: true
        )
        let bottom = envelope(
            (0..<columns).map { column in
                deepest(
                    around: pixel(column, of: columns, over: width), reach: cellX,
                    limit: width, coverage: coverage, width: width, height: height,
                    from: .bottom, inward: false
                )
            },
            inward: false
        )
        for column in 1..<(columns - 1) {
            let x = Float(column) / Float(columns - 1) * Float(width - 1)
            if let y = top[column] {
                source[column] = SIMD2(x, y + min(edgeInset, y))
                fixed[column] = true
            }
            if let y = bottom[column] {
                let room = Float(height - 1) - y
                source[(rows - 1) * columns + column] = SIMD2(x, y - min(edgeInset, room))
                fixed[(rows - 1) * columns + column] = true
            }
        }

        let left = envelope(
            (0..<rows).map { row in
                deepest(
                    around: pixel(row, of: rows, over: height), reach: cellY,
                    limit: height, coverage: coverage, width: width, height: height,
                    from: .left, inward: true
                )
            },
            inward: true
        )
        let right = envelope(
            (0..<rows).map { row in
                deepest(
                    around: pixel(row, of: rows, over: height), reach: cellY,
                    limit: height, coverage: coverage, width: width, height: height,
                    from: .right, inward: false
                )
            },
            inward: false
        )
        for row in 1..<(rows - 1) {
            let y = Float(row) / Float(rows - 1) * Float(height - 1)
            if let x = left[row] {
                source[row * columns] = SIMD2(x + min(edgeInset, x), y)
                fixed[row * columns] = true
            }
            if let x = right[row] {
                let room = Float(width - 1) - x
                source[row * columns + columns - 1] = SIMD2(x - min(edgeInset, room), y)
                fixed[row * columns + columns - 1] = true
            }
        }

        // The four corners belong to two edges at once, and letting the
        // second one win puts the corner of the output somewhere along the
        // far edge — a fan of empty canvas across the whole corner. A corner
        // takes one coordinate from each edge it belongs to, so it is as deep
        // as both of its neighbours and the lines to them stay inside.
        for corner in Corner.allCases {
            let column = corner.usesLeft ? 0 : columns - 1
            // The vertical coordinate comes from the edge above or below,
            // which is measured over columns and so is well behaved at a
            // corner. The horizontal one is then read **on that row** rather
            // than from the side edge's own first cell: a row that only
            // clips the picture at one end would otherwise drag the corner
            // halfway across the panorama, which is the fan of empty canvas
            // this is here to prevent.
            guard let y = (corner.usesTop ? top : bottom)[column] else { continue }
            // Rows **on the picture's side of** that edge, never past it: a
            // row above a top corner's boundary meets the picture hundreds of
            // pixels away, and taking the deepest of those would drag the
            // corner there. This is the third time that same blow-up has
            // shown up, each time through a different window.
            let half = max(1, cellY / 2)
            guard let x = deepest(
                around: Int(y) + (corner.usesTop ? half : -half), reach: half, limit: height,
                coverage: coverage, width: width, height: height,
                from: corner.usesLeft ? .left : .right, inward: corner.usesLeft
            ) else { continue }
            let roomX = corner.usesLeft ? x : Float(width - 1) - x
            let roomY = corner.usesTop ? y : Float(height - 1) - y
            source[corner.vertex(columns: columns, rows: rows)] = SIMD2(
                x + (corner.usesLeft ? 1 : -1) * min(edgeInset, roomX),
                y + (corner.usesTop ? 1 : -1) * min(edgeInset, roomY)
            )
            fixed[corner.vertex(columns: columns, rows: rows)] = true
        }

        // 2. The inside follows, as smoothly as it can. Each free vertex sits
        // at the average of its four neighbours, over and over — the discrete
        // form of "as flat as possible given the edges", and the reason a
        // straight line comes out straight: a harmonic map has no bumps of its
        // own to add, so the only bending it does is the bending the edge
        // asked for, spread over the whole width of the picture.
        for _ in 0..<relaxationRounds {
            for row in 1..<(rows - 1) {
                for column in 1..<(columns - 1) {
                    let index = row * columns + column
                    guard !fixed[index] else { continue }
                    source[index] = (
                        source[index - 1] + source[index + 1]
                            + source[index - columns] + source[index + columns]
                    ) / 4
                }
            }
        }

        repair(&source, coverage: coverage, width: width, height: height,
               columns: columns, rows: rows)

        guard clamped < 1 else {
            return PanoramaWarpMesh(columns: columns, rows: rows, source: source)
        }
        let rest = identity(width: width, height: height, columns: columns, rows: rows)
        for index in source.indices {
            source[index] = rest[index] + (source[index] - rest[index]) * clamped
        }
        return PanoramaWarpMesh(columns: columns, rows: rows, source: source)
    }

    /// How deep the boundary gets anywhere within `reach` of one line.
    static func deepest(
        around line: Int,
        reach: Int,
        limit: Int,
        coverage: [Float],
        width: Int,
        height: Int,
        from edge: Edge,
        inward: Bool
    ) -> Float? {
        var best: Float?
        for offset in -reach...reach {
            let at = line + offset
            guard at >= 0, at < limit else { continue }
            let found: Int? = switch edge {
            case .top, .bottom:
                firstCovered(coverage: coverage, width: width, height: height, x: at, from: edge)
            case .left, .right:
                firstCovered(coverage: coverage, width: width, height: height, y: at, from: edge)
            }
            guard let found else { continue }
            let value = Float(found)
            best = best.map { inward ? max($0, value) : min($0, value) } ?? value
        }
        return best
    }

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        func vertex(columns: Int, rows: Int) -> Int {
            switch self {
            case .topLeft: 0
            case .topRight: columns - 1
            case .bottomLeft: (rows - 1) * columns
            case .bottomRight: (rows - 1) * columns + columns - 1
            }
        }

        var usesTop: Bool { self == .topLeft || self == .topRight }
        var usesLeft: Bool { self == .topLeft || self == .bottomLeft }

        func step(width: Int, height: Int) -> (x: Int, y: Int, dx: Int, dy: Int) {
            switch self {
            case .topLeft: (0, 0, 1, 1)
            case .topRight: (width - 1, 0, -1, 1)
            case .bottomLeft: (0, height - 1, 1, -1)
            case .bottomRight: (width - 1, height - 1, -1, -1)
            }
        }
    }

    /// The first covered pixel walking in from a corner along its diagonal,
    /// nudged one step further in for the same reason the edges are.
    static func firstCoveredDiagonally(
        coverage: [Float],
        width: Int,
        height: Int,
        from corner: Corner
    ) -> SIMD2<Float>? {
        let start = corner.step(width: width, height: height)
        var x = start.x, y = start.y
        while x >= 0, x < width, y >= 0, y < height {
            if coverage[y * width + x] > 0.001 {
                // The same "never further in than the picture is out" rule the
                // edges follow, so a full rectangle is not quietly zoomed.
                let roomX = start.dx > 0 ? Float(x) : Float(width - 1 - x)
                let roomY = start.dy > 0 ? Float(y) : Float(height - 1 - y)
                return SIMD2(
                    Float(x) + Float(start.dx) * min(edgeInset, roomX),
                    Float(y) + Float(start.dy) * min(edgeInset, roomY)
                )
            }
            x += start.dx
            y += start.dy
        }
        return nil
    }

    /// Which pixel a mesh line sits on.
    static func pixel(_ index: Int, of count: Int, over extent: Int) -> Int {
        Int((Float(index) / Float(count - 1) * Float(extent - 1)).rounded())
    }

    /// A smoothed version of one edge that never falls outside the picture.
    ///
    /// Smoothing alone would let the line cross the boundary where the
    /// boundary bulges; taking the more-inward of the two afterwards keeps it
    /// inside everywhere while still losing most of the sharpness. `inward`
    /// says which direction that is — larger values for the top and left
    /// edges, smaller for the bottom and right.
    static func envelope(_ raw: [Float?], inward: Bool) -> [Float?] {
        guard raw.contains(where: { $0 != nil }) else { return raw }
        // A gap is filled from its neighbours so the smoothing has something
        // to work with; it goes back to nil at the end.
        var filled = raw
        var last: Float?
        for index in filled.indices {
            if filled[index] == nil { filled[index] = last } else { last = filled[index] }
        }
        last = nil
        for index in filled.indices.reversed() {
            if filled[index] == nil { filled[index] = last } else { last = filled[index] }
        }
        var values = filled.map { $0 ?? 0 }
        for _ in 0..<edgeSmoothingPasses {
            var next = values
            for index in 1..<(values.count - 1) {
                next[index] = (values[index - 1] + 2 * values[index] + values[index + 1]) / 4
            }
            values = next
        }
        return raw.indices.map { index -> Float? in
            guard let rawValue = raw[index] else { return nil }
            return inward ? max(values[index], rawValue) : min(values[index], rawValue)
        }
    }

    /// Nudges any vertex whose neighbourhood reads from outside the picture
    /// towards the middle, until it does not.
    ///
    /// Three goes at reasoning the edge into always being inside all failed in
    /// the same corner, each through a different window, so this checks the
    /// answer instead: for each vertex, sample the midpoints of the lines to
    /// its neighbours — the places the renderer will interpolate — and if any
    /// of them lands on empty canvas, step the vertex inward and look again.
    /// It is a handful of samples per vertex on a mesh of a thousand, and it
    /// turns "should be inside" into "is inside".
    static func repair(
        _ source: inout [SIMD2<Float>],
        coverage: [Float],
        width: Int,
        height: Int,
        columns: Int,
        rows: Int
    ) {
        let centre = SIMD2(Float(width - 1) / 2, Float(height - 1) / 2)
        func covered(_ point: SIMD2<Float>) -> Bool {
            let x = Int(point.x.rounded()), y = Int(point.y.rounded())
            guard x >= 0, x < width, y >= 0, y < height else { return false }
            return coverage[y * width + x] > 0.001
        }
        for _ in 0..<24 {
            var moved = false
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = row * columns + column
                    var neighbours: [Int] = []
                    if column > 0 { neighbours.append(index - 1) }
                    if column < columns - 1 { neighbours.append(index + 1) }
                    if row > 0 { neighbours.append(index - columns) }
                    if row < rows - 1 { neighbours.append(index + columns) }
                    // Along each line, not just its middle: the renderer
                    // interpolates every pixel of it, and a boundary that
                    // bulges can clip a quarter of the way along while the
                    // midpoint is comfortably inside.
                    let bad = !covered(source[index]) || neighbours.contains { neighbour in
                        (1...7).map { Float($0) / 8 }.contains {
                            !covered(source[index] + (source[neighbour] - source[index]) * Float($0))
                        }
                    }
                    guard bad else { continue }
                    let towards = centre - source[index]
                    let length = (towards.x * towards.x + towards.y * towards.y).squareRoot()
                    guard length > 1 else { continue }
                    source[index] += towards / length * 2
                    moved = true
                }
            }
            if !moved { break }
        }

        // And the insides of the cells, which no line passes through: the
        // renderer interpolates both ways at once, so a point in the middle of
        // a cell is its own question.
        let inside: [Float] = (0...8).map { Float($0) / 8 }
        for _ in 0..<24 {
            var moved = false
            for row in 0..<(rows - 1) {
                for column in 0..<(columns - 1) {
                    let corners = [
                        row * columns + column, row * columns + column + 1,
                        (row + 1) * columns + column, (row + 1) * columns + column + 1,
                    ]
                    let bad = inside.contains { u in
                        inside.contains { v in
                            let top = source[corners[0]] + (source[corners[1]] - source[corners[0]]) * u
                            let bottom = source[corners[2]] + (source[corners[3]] - source[corners[2]]) * u
                            return !covered(top + (bottom - top) * v)
                        }
                    }
                    guard bad else { continue }
                    for corner in corners {
                        let towards = centre - source[corner]
                        let length = (towards.x * towards.x + towards.y * towards.y).squareRoot()
                        guard length > 1 else { continue }
                        source[corner] += towards / length * 2
                        moved = true
                    }
                }
            }
            if !moved { break }
        }
    }

    /// The map that changes nothing: every output vertex reads from its own
    /// place.
    public static func identity(
        width: Int,
        height: Int,
        columns: Int = columns,
        rows: Int = rows
    ) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        points.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                points.append(
                    SIMD2(
                        Float(column) / Float(columns - 1) * Float(width - 1),
                        Float(row) / Float(rows - 1) * Float(height - 1)
                    )
                )
            }
        }
        return points
    }

    enum Edge { case top, bottom, left, right }

    /// Where the picture starts, walking in from one edge. Nil for a line that
    /// crosses no picture at all, which leaves that vertex where it was rather
    /// than dragging it to an arbitrary place.
    static func firstCovered(
        coverage: [Float],
        width: Int,
        height: Int,
        x: Int = 0,
        y: Int = 0,
        from edge: Edge
    ) -> Int? {
        switch edge {
        case .top:
            guard x >= 0, x < width else { return nil }
            for row in 0..<height where coverage[row * width + x] > 0.001 { return row }
        case .bottom:
            guard x >= 0, x < width else { return nil }
            for row in stride(from: height - 1, through: 0, by: -1)
            where coverage[row * width + x] > 0.001 { return row }
        case .left:
            guard y >= 0, y < height else { return nil }
            for column in 0..<width where coverage[y * width + column] > 0.001 { return column }
        case .right:
            guard y >= 0, y < height else { return nil }
            for column in stride(from: width - 1, through: 0, by: -1)
            where coverage[y * width + column] > 0.001 { return column }
        }
        return nil
    }

    /// Where an output point reads from, by bilinear interpolation of the mesh
    /// — the same arithmetic the renderer does per pixel, available here so a
    /// test can ask about a point rather than a vertex.
    public static func sourcePoint(
        of point: SIMD2<Float>,
        mesh: PanoramaWarpMesh,
        width: Int,
        height: Int
    ) -> SIMD2<Float> {
        let cellWidth = Float(width - 1) / Float(mesh.columns - 1)
        let cellHeight = Float(height - 1) / Float(mesh.rows - 1)
        let fx = min(max(point.x / cellWidth, 0), Float(mesh.columns - 1))
        let fy = min(max(point.y / cellHeight, 0), Float(mesh.rows - 1))
        let column = min(Int(fx), mesh.columns - 2)
        let row = min(Int(fy), mesh.rows - 2)
        let tx = fx - Float(column), ty = fy - Float(row)
        let topLeft = mesh.sourcePoint(column: column, row: row)
        let topRight = mesh.sourcePoint(column: column + 1, row: row)
        let bottomLeft = mesh.sourcePoint(column: column, row: row + 1)
        let bottomRight = mesh.sourcePoint(column: column + 1, row: row + 1)
        let top = topLeft + (topRight - topLeft) * tx
        let bottom = bottomLeft + (bottomRight - bottomLeft) * tx
        return top + (bottom - top) * ty
    }

    // MARK: Rendering

    /// The mesh as a picture the warp can read: one pixel per mesh vertex,
    /// red and green holding where to read from.
    ///
    /// Core Image cannot be handed an array, and a kernel that walked one
    /// would be doing the interpolation itself per pixel. A float image costs
    /// a kilobyte at this size and the sampler does the interpolation in
    /// hardware.
    public static func map(_ mesh: PanoramaWarpMesh) -> CIImage? {
        var values = [Float](repeating: 0, count: mesh.columns * mesh.rows * 4)
        for row in 0..<mesh.rows {
            // Core Image counts rows from the bottom.
            let destination = (mesh.rows - 1 - row) * mesh.columns
            for column in 0..<mesh.columns {
                let point = mesh.sourcePoint(column: column, row: row)
                let at = 4 * (destination + column)
                values[at] = point.x
                values[at + 1] = point.y
                values[at + 3] = 1
            }
        }
        return values.withUnsafeBufferPointer { buffer in
            CIImage(
                bitmapData: Data(buffer: buffer),
                bytesPerRow: mesh.columns * 4 * MemoryLayout<Float>.size,
                size: CGSize(width: mesh.columns, height: mesh.rows),
                format: .RGBAf,
                colorSpace: nil
            )
        }
    }

    /// Applies the mesh to a blended panorama.
    public static func apply(
        _ mesh: PanoramaWarpMesh,
        to image: CIImage,
        width: Int,
        height: Int
    ) -> CIImage? {
        guard let kernel = warpKernel, let map = map(mesh) else { return nil }
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        // The map is one pixel per vertex; stretched over the picture, the
        // sampler's own bilinear filtering is the interpolation.
        let stretched = map
            .transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(width) / CGFloat(mesh.columns),
                    y: CGFloat(height) / CGFloat(mesh.rows)
                )
            )
            .clampedToExtent()
        return kernel.apply(
            extent: extent,
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [image.clampedToExtent(), stretched, Float(height)]
        )
    }

    /// Reads the destination's place in the map, then reads the picture there.
    ///
    /// The y flip is the usual one: the map was built with rows counted from
    /// the top and Core Image counts them from the bottom, and the
    /// coordinates stored in it are in the same top-down space.
    static let warpKernel = CIKernel(source: """
        kernel vec4 panoramaBoundaryWarp(sampler picture, sampler map, float height) {
            vec2 d = destCoord();
            vec4 where = sample(map, samplerTransform(map, d));
            vec2 source = vec2(where.r + 0.5, height - 0.5 - where.g);
            return sample(picture, samplerTransform(picture, source));
        }
        """)
}
