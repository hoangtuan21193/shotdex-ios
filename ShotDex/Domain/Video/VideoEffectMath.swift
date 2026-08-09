import CoreGraphics
import Foundation

/// Pure math behind the per-clip effects and transition blends — no Core
/// Image, so every ramp, offset, and transform is unit-testable. All spatial
/// values scale with the render size, so preview (1280 long edge) and export
/// (1080p/4K) read identically.
enum VideoEffectMath {
    // MARK: Progress & easing

    /// 0…1 position inside a clip's placement, clamped.
    static func clipProgress(time: Double, clipStart: Double, clipDuration: Double) -> Double {
        guard clipDuration > 0 else { return 1 }
        return min(max((time - clipStart) / clipDuration, 0), 1)
    }

    /// Smoothstep — eases the slide/zoom transitions and the pans.
    static func eased(_ t: Double) -> Double {
        let clamped = min(max(t, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    // MARK: Clip effects — geometry

    static let zoomTravel = 0.12
    static let panPreScale = 1.06
    /// Pan travel per side, as a fraction of the canvas width.
    static let panTravel = 0.02
    /// Shake amplitude as a fraction of the canvas short edge.
    static let shakeAmplitude = 0.01
    /// Shake ramps to zero over this window at both clip edges so it never
    /// pops across a transition boundary.
    static let shakeEdgeWindow = 0.2

    /// The affine a geometric effect applies to the fitted frame, about the
    /// canvas centre. Identity for every non-geometric effect.
    static func effectTransform(
        effect: VideoClipEffect,
        progress: Double,
        time: Double,
        clipStart: Double,
        clipDuration: Double,
        clipIndex: Int,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let center = CGPoint(x: renderSize.width / 2, y: renderSize.height / 2)
        func aboutCenter(scale: Double, tx: Double = 0, ty: Double = 0) -> CGAffineTransform {
            CGAffineTransform(translationX: center.x + tx, y: center.y + ty)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -center.x, y: -center.y)
        }
        switch effect {
        case .zoomIn:
            return aboutCenter(scale: 1 + zoomTravel * progress)
        case .zoomOut:
            return aboutCenter(scale: 1 + zoomTravel * (1 - progress))
        case .panLeft:
            let tx = (1 - 2 * eased(progress)) * panTravel * renderSize.width
            return aboutCenter(scale: panPreScale, tx: tx)
        case .panRight:
            let tx = (2 * eased(progress) - 1) * panTravel * renderSize.width
            return aboutCenter(scale: panPreScale, tx: tx)
        case .shake:
            let offset = shakeOffset(
                time: time,
                clipStart: clipStart,
                clipDuration: clipDuration,
                clipIndex: clipIndex,
                renderSize: renderSize
            )
            return CGAffineTransform(translationX: offset.dx, y: offset.dy)
        case .none, .blurIn, .blurOut, .softGlow, .vignettePulse:
            return .identity
        }
    }

    /// Deterministic shake: composition time quantized to 30 fps frames,
    /// hashed with the clip index — the preview and the export share the
    /// frame duration and the instructions, so they land on identical
    /// offsets. Amplitude windows to zero at the clip's edges.
    static func shakeOffset(
        time: Double,
        clipStart: Double,
        clipDuration: Double,
        clipIndex: Int,
        renderSize: CGSize
    ) -> CGVector {
        guard clipDuration > 0 else { return .zero }
        let local = time - clipStart
        let window = min(1, max(0, min(local, clipDuration - local) / shakeEdgeWindow))
        guard window > 0 else { return .zero }
        let frame = UInt64(max(0, (time * 30).rounded(.down)))
        let seed = frame &* 0x9E3779B97F4A7C15 ^ (UInt64(bitPattern: Int64(clipIndex)) &<< 32)
        let amplitude = shakeAmplitude * min(renderSize.width, renderSize.height) * window
        let dx = (unitRandom(splitMix64(seed)) * 2 - 1) * amplitude
        let dy = (unitRandom(splitMix64(seed ^ 0xBF58476D1CE4E5B9)) * 2 - 1) * amplitude
        return CGVector(dx: dx, dy: dy)
    }

    private static func splitMix64(_ input: UInt64) -> UInt64 {
        var z = input &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    private static func unitRandom(_ hash: UInt64) -> Double {
        Double(hash >> 11) / Double(1 << 53)
    }

    // MARK: Clip effects — radii & intensities

    /// Blur ramp reference radius at a 1080-short-edge canvas.
    static let blurBaseRadius = 12.0
    /// The ramp window; short clips shrink it to their own length.
    static let blurRampSeconds = 0.8

    /// blurIn: full blur → sharp over the clip's first ramp window;
    /// blurOut: sharp → full blur over the last. Zero for other effects.
    static func effectBlurRadius(
        effect: VideoClipEffect,
        time: Double,
        clipStart: Double,
        clipDuration: Double,
        renderSize: CGSize
    ) -> Double {
        guard clipDuration > 0 else { return 0 }
        let ramp = min(blurRampSeconds, clipDuration)
        let local = min(max(time - clipStart, 0), clipDuration)
        let scale = min(renderSize.width, renderSize.height) / 1080
        switch effect {
        case .blurIn:
            return blurBaseRadius * scale * max(0, 1 - local / ramp)
        case .blurOut:
            let fromEnd = clipDuration - local
            return blurBaseRadius * scale * max(0, 1 - fromEnd / ramp)
        default:
            return 0
        }
    }

    static func glowRadius(renderSize: CGSize) -> Double {
        20 * min(renderSize.width, renderSize.height) / 1080
    }

    static let glowIntensity = 0.6

    /// 0.25 Hz sine on local clip time, phase-shifted to start at the trough
    /// so the pulse breathes in from its gentlest point. Range 0.2…0.8.
    static func vignettePulseIntensity(localTime: Double) -> Double {
        0.5 + 0.3 * sin(2 * .pi * 0.25 * localTime - .pi / 2)
    }

    static func vignetteRadius(renderSize: CGSize) -> Double {
        0.9 * min(renderSize.width, renderSize.height)
    }

    // MARK: Transitions

    /// Horizontal push: both frames travel a full canvas width, eased. At
    /// p = 0 the incoming frame sits fully offscreen and the outgoing at
    /// rest; at p = 1 they've swapped.
    static func slideOffsets(
        kind: VideoTransitionKind,
        progress: Double,
        renderSize: CGSize
    ) -> (front: CGVector, back: CGVector) {
        let travel = eased(progress) * renderSize.width
        switch kind {
        case .slideLeft:
            return (
                front: CGVector(dx: renderSize.width - travel, dy: 0),
                back: CGVector(dx: -travel, dy: 0)
            )
        case .slideRight:
            return (
                front: CGVector(dx: travel - renderSize.width, dy: 0),
                back: CGVector(dx: travel, dy: 0)
            )
        default:
            return (front: .zero, back: .zero)
        }
    }

    /// Outgoing frame scale for the zoom transition: 1 → 1.3, eased.
    static func zoomTransitionScale(progress: Double) -> Double {
        1 + 0.3 * eased(progress)
    }

    /// Soft edge of the wipe as a fraction of the canvas width.
    static let wipeSoftness = 0.05

    /// Left-to-right wipe: gradient x endpoints for a white(front)→black(back)
    /// mask. The edge travels from beyond the left edge to beyond the right
    /// so p = 0 shows none of the incoming frame and p = 1 all of it.
    static func wipeGradientX(progress: Double, width: Double) -> (whiteX: Double, blackX: Double) {
        let soft = wipeSoftness * width
        let edge = -soft + eased(progress) * (width + 2 * soft)
        return (whiteX: edge - soft, blackX: edge + soft)
    }

    enum FadeBlackStage: Equatable {
        case out, `in`
    }

    /// First half dissolves the outgoing frame to black, second half
    /// dissolves black up to the incoming frame.
    static func fadeBlackStage(progress: Double) -> (stage: FadeBlackStage, t: Double) {
        let clamped = min(max(progress, 0), 1)
        if clamped < 0.5 {
            return (.out, clamped * 2)
        }
        return (.in, clamped * 2 - 1)
    }
}
