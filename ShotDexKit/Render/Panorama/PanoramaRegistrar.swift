import Foundation

/// Why a set of frames could not be made into a panorama.
public enum PanoramaRegistrationError: Error, Equatable, Sendable {
    /// Fewer than two usable frames were handed over.
    case needsTwoImages
    /// No two frames overlap at all. The screen turns this into the sentence
    /// about frames needing to overlap by about a third (FS-14.01 §2).
    case noOverlappingFrames
}

/// What registration found, including what it could not place.
public struct PanoramaRegistration: Sendable {
    public var solution: PanoramaCameraSolution
    /// Pairs that were found to overlap, kept for the stages that need the
    /// matched points again.
    public var pairs: [PanoramaPairObservation]
    /// How many pairs were actually compared. Lower than n(n−1)/2 once the
    /// candidate filter is in play, and worth reporting because that filter is
    /// the difference between a 120-frame set taking seconds and minutes.
    public var comparedPairs: Int

    public init(
        solution: PanoramaCameraSolution,
        pairs: [PanoramaPairObservation],
        comparedPairs: Int
    ) {
        self.solution = solution
        self.pairs = pairs
        self.comparedPairs = comparedPairs
    }
}

/// Takes a pile of frames and works out which of them belong to one panorama
/// and where each was pointing.
///
/// This is the stage that must never lose a frame quietly: a frame that cannot
/// be joined comes back in `solution.unplaced`, and a set where nothing joins
/// anything throws rather than returning a panorama made of one picture
/// (FS-14.01 §2 — "không bao giờ lặng lẽ bỏ khung").
public enum PanoramaRegistrar {

    /// Above this many frames, comparing every pair stops being free:
    /// n(n−1)/2 is 45 comparisons at ten frames and 7 140 at a hundred and
    /// twenty. Up to here, compare everything — the spike measured ten frames
    /// at 0.3 s, and a filter that skips a real pair costs far more than the
    /// comparisons it saves.
    public static let exhaustiveFrameLimit = 12

    /// How alike two frames' thumbnails must be before they are worth
    /// comparing properly, once the set is too big to compare exhaustively.
    /// Generous on purpose: this is a filter against frames of a different
    /// scene, not a matcher.
    static let thumbnailDistanceLimit: Float = 0.35

    public static func register(
        images: [PanoramaImage],
        captureDates: [Date?]? = nil
    ) throws -> PanoramaRegistration {
        guard images.count >= 2 else { throw PanoramaRegistrationError.needsTwoImages }

        let features = images.map { PanoramaFeatureDetector.features(in: $0) }
        let thumbnails = images.map(thumbnail)
        let candidates = candidatePairs(
            count: images.count, thumbnails: thumbnails, captureDates: captureDates
        )

        var pairs: [PanoramaPairObservation] = []
        for (a, b) in candidates {
            let matches = PanoramaMatcher.matches(features[a], features[b])
            guard let fit = PanoramaMatcher.fit(matches: matches, a: features[a], b: features[b]) else {
                continue
            }
            let correspondences = fit.inliers.map { match in
                (
                    ax: Double(features[a][match.a].x),
                    ay: Double(features[a][match.a].y),
                    bx: Double(features[b][match.b].x),
                    by: Double(features[b][match.b].y)
                )
            }
            pairs.append(
                PanoramaPairObservation(
                    a: a, b: b, homography: fit.homography, correspondences: correspondences
                )
            )
        }
        guard !pairs.isEmpty else { throw PanoramaRegistrationError.noOverlappingFrames }

        guard let solution = PanoramaCameraSolver.solve(
            frameCount: images.count,
            imageWidth: images[0].width,
            imageHeight: images[0].height,
            pairs: pairs
        ) else {
            throw PanoramaRegistrationError.noOverlappingFrames
        }
        return PanoramaRegistration(
            solution: solution, pairs: pairs, comparedPairs: candidates.count
        )
    }

    // MARK: Candidate pairs

    /// Which pairs are worth the full comparison.
    ///
    /// Two signals, both cheap, and deliberately only used above
    /// `exhaustiveFrameLimit`: frames shot minutes apart are rarely part of one
    /// sweep, and frames whose 8×8 thumbnails look nothing alike are rarely of
    /// the same wall. Either one alone would be too eager — a panorama shot
    /// slowly is still one panorama, and a sweep across a plain sky has frames
    /// that all look the same — so a pair survives if it passes **either**.
    static func candidatePairs(
        count: Int,
        thumbnails: [[Float]],
        captureDates: [Date?]?
    ) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        let exhaustive = count <= exhaustiveFrameLimit
        for a in 0..<count {
            for b in (a + 1)..<count {
                guard !exhaustive else {
                    pairs.append((a, b))
                    continue
                }
                if looksRelated(thumbnails[a], thumbnails[b]) || shotTogether(captureDates, a, b) {
                    pairs.append((a, b))
                }
            }
        }
        return pairs
    }

    /// An 8×8 grey thumbnail, which is enough to say "these are not pictures of
    /// the same thing" and nothing more.
    static func thumbnail(of image: PanoramaImage) -> [Float] {
        let side = 8
        var out = [Float](repeating: 0, count: side * side)
        let cellWidth = max(1, image.width / side)
        let cellHeight = max(1, image.height / side)
        for row in 0..<side {
            for column in 0..<side {
                var sum: Float = 0
                var samples = 0
                let yStart = row * cellHeight
                let xStart = column * cellWidth
                for y in yStart..<min(image.height, yStart + cellHeight) {
                    for x in xStart..<min(image.width, xStart + cellWidth) {
                        sum += image[x, y]
                        samples += 1
                    }
                }
                out[row * side + column] = samples > 0 ? sum / Float(samples) : 0
            }
        }
        return out
    }

    static func looksRelated(_ a: [Float], _ b: [Float]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return true }
        var total: Float = 0
        for index in a.indices { total += abs(a[index] - b[index]) }
        return total / Float(a.count) <= thumbnailDistanceLimit
    }

    /// Frames from one sweep are seconds apart. Two minutes is loose enough to
    /// cover a careful photographer changing their footing between frames.
    static func shotTogether(_ dates: [Date?]?, _ a: Int, _ b: Int) -> Bool {
        guard let dates, a < dates.count, b < dates.count,
              let first = dates[a], let second = dates[b]
        else { return false }
        return abs(first.timeIntervalSince(second)) <= 120
    }
}
