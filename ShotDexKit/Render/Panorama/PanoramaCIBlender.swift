import CoreImage
import Foundation

/// One frame as the GPU path wants it.
public struct PanoramaCISource {
    public var image: CIImage
    public var width: Int
    public var height: Int
    public var camera: PanoramaCamera
    /// Exposure multiplier from the gain solve.
    public var gain: Double

    public init(image: CIImage, width: Int, height: Int, camera: PanoramaCamera, gain: Double = 1) {
        self.image = image
        self.width = width
        self.height = height
        self.camera = camera
        self.gain = gain
    }
}

/// The blend, on the GPU.
///
/// `PanoramaCompositor` does the same arithmetic in Swift and is the reference
/// the tests check this against — but it is not what runs when somebody presses
/// Save. Measured: the CPU draft costs 2,433 ms per megapixel in a debug build
/// and the sharp blend did not finish a tenth of a megapixel in twenty-five
/// minutes, while Core Image composites ten frames at 1536 px in 21.6 ms. One
/// of those can follow a finger on a slider and the other cannot.
public enum PanoramaCIBlender {

    /// Warps and blends every frame into one image, weighted so each point
    /// comes from whichever frame saw it most squarely.
    ///
    /// The whole thing is one Core Image graph: nothing is rendered until the
    /// caller asks for pixels, so a preview that is about to be replaced by the
    /// next drag costs nothing if it is dropped first.
    public static func draft(
        canvas: PanoramaCanvas,
        sources: [PanoramaCISource],
        focal: Double
    ) -> CIImage? {
        guard canvas.width > 0, canvas.height > 0, !sources.isEmpty else { return nil }
        guard let warpKernel, let rampKernel, let resolveKernel,
              let accumulateColourKernel, let accumulateWeightKernel
        else { return nil }

        let canvasExtent = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        // Two accumulators, not one with the weight hidden in alpha. Alpha in
        // Core Image means premultiplication, and a running weight sum is
        // routinely above 1 where frames overlap — putting it there invites
        // every filter in the chain to treat it as coverage and clamp it.
        var colourTotal = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: canvasExtent)
        var weightTotal = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1))
            .cropped(to: canvasExtent)

        for source in sources {
            guard source.width > 0, source.height > 0 else { continue }
            let arguments = warpArguments(canvas: canvas, source: source, focal: focal)
            let sourceExtent = CGRect(x: 0, y: 0, width: source.width, height: source.height)

            // How much this frame should have a say: full in the middle, nothing
            // at its border. Built on the GPU rather than handed in, because it
            // depends only on the frame's size.
            guard let ramp = rampKernel.apply(
                extent: sourceExtent,
                roiCallback: { _, rect in rect },
                arguments: [Float(source.width), Float(source.height)]
            ) else { continue }

            guard let warpedColour = warpKernel.apply(
                extent: canvasExtent,
                roiCallback: { _, rect in sourceRegion(for: rect, canvas: canvas, source: source, focal: focal) },
                image: source.image,
                arguments: arguments
            ), let warpedWeight = warpKernel.apply(
                extent: canvasExtent,
                roiCallback: { _, rect in sourceRegion(for: rect, canvas: canvas, source: source, focal: focal) },
                image: ramp,
                arguments: arguments
            ) else { continue }

            guard let nextColour = accumulateColourKernel.apply(
                extent: canvasExtent,
                arguments: [colourTotal, warpedColour, warpedWeight, Float(source.gain)]
            ), let nextWeight = accumulateWeightKernel.apply(
                extent: canvasExtent,
                arguments: [weightTotal, warpedColour, warpedWeight]
            ) else { continue }
            colourTotal = nextColour
            weightTotal = nextWeight
        }

        return resolveKernel.apply(extent: canvasExtent, arguments: [colourTotal, weightTotal])
    }

    /// The blend that gets saved: detail split by scale, each scale joined with
    /// a mask of matching softness.
    ///
    /// Same idea as the reference, arranged the way Core Image wants it. The
    /// bands come from blurring the warped frame at doubling radii rather than
    /// from a chain of five-tap passes — the same pyramid, a fifth of the
    /// nodes, and Core Image's own Gaussian is the part of this it is best at.
    ///
    /// Needs a float working format. Band detail is a difference and is
    /// routinely negative, and in an eight-bit context every one of those
    /// becomes zero — which looks like a blend that simply does not work.
    /// `seamMasks`, when given, replaces the "whichever frame saw it most
    /// squarely" answer with one that puts the joins where the frames agree
    /// (`PanoramaSeamPlanner`). One image per source, in the same order.
    public static func sharp(
        canvas: PanoramaCanvas,
        sources: [PanoramaCISource],
        focal: Double,
        bandCount: Int = PanoramaCompositor.bandCount,
        seamMasks: [CIImage]? = nil
    ) -> CIImage? {
        guard canvas.width > 0, canvas.height > 0, !sources.isEmpty, bandCount >= 1 else { return nil }
        guard let maximumKernel, let maskKernel, let bandKernel,
              let bandWeightKernel, let resolveKernel, let differenceKernel
        else { return nil }

        let canvasExtent = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        var colours: [CIImage] = []
        var weights: [CIImage] = []
        for source in sources {
            guard let pair = warped(canvas: canvas, source: source, focal: focal) else { continue }
            colours.append(pair.colour)
            weights.append(pair.weight)
        }
        guard !colours.isEmpty else { return nil }

        // Which frame owns each pixel: the one that saw it most squarely. Found
        // in two passes because a per-pixel argmax across N images is not a
        // thing one kernel can do — first the running maximum, then each
        // frame's own claim against it.
        var runningMaximum = weights[0]
        for weight in weights.dropFirst() {
            guard let next = maximumKernel.apply(
                extent: canvasExtent, arguments: [runningMaximum, weight]
            ) else { return nil }
            runningMaximum = next
        }
        var masks: [CIImage] = []
        if let seamMasks, seamMasks.count == colours.count {
            masks = seamMasks
        } else {
            for weight in weights {
                guard let mask = maskKernel.apply(
                    extent: canvasExtent, arguments: [weight, runningMaximum]
                ) else { return nil }
                masks.append(mask)
            }
        }

        // How wide the coarsest band may reach.
        //
        // Doubling from one pixel is the textbook pyramid, but the top of it
        // has to stay *local*: a band that blurs across the whole picture is no
        // longer the lowest frequency of a place, it is the average of
        // everything, and the blend then pulls every frame towards one level —
        // two frames a stop apart come out the same grey. A sixteenth of the
        // shorter side keeps the coarsest band wider than any seam and far
        // narrower than the panorama.
        let coarsestSigma = max(2.0, Double(min(canvas.width, canvas.height)) / 16)

        var accumulated: CIImage?
        for band in 0..<bandCount {
            let last = band == bandCount - 1
            let radius = Float(min(Double(1 << band), coarsestSigma))
            var bandTotal: CIImage?
            var maskTotal: CIImage?

            for index in colours.indices {
                // Clamped before blurring: a blur that reaches past a frame's
                // edge otherwise pulls in nothing and rings the panorama with a
                // dark halo. Repeating the edge is the cheap stand-in for the
                // reference's fill.
                let base = colours[index].clampedToExtent()
                let coarse = base.applyingGaussianBlur(sigma: Double(radius))
                let detail: CIImage
                if last {
                    detail = coarse.cropped(to: canvasExtent)
                } else {
                    let finerSigma = min(Double(1 << band) / 2, coarsestSigma)
                    let finer = band == 0 ? base : base.applyingGaussianBlur(sigma: finerSigma)
                    guard let difference = differenceKernel.apply(
                        extent: canvasExtent,
                        arguments: [finer.cropped(to: canvasExtent), coarse.cropped(to: canvasExtent)]
                    ) else { return nil }
                    detail = difference
                }
                let softMask = masks[index].clampedToExtent()
                    .applyingGaussianBlur(sigma: Double(radius))
                    .cropped(to: canvasExtent)

                guard let nextBand = bandKernel.apply(
                    extent: canvasExtent,
                    arguments: [bandTotal ?? transparent(canvasExtent), detail, softMask]
                ), let nextMask = bandWeightKernel.apply(
                    extent: canvasExtent,
                    arguments: [maskTotal ?? transparent(canvasExtent), softMask]
                ) else { return nil }
                bandTotal = nextBand
                maskTotal = nextMask
            }

            guard let bandTotal, let maskTotal,
                  let resolved = resolveKernel.apply(extent: canvasExtent, arguments: [bandTotal, maskTotal])
            else { return nil }
            if let running = accumulated {
                guard let sum = sumKernel?.apply(extent: canvasExtent, arguments: [running, resolved])
                else { return nil }
                accumulated = sum
            } else {
                accumulated = resolved
            }
        }

        // Coverage comes from the draft's own answer: the bands carry detail,
        // not the question of where the panorama is.
        guard let accumulated, let coverage = draft(canvas: canvas, sources: sources, focal: focal),
              let masked = coverageKernel?.apply(extent: canvasExtent, arguments: [accumulated, coverage])
        else { return accumulated }
        return masked
    }

    private static func transparent(_ extent: CGRect) -> CIImage {
        CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
    }

    /// One frame, warped onto the canvas, with its say beside it.
    static func warped(
        canvas: PanoramaCanvas,
        source: PanoramaCISource,
        focal: Double
    ) -> (colour: CIImage, weight: CIImage)? {
        guard let warpKernel, let rampKernel, let gainKernel else { return nil }
        let canvasExtent = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        let sourceExtent = CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let arguments = warpArguments(canvas: canvas, source: source, focal: focal)
        guard let ramp = rampKernel.apply(
            extent: sourceExtent,
            roiCallback: { _, rect in rect },
            arguments: [Float(source.width), Float(source.height)]
        ), let colour = warpKernel.apply(
            extent: canvasExtent,
            roiCallback: { _, rect in sourceRegion(for: rect, canvas: canvas, source: source, focal: focal) },
            image: source.image,
            arguments: arguments
        ), let weight = warpKernel.apply(
            extent: canvasExtent,
            roiCallback: { _, rect in sourceRegion(for: rect, canvas: canvas, source: source, focal: focal) },
            image: ramp,
            arguments: arguments
        ), let gained = gainKernel.apply(
            extent: canvasExtent, arguments: [colour, Float(source.gain)]
        ) else { return nil }
        return (gained, weight)
    }

    // MARK: Arguments

    /// Everything the warp kernel needs, worked out once per frame on the CPU.
    ///
    /// The two rotations are folded into one matrix here rather than applied in
    /// the kernel: the kernel runs per pixel, and this runs per frame.
    static func warpArguments(
        canvas: PanoramaCanvas,
        source: PanoramaCISource,
        focal: Double
    ) -> [Any] {
        let combined = PanoramaRotation.multiply(
            source.camera.rotation, PanoramaRotation.transposed(canvas.frame)
        )
        let kind: Float
        switch canvas.kind {
        case .spherical: kind = 0
        case .cylindrical: kind = 1
        case .perspective: kind = 2
        }
        return [
            CIVector(x: CGFloat(canvas.originU), y: CGFloat(canvas.originV)),
            Float(canvas.height),
            Float(canvas.focal),
            kind,
            CIVector(x: CGFloat(combined[0]), y: CGFloat(combined[1]), z: CGFloat(combined[2])),
            CIVector(x: CGFloat(combined[3]), y: CGFloat(combined[4]), z: CGFloat(combined[5])),
            CIVector(x: CGFloat(combined[6]), y: CGFloat(combined[7]), z: CGFloat(combined[8])),
            Float(focal),
            CIVector(x: CGFloat(source.width) / 2, y: CGFloat(source.height) / 2),
            CIVector(x: CGFloat(source.width), y: CGFloat(source.height)),
        ]
    }

    /// Which part of a frame a slab of canvas can possibly need.
    ///
    /// Core Image asks this so it never has to hold a whole frame to draw a
    /// strip of output — which is the difference between a strip renderer and
    /// one that needs every full-resolution frame resident at once. The corners
    /// of the output rect are mapped back and the box padded, because the map
    /// bends between them.
    static func sourceRegion(
        for rect: CGRect,
        canvas: PanoramaCanvas,
        source: PanoramaCISource,
        focal: Double
    ) -> CGRect {
        let combined = PanoramaRotation.multiply(
            source.camera.rotation, PanoramaRotation.transposed(canvas.frame)
        )
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        var sawAny = false

        // A grid rather than four corners: a spherical map can bow far enough
        // between two corners that the corner box misses the middle.
        for row in 0...4 {
            for column in 0...4 {
                let x = Double(rect.minX) + Double(column) / 4 * Double(rect.width)
                let ciY = Double(rect.minY) + Double(row) / 4 * Double(rect.height)
                let y = Double(canvas.height) - ciY
                guard let direction = PanoramaProjection.unproject(
                    u: x + canvas.originU, v: y + canvas.originV, kind: canvas.kind, focal: canvas.focal
                ) else { continue }
                let local = PanoramaRotation.apply(combined, to: direction)
                guard local.2 > 1e-9 else { continue }
                let sx = Double(source.width) / 2 + focal * local.0 / local.2
                let sy = Double(source.height) / 2 + focal * local.1 / local.2
                minX = min(minX, sx); maxX = max(maxX, sx)
                minY = min(minY, sy); maxY = max(maxY, sy)
                sawAny = true
            }
        }
        guard sawAny, minX.isFinite, maxX.isFinite, minY.isFinite, maxY.isFinite else {
            return CGRect(x: 0, y: 0, width: source.width, height: source.height)
        }
        // Back to Core Image's y-up space, with a margin for the bowing and for
        // the sampler's own footprint.
        let padding = 4.0
        let top = Double(source.height) - minY
        let bottom = Double(source.height) - maxY
        return CGRect(
            x: minX - padding,
            y: min(top, bottom) - padding,
            width: (maxX - minX) + 2 * padding,
            height: abs(top - bottom) + 2 * padding
        )
    }

    // MARK: Kernels

    /// Canvas pixel to source pixel: undo the projection, turn the ray into the
    /// frame's own view, and put it back on the sensor.
    ///
    /// Anything the frame did not see is sent far outside its extent, where
    /// Core Image samples transparent — so "this frame has nothing here" needs
    /// no branch anywhere downstream.
    static let warpKernel = CIWarpKernel(source: """
        kernel vec2 panoramaWarp(vec2 origin, float canvasHeight, float canvasFocal, float kind,
                                 vec3 m0, vec3 m1, vec3 m2,
                                 float sourceFocal, vec2 sourceCentre, vec2 sourceSize) {
            vec2 d = destCoord();
            float u = d.x + origin.x;
            float v = (canvasHeight - d.y) + origin.y;

            vec3 dir;
            if (kind < 0.5) {
                float theta = u / canvasFocal;
                float phi = v / canvasFocal;
                float c = cos(phi);
                dir = vec3(c * sin(theta), sin(phi), c * cos(theta));
            } else if (kind < 1.5) {
                float theta = u / canvasFocal;
                dir = vec3(sin(theta), v / canvasFocal, cos(theta));
            } else {
                dir = vec3(u / canvasFocal, v / canvasFocal, 1.0);
            }

            vec3 local = vec3(dot(m0, dir), dot(m1, dir), dot(m2, dir));
            if (local.z <= 0.000000001) {
                return vec2(-100000.0, -100000.0);
            }
            float sx = sourceCentre.x + sourceFocal * local.x / local.z;
            float sy = sourceCentre.y + sourceFocal * local.y / local.z;
            if (sx < 0.0 || sy < 0.0 || sx > sourceSize.x - 1.0 || sy > sourceSize.y - 1.0) {
                return vec2(-100000.0, -100000.0);
            }
            // Half a pixel, and it matters: the reference measures a frame in
            // index space, where 0 is the centre of the first pixel, while
            // Core Image measures in continuous space, where that centre is at
            // 0.5 — and its y runs the other way. Getting this wrong shifts
            // every sample by half a pixel, which is invisible on a gradient
            // and glaring on anything with fine detail.
            return vec2(sx + 0.5, sourceSize.y - 0.5 - sy);
        }
        """)

    /// How far inside its own frame a sample is, 0 at the border and 1 in the
    /// middle. The same ramp the CPU reference uses.
    static let rampKernel = CIColorKernel(source: """
        kernel vec4 panoramaRamp(float width, float height) {
            vec2 d = destCoord();
            // Back to the index space the reference works in, same half pixel
            // as the warp.
            float x = d.x - 0.5;
            float y = height - 0.5 - d.y;
            float dx = min(x, width - 1.0 - x) / (width * 0.5);
            float dy = min(y, height - 1.0 - y) / (height * 0.5);
            float w = max(0.0001, min(dx, dy));
            return vec4(w, w, w, 1.0);
        }
        """)

    /// Running colour total: the frame's colour times its say.
    ///
    /// `colour.a` is the coverage the warp produced — 1 where the frame reached
    /// and 0 where it did not — and it is what decides whether this frame
    /// contributes at all. The weight is read from the ramp's red channel; its
    /// own alpha is not multiplied in again, because a `__sample` is already
    /// premultiplied and doing it twice makes the ramp fall off twice as fast
    /// at every frame border.
    static let accumulateColourKernel = CIColorKernel(source: """
        kernel vec4 panoramaAccumulateColour(__sample total, __sample colour, __sample weight, float gain) {
            if (colour.a <= 0.0) { return total; }
            // A sample straddling the frame's border comes back premultiplied
            // by a fraction of coverage. Undoing that recovers the colour the
            // frame actually has there, and lets the weight alone decide how
            // much of it to take — otherwise the border darkens or lightens
            // depending on which way the sampler fell.
            vec3 unpremultiplied = colour.rgb / colour.a;
            float w = weight.r * colour.a;
            return vec4(total.rgb + unpremultiplied * gain * w, 1.0);
        }
        """)

    /// Running weight total, in the same units, so the divide is exact.
    static let accumulateWeightKernel = CIColorKernel(source: """
        kernel vec4 panoramaAccumulateWeight(__sample total, __sample colour, __sample weight) {
            if (colour.a <= 0.0) { return total; }
            float w = weight.r * colour.a;
            return vec4(total.rgb + vec3(w, w, w), 1.0);
        }
        """)

    /// Running maximum of two weight images, for finding which frame owns a
    /// pixel without a kernel that takes them all at once.
    static let maximumKernel = CIColorKernel(source: """
        kernel vec4 panoramaMaximum(__sample a, __sample b) {
            float wa = a.r * a.a;
            float wb = b.r * b.a;
            float w = max(wa, wb);
            return vec4(w, w, w, 1.0);
        }
        """)

    /// One frame's claim: it owns the pixel if its say is the largest there.
    ///
    /// A hard claim, softened per band afterwards. Starting soft instead blurs
    /// fine detail from two frames together, which is the double image
    /// multi-band blending exists to avoid.
    static let maskKernel = CIColorKernel(source: """
        kernel vec4 panoramaMask(__sample weight, __sample maximum) {
            float w = weight.r * weight.a;
            float m = (w > 0.0 && w >= maximum.r - 0.000001) ? 1.0 : 0.0;
            return vec4(m, m, m, 1.0);
        }
        """)

    static let differenceKernel = CIColorKernel(source: """
        kernel vec4 panoramaDifference(__sample fine, __sample coarse) {
            return vec4(fine.rgb - coarse.rgb, 1.0);
        }
        """)

    static let gainKernel = CIColorKernel(source: """
        kernel vec4 panoramaGain(__sample colour, float gain) {
            if (colour.a <= 0.0) { return vec4(0.0, 0.0, 0.0, 0.0); }
            return vec4(colour.rgb / colour.a * gain, colour.a);
        }
        """)

    static let bandKernel = CIColorKernel(source: """
        kernel vec4 panoramaBand(__sample total, __sample detail, __sample mask) {
            return vec4(total.rgb + detail.rgb * mask.r, 1.0);
        }
        """)

    static let bandWeightKernel = CIColorKernel(source: """
        kernel vec4 panoramaBandWeight(__sample total, __sample mask) {
            return vec4(total.rgb + vec3(mask.r, mask.r, mask.r), 1.0);
        }
        """)

    static let sumKernel = CIColorKernel(source: """
        kernel vec4 panoramaSum(__sample a, __sample b) {
            return vec4(a.rgb + b.rgb, 1.0);
        }
        """)

    /// Puts the draft's coverage back on the banded result, so the crop that
    /// follows reads the same shape either way.
    static let coverageKernel = CIColorKernel(source: """
        kernel vec4 panoramaCoverage(__sample colour, __sample reference) {
            if (reference.a <= 0.0) { return vec4(0.0, 0.0, 0.0, 0.0); }
            return vec4(colour.rgb, 1.0);
        }
        """)

    /// Divide the totals back out. Where nothing landed, stay transparent —
    /// that is the coverage the crop later reads.
    static let resolveKernel = CIColorKernel(source: """
        kernel vec4 panoramaResolve(__sample colourTotal, __sample weightTotal) {
            if (weightTotal.r <= 0.0) { return vec4(0.0, 0.0, 0.0, 0.0); }
            return vec4(colourTotal.rgb / weightTotal.r, 1.0);
        }
        """)
}
