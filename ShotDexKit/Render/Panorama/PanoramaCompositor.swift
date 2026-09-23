import Foundation

/// A colour image with a coverage channel: three floats of linear RGB per
/// pixel, plus how much of that pixel any frame actually reached.
///
/// Coverage is carried separately rather than as alpha because the blend needs
/// to ask two different questions of it — "is there anything here" when
/// deciding what to fill, and "how much of this frame is here" when weighing
/// one frame against another.
public struct PanoramaRGBImage: Sendable {
    public let width: Int
    public let height: Int
    /// Interleaved RGB, `3 * width * height`.
    public var pixels: [Float]
    /// One value per pixel, 0…1.
    public var coverage: [Float]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [Float](repeating: 0, count: 3 * width * height)
        coverage = [Float](repeating: 0, count: width * height)
    }

    public init(width: Int, height: Int, pixels: [Float], coverage: [Float]) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.coverage = coverage
    }

    @inlinable
    public func colour(atX x: Int, y: Int) -> (Float, Float, Float) {
        let index = 3 * (y * width + x)
        return (pixels[index], pixels[index + 1], pixels[index + 2])
    }
}

/// How carefully a panorama is put together.
public enum PanoramaBlendQuality: Sendable {
    /// One soft crossfade, no pyramid. For the preview that has to keep up
    /// with a finger on a slider (FS-14.01 §4).
    case draft
    /// Multi-band. For the picture that gets saved, and for the preview once
    /// the finger comes off.
    case sharp
}

/// Warps every frame onto the canvas and blends them into one picture.
public enum PanoramaCompositor {

    /// Bands in the sharp blend.
    ///
    /// Six is what the spike used and found free of visible seams. The point of
    /// more than one is that a seam is only invisible if each scale of detail
    /// crosses it differently: broad brightness has to blend over a wide
    /// distance or the join shows as a soft bar, and fine detail has to blend
    /// over a narrow one or it smears into a double image.
    public static let bandCount = 6

    public static func render(
        canvas: PanoramaCanvas,
        frames: [PanoramaRGBImage],
        cameras: [Int: PanoramaCamera],
        focal: Double,
        gains: [Double]? = nil,
        quality: PanoramaBlendQuality = .sharp
    ) -> PanoramaRGBImage? {
        guard canvas.width > 0, canvas.height > 0, !frames.isEmpty else { return nil }
        let order = cameras.keys.sorted().filter { $0 < frames.count }
        guard !order.isEmpty else { return nil }

        var warped: [PanoramaRGBImage] = []
        var weights: [[Float]] = []
        warped.reserveCapacity(order.count)
        for index in order {
            guard let camera = cameras[index] else { continue }
            let gain = Float(gains?.indices.contains(index) == true ? gains![index] : 1)
            let (image, weight) = warp(
                frame: frames[index], camera: camera, focal: focal, canvas: canvas, gain: gain
            )
            warped.append(image)
            weights.append(weight)
        }
        guard !warped.isEmpty else { return nil }

        switch quality {
        case .draft:
            return feather(warped, weights: weights)
        case .sharp:
            return multiBand(warped, weights: weights)
        }
    }

    // MARK: Warping

    /// Pulls one frame onto the canvas, and works out how much that frame
    /// should have a say at each canvas pixel.
    ///
    /// The say is a distance-to-edge ramp — full in the middle of the frame,
    /// falling to nothing at its border. That is what makes the blend pick the
    /// frame that saw a point most squarely, rather than whichever frame
    /// happens to be last in the list.
    static func warp(
        frame: PanoramaRGBImage,
        camera: PanoramaCamera,
        focal: Double,
        canvas: PanoramaCanvas,
        gain: Float
    ) -> (PanoramaRGBImage, [Float]) {
        var output = PanoramaRGBImage(width: canvas.width, height: canvas.height)
        var weight = [Float](repeating: 0, count: canvas.width * canvas.height)
        let centreX = Double(frame.width) / 2, centreY = Double(frame.height) / 2

        for y in 0..<canvas.height {
            for x in 0..<canvas.width {
                guard let direction = canvas.direction(atX: Double(x) + 0.5, y: Double(y) + 0.5)
                else { continue }
                let local = PanoramaRotation.apply(camera.rotation, to: direction)
                guard local.2 > 1e-9 else { continue }
                let sourceX = centreX + focal * local.0 / local.2
                let sourceY = centreY + focal * local.1 / local.2
                guard sourceX >= 0, sourceY >= 0,
                      sourceX <= Double(frame.width - 1), sourceY <= Double(frame.height - 1)
                else { continue }

                let colour = sample(frame, x: sourceX, y: sourceY)
                let index = y * canvas.width + x
                output.pixels[3 * index] = colour.0 * gain
                output.pixels[3 * index + 1] = colour.1 * gain
                output.pixels[3 * index + 2] = colour.2 * gain
                output.coverage[index] = 1
                // How far inside its own frame this sample came from, 0 at the
                // border and 1 at the middle.
                let dx = min(sourceX, Double(frame.width - 1) - sourceX) / (Double(frame.width) / 2)
                let dy = min(sourceY, Double(frame.height - 1) - sourceY) / (Double(frame.height) / 2)
                weight[index] = Float(max(1e-4, min(dx, dy)))
            }
        }
        return (output, weight)
    }

    static func sample(_ image: PanoramaRGBImage, x: Double, y: Double) -> (Float, Float, Float) {
        let x0 = min(image.width - 2, max(0, Int(x)))
        let y0 = min(image.height - 2, max(0, Int(y)))
        let tx = Float(x - Double(x0)), ty = Float(y - Double(y0))
        let c00 = image.colour(atX: x0, y: y0), c10 = image.colour(atX: x0 + 1, y: y0)
        let c01 = image.colour(atX: x0, y: y0 + 1), c11 = image.colour(atX: x0 + 1, y: y0 + 1)
        func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
        return (
            mix(mix(c00.0, c10.0, tx), mix(c01.0, c11.0, tx), ty),
            mix(mix(c00.1, c10.1, tx), mix(c01.1, c11.1, tx), ty),
            mix(mix(c00.2, c10.2, tx), mix(c01.2, c11.2, tx), ty)
        )
    }

    // MARK: Draft blend

    /// A weighted average. Cheap, and good enough while a control is moving:
    /// it shows the geometry, which is what the user is adjusting.
    static func feather(_ frames: [PanoramaRGBImage], weights: [[Float]]) -> PanoramaRGBImage {
        let width = frames[0].width, height = frames[0].height
        var output = PanoramaRGBImage(width: width, height: height)
        for index in 0..<(width * height) {
            var total: Float = 0
            var accumulated: (Float, Float, Float) = (0, 0, 0)
            for (frameIndex, frame) in frames.enumerated() {
                let weight = weights[frameIndex][index] * frame.coverage[index]
                guard weight > 0 else { continue }
                accumulated.0 += frame.pixels[3 * index] * weight
                accumulated.1 += frame.pixels[3 * index + 1] * weight
                accumulated.2 += frame.pixels[3 * index + 2] * weight
                total += weight
            }
            guard total > 0 else { continue }
            output.pixels[3 * index] = accumulated.0 / total
            output.pixels[3 * index + 1] = accumulated.1 / total
            output.pixels[3 * index + 2] = accumulated.2 / total
            output.coverage[index] = 1
        }
        return output
    }

    // MARK: Sharp blend

    /// Multi-band blending: each frame's detail is split by scale, the scales
    /// are blended with masks of matching softness, and the result is added
    /// back up.
    static func multiBand(_ frames: [PanoramaRGBImage], weights: [[Float]]) -> PanoramaRGBImage {
        let width = frames[0].width, height = frames[0].height
        let count = width * height
        guard count > 0 else { return PanoramaRGBImage(width: width, height: height) }

        // Each pixel belongs to whichever frame saw it most squarely. Starting
        // from a hard assignment and softening it per band is what keeps fine
        // detail from being averaged into mush.
        var masks = [[Float]](repeating: [Float](repeating: 0, count: count), count: frames.count)
        for index in 0..<count {
            var best = -1
            var bestWeight: Float = 0
            for (frameIndex, frame) in frames.enumerated() where frame.coverage[index] > 0 {
                let weight = weights[frameIndex][index]
                if weight > bestWeight {
                    bestWeight = weight
                    best = frameIndex
                }
            }
            if best >= 0 { masks[best][index] = 1 }
        }

        // Filling the outside of each frame before the pyramid is built is not
        // cosmetic: a blur that reaches past a frame's edge pulls in black and
        // leaves a dark halo all round the panorama.
        let channels: [[[Float]]] = frames.map { frame in
            (0..<3).map { channel in
                filledChannel(frame, channel: channel, width: width, height: height)
            }
        }

        var result = PanoramaRGBImage(width: width, height: height)
        for channel in 0..<3 {
            var accumulated = [Float](repeating: 0, count: count)
            var residuals = frames.indices.map { channels[$0][channel] }
            var blurredMasks = masks

            for band in 0..<bandCount {
                let last = band == bandCount - 1
                var bandTotal = [Float](repeating: 0, count: count)
                var maskTotal = [Float](repeating: 0, count: count)

                for frameIndex in frames.indices {
                    let coarse = last ? nil : blur(residuals[frameIndex], width: width, height: height)
                    let detail: [Float]
                    if let coarse {
                        detail = zip(residuals[frameIndex], coarse).map(-)
                        residuals[frameIndex] = coarse
                    } else {
                        detail = residuals[frameIndex]
                    }
                    let mask = blurredMasks[frameIndex]
                    for index in 0..<count {
                        bandTotal[index] += detail[index] * mask[index]
                        maskTotal[index] += mask[index]
                    }
                    if !last {
                        blurredMasks[frameIndex] = blur(mask, width: width, height: height)
                    }
                }
                for index in 0..<count where maskTotal[index] > 1e-6 {
                    accumulated[index] += bandTotal[index] / maskTotal[index]
                }
            }
            for index in 0..<count {
                result.pixels[3 * index + channel] = accumulated[index]
            }
        }

        for index in 0..<count {
            result.coverage[index] = frames.contains { $0.coverage[index] > 0 } ? 1 : 0
        }
        return result
    }

    /// One channel of a frame, with everything outside its coverage filled in
    /// from the nearest covered pixels.
    static func filledChannel(
        _ frame: PanoramaRGBImage,
        channel: Int,
        width: Int,
        height: Int
    ) -> [Float] {
        var values = [Float](repeating: 0, count: width * height)
        var known = frame.coverage
        for index in values.indices {
            values[index] = frame.pixels[3 * index + channel]
        }
        // A few sweeps of "take the average of whatever neighbours are known"
        // spreads the edge outwards. Cheap, and the numbers only have to be
        // plausible — they are never seen, they are there so the blur has
        // something other than black to reach into.
        for _ in 0..<8 {
            var nextValues = values
            var nextKnown = known
            for y in 0..<height {
                for x in 0..<width {
                    let index = y * width + x
                    guard known[index] <= 0 else { continue }
                    var sum: Float = 0
                    var weight: Float = 0
                    for dy in -1...1 {
                        let ny = y + dy
                        guard ny >= 0, ny < height else { continue }
                        for dx in -1...1 {
                            let nx = x + dx
                            guard nx >= 0, nx < width else { continue }
                            let neighbour = ny * width + nx
                            guard known[neighbour] > 0 else { continue }
                            sum += values[neighbour]
                            weight += 1
                        }
                    }
                    if weight > 0 {
                        nextValues[index] = sum / weight
                        nextKnown[index] = 1
                    }
                }
            }
            values = nextValues
            known = nextKnown
        }
        return values
    }

    /// A 5-tap binomial blur, separable, clamped at the edges. The kernel the
    /// pyramid is built on.
    static func blur(_ values: [Float], width: Int, height: Int) -> [Float] {
        let kernel: [Float] = [1.0 / 16, 4.0 / 16, 6.0 / 16, 4.0 / 16, 1.0 / 16]
        var horizontal = [Float](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for tap in -2...2 {
                    let sampleX = min(width - 1, max(0, x + tap))
                    sum += values[y * width + sampleX] * kernel[tap + 2]
                }
                horizontal[y * width + x] = sum
            }
        }
        var output = [Float](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                for tap in -2...2 {
                    let sampleY = min(height - 1, max(0, y + tap))
                    sum += horizontal[sampleY * width + x] * kernel[tap + 2]
                }
                output[y * width + x] = sum
            }
        }
        return output
    }
}
