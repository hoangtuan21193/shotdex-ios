import Foundation

enum PhotoOutputFilename {
    static func make(
        original: String?,
        suffix: String,
        index: Int,
        format: PhotoOutputFormat,
        fallbackTimestamp: Int = Int(Date().timeIntervalSince1970)
    ) -> String {
        let fallback = "ShotDex-\(fallbackTimestamp)"
        let source = original.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        let base = (source as NSString).deletingPathExtension
        return "\(base)_\(suffix)_\(max(1, index)).\(format.fileExtension)"
    }
}

/// Allocates monotonically increasing filename suffixes per source asset and
/// operation. Counters are local to this ShotDex install, matching PhotoKit's
/// device-local asset identifiers and the edit-recipe recall policy.
@MainActor
final class PhotoOutputFilenameIndexStore {
    struct Reservation: Equatable {
        fileprivate let key: String
        let index: Int
    }

    private let defaults: UserDefaults
    private var counters: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.counters = defaults.dictionary(
            forKey: SettingsKeys.outputFilenameIndexes
        )?.reduce(into: [:]) { result, entry in
            guard let number = entry.value as? NSNumber else { return }
            result[entry.key] = max(0, number.intValue)
        } ?? [:]
    }

    func reserve(
        sourceAssetIdentifier: String,
        suffix: String
    ) -> Reservation {
        let key = "\(sourceAssetIdentifier)|\(suffix)"
        let index = (counters[key] ?? 0) + 1
        counters[key] = index
        persist()
        return Reservation(key: key, index: index)
    }

    /// Reclaims the last reservation when a save fails before Photos creates
    /// the asset. A later concurrent reservation is never moved backwards.
    func release(_ reservation: Reservation) {
        guard counters[reservation.key] == reservation.index else { return }
        if reservation.index == 1 {
            counters.removeValue(forKey: reservation.key)
        } else {
            counters[reservation.key] = reservation.index - 1
        }
        persist()
    }

    private func persist() {
        defaults.set(counters, forKey: SettingsKeys.outputFilenameIndexes)
    }
}
