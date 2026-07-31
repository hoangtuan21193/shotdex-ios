import SwiftUI

/// The index readout on the dim overlay: one large ring with the percentage,
/// the photo count and the wait inside it, and the network/advisory lines
/// underneath.
///
/// Everything stays faint (white at ~55%) because the overlay's job is to keep
/// an OLED panel mostly dark while a long run finishes. Two things move, both
/// on purpose:
///
/// - a **comet arc** sweeping the ring once every few seconds, so the screen
///   reads as alive even when the fraction sits still through a slow iCloud
///   batch (a 200-photo batch can take two minutes to tick over);
/// - the whole cluster **drifting** ±16pt, so no pixel holds the same value
///   long enough to burn in.
///
/// Both are single-layer transforms — no per-frame layout, no redraw of the
/// text — so the cost is a compositor animation, not a render loop.
struct DimIndexProgressView: View {
    let progress: IndexProgress?
    let throughput: IndexThroughput?
    let networkStatus: IndexNetworkStatus?
    let diagnostics: IndexDiagnostics?

    private static let ringSize: CGFloat = 280
    private static let ringWidth: CGFloat = 14
    /// One sweep revolution. Slow enough to read as breathing rather than
    /// spinning — a fast spinner on a dimmed screen reads as an error.
    private static let sweepInterval: TimeInterval = 6

    /// Slow vertical drift so static text never sits on the same OLED pixels.
    /// Each step glides over ~the full interval, so motion is ~1–2 pt/s —
    /// below the perception threshold but enough travel to avoid burn-in.
    private static let driftPositions: [CGFloat] = [-16, 0, 16, 0]
    private static let driftInterval: TimeInterval = 20

    @State private var driftIndex = 0
    @State private var isSweeping = false
    private let driftTimer = Timer.publish(every: driftInterval, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Text("Reading photo and video info")
                .font(.title3.weight(.semibold))
            ring
            VStack(spacing: 8) {
                // Always-on network readout — speed and downloaded total show
                // even at zero so the state is legible at a glance without
                // waiting for traffic to start.
                if let networkStatus {
                    Text(networkStatus.detailedLine)
                        .monospacedDigit()
                }
                // Plain-language notes, and only while something is holding
                // the run back (warm device, Low Power Mode, iCloud silent).
                if let diagnostics {
                    ForEach(diagnostics.advisories, id: \.self) { advisory in
                        Text(advisory)
                    }
                }
            }
            .font(.subheadline)
            Text("ShotDex is reading the camera, lens and exposure info from each photo and video. For items kept in iCloud it downloads only the small part of the file holding that info — nothing is saved to this iPhone.")
                .font(.footnote)
                .padding(.horizontal, 40)
        }
        .multilineTextAlignment(.center)
        .tint(.white.opacity(0.6))
        .foregroundStyle(.white.opacity(0.55))
        .offset(y: Self.driftPositions[driftIndex])
        .animation(.easeInOut(duration: Self.driftInterval - 1), value: driftIndex)
        .onReceive(driftTimer) { _ in
            driftIndex = (driftIndex + 1) % Self.driftPositions.count
        }
        .onAppear { isSweeping = true }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.1), lineWidth: Self.ringWidth)
            comet
            if let fraction = progress?.fraction {
                Circle()
                    // A floor keeps a rounded cap visible at 0%, so the ring
                    // never looks like it failed to start.
                    .trim(from: 0, to: max(0.004, fraction))
                    .stroke(
                        .white.opacity(0.6),
                        style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.6), value: fraction)
            }
            centerReadout
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            progress.map { "Reading photo and video info, \($0.percent) percent, \($0.processed) of \($0.total) items" }
                ?? "Reading photo and video info"
        )
    }

    /// Short arc that fades in towards its leading edge, rotating forever. The
    /// gradient stops are placed inside the trimmed span so the fade lands on
    /// the arc itself rather than being spread over the whole circle.
    ///
    /// Thinner and dimmer than the progress arc on purpose: at full weight the
    /// two read as two progress values, and the sweep has to read as a
    /// highlight passing over the track.
    private var comet: some View {
        Circle()
            .trim(from: 0, to: 0.18)
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: .white.opacity(0), location: 0),
                        .init(color: .white.opacity(0.3), location: 0.18)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: Self.ringWidth * 0.5, lineCap: .round)
            )
            .rotationEffect(.degrees(isSweeping ? 360 : 0))
            .animation(
                .linear(duration: Self.sweepInterval).repeatForever(autoreverses: false),
                value: isSweeping
            )
    }

    /// Percentage, count and wait, stacked inside the ring. Held to one line
    /// each with a scale floor: the count grows to five digits on a big
    /// library and must not wrap into the stroke.
    private var centerReadout: some View {
        VStack(spacing: 4) {
            if let progress, progress.total > 0 {
                Text("\(progress.percent)%")
                    .font(.system(size: 64, weight: .semibold, design: .rounded).monospacedDigit())
                Text("\(progress.processed.formatted()) of \(progress.total.formatted()) photos and videos")
                    .font(.system(.subheadline, design: .rounded).monospacedDigit())
            } else {
                Text("Starting…")
                    .font(.system(.title3, design: .rounded))
            }
            if let throughput {
                VStack(spacing: 2) {
                    if let remaining = throughput.remainingText {
                        Text(remaining)
                            .font(.system(.footnote, design: .rounded))
                    }
                    Text(throughput.rateText)
                        .font(.system(.caption2, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.top, 4)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, Self.ringWidth * 2.5)
    }
}
