import SwiftUI
import UIKit

/// The hold-drag from the Media grid in progress (FS-12.09 §5): what the
/// finger carries, where it is in window coordinates, and the seam it would
/// land on. Screen state — never part of the project or of undo.
struct VideoMediaDrag: Equatable {
    var picks: [VideoMediaPick]
    /// The finger, in window coordinates.
    var location: CGPoint
    /// The cell it was lifted from, for the flight back on a cancel.
    var origin: CGRect
    /// The seam under the finger, when it is over a drop target.
    var target: Target?
    /// Flying back to the grid after a cancelled drop.
    var isReturning = false

    struct Target: Equatable {
        let boundary: MediaInsertMath.Boundary
        /// The white line, in window coordinates: the lane's height (or the
        /// overview strip's) at the seam's x.
        let line: CGRect
    }
}

/// Where a timeline-shaped drop target sits on screen and how its x maps to
/// time — the timeline's lanes (playhead in the middle, `pps` points a
/// second) or the overview strip (the whole project across its width).
struct VideoDropGeometry: Equatable {
    enum Mapping: Equatable {
        case timeline(playheadX: CGFloat, pointsPerSecond: CGFloat)
        case overview(totalDuration: Double)
    }

    /// The region a drop is accepted in, window coordinates.
    var frame: CGRect
    /// The band the insertion line spans — the video lane, or the strip.
    var lineBand: CGRect
    var mapping: Mapping

    func time(atX x: CGFloat, currentTime: Double) -> Double {
        switch mapping {
        case let .timeline(playheadX, pps):
            pps > 0 ? currentTime + Double((x - playheadX) / pps) : currentTime
        case let .overview(total):
            frame.width > 0 ? Double((x - frame.minX) / frame.width) * total : 0
        }
    }

    func x(atTime time: Double, currentTime: Double) -> CGFloat {
        switch mapping {
        case let .timeline(playheadX, pps):
            playheadX + CGFloat(time - currentTime) * pps
        case let .overview(total):
            total > 0 ? frame.minX + frame.width * CGFloat(time / total) : frame.minX
        }
    }
}

/// What the drag draws over the whole studio (FS-12.09 §5): a 70pt ghost of
/// the lifted item under the finger — 1.1×, tilted −3°, a 2pt white edge, a
/// count when it carries several — and, over a drop target, a 4pt white
/// line on the seam with "+ 0:14.2" above it.
struct VideoMediaDragOverlay: View {
    let model: VideoStudioModel

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            if let drag = model.mediaDrag {
                ZStack(alignment: .topLeading) {
                    if let target = drag.target {
                        let line = target.line.offsetBy(dx: -origin.x, dy: -origin.y)
                        Rectangle()
                            .fill(Color.white)
                            .frame(width: line.width, height: line.height)
                            .shadow(color: .black.opacity(0.5), radius: 3)
                            .position(x: line.midX, y: line.midY)
                        Text(verbatim: "+ " + VideoStudioMetrics.compactTimecode(target.boundary.time))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.black)
                            .frame(width: 68, height: 20)
                            .background(Capsule().fill(Color.white))
                            // Kept on screen when the seam is near an edge.
                            .position(
                                x: min(max(line.midX, 38), proxy.size.width - 38),
                                y: line.minY - 14
                            )
                            .accessibilityIdentifier("mediaDropPill")
                    }
                    ghost(drag)
                        .position(x: drag.location.x - origin.x, y: drag.location.y - origin.y)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func ghost(_ drag: VideoMediaDrag) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
            .overlay {
                if let image = model.mediaDragImage {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: 70, height: 70)
            .clipped()
            .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 2))
            .overlay(alignment: .topLeading) {
                if drag.picks.count > 1 {
                    Text(verbatim: "\(drag.picks.count)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 21, height: 21)
                        .background(Circle().fill(Color.white))
                        .offset(x: -8, y: -8)
                }
            }
            .scaleEffect(drag.isReturning ? 1 : 1.1)
            .rotationEffect(.degrees(drag.isReturning ? 0 : -3))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .opacity(drag.isReturning ? 0.6 : 1)
            .accessibilityIdentifier("mediaDragGhost")
    }
}
