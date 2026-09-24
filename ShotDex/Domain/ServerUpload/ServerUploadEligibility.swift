import Foundation

/// Which photos the "Delete from iPhone" offer may include (FS-15.02 §7).
///
/// Deleting an asset deletes **every** file it holds, so an asset qualifies
/// only when each of its originals is verified on some server — not just the
/// files this batch sent. At Only RAW, a RAW+JPEG pair whose JPEG never went
/// up stays on the phone. Edited renders do not count: they can be made
/// again from the originals.
enum ServerUploadEligibility {
    struct Verdict: Equatable, Sendable {
        /// Asset ids safe to offer for deletion, in the order asked.
        var deletable: [String] = []
        /// Asset id → the original files still missing from every server.
        var missing: [String: [String]] = [:]
    }

    /// - Parameters:
    ///   - assets: each asset's files (any role; only originals are checked).
    ///   - uploadedKeys: per asset, the file keys that have a history row.
    static func evaluate(
        assets: [(assetId: String, files: [AssetUploadFile])],
        uploadedKeys: [String: Set<String>]
    ) -> Verdict {
        var verdict = Verdict()
        for asset in assets {
            let originals = asset.files.filter { $0.role == .original }
            guard !originals.isEmpty else { continue }
            let onServer = uploadedKeys[asset.assetId] ?? []
            let missing = originals.filter { !onServer.contains($0.key) }.map(\.filename)
            if missing.isEmpty {
                verdict.deletable.append(asset.assetId)
            } else if missing.count < originals.count {
                // Part of it is up: say which part is not. An asset with
                // nothing on a server is not "blocked", it just wasn't sent.
                verdict.missing[asset.assetId] = missing
            }
        }
        return verdict
    }
}
