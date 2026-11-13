import Foundation
import Vision

/// Unarchives stored feature prints once and answers distances between them
/// for `DuplicateVerifier`. Built and used on one background task.
final class FeaturePrintDistances {
    private var observations: [String: VNFeaturePrintObservation] = [:]

    init(_ archived: [String: Data]) {
        for (assetId, data) in archived {
            if let observation = try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data) {
                observations[assetId] = observation
            }
        }
    }

    func distance(_ a: String, _ b: String) -> Float? {
        guard let left = observations[a], let right = observations[b] else { return nil }
        var result: Float = 0
        guard (try? left.computeDistance(&result, to: right)) != nil else { return nil }
        return result
    }
}
