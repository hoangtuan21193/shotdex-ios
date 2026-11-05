import Foundation

/// FS-19.08 §6f: a Live Photo on a server is two files side by side —
/// `IMG_1234.HEIC` and `IMG_1234.MOV`, one name in one folder. Matched a
/// file at a time, its halves could part: a still moved without its motion,
/// a motion filed beside another photo's still. Here they are held together:
/// Same only as a pair, the motion right after its still, one name and one
/// folder in the destination.
enum CommonPhotosLive {
    static let stillExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg"]
    static let motionExtensions: Set<String> = ["mov"]

    static func isStill(_ name: String) -> Bool { stillExtensions.contains((name as NSString).pathExtension.lowercased()) }
    static func isMotion(_ name: String) -> Bool { motionExtensions.contains((name as NSString).pathExtension.lowercased()) }

    /// Each half of a Live Photo in the listing, mapped to the other half:
    /// one still and one motion of one name in one folder. A name with two
    /// stills (`IMG_1.JPG` and `IMG_1.HEIC`) is no Live Photo — which still
    /// owns the motion cannot be told.
    static func partners(in files: [[CommonPhotosFile]]) -> [CommonPhotosFile: CommonPhotosFile] {
        let byName = Dictionary(grouping: files.joined().filter { isStill($0.name) || isMotion($0.name) }) { file in
            "\(file.folder)/" + (file.relativePath as NSString).deletingPathExtension.precomposedStringWithCanonicalMapping.lowercased()
        }
        var out: [CommonPhotosFile: CommonPhotosFile] = [:]
        for group in byName.values {
            let stills = group.filter { isStill($0.name) }
            let motions = group.filter { isMotion($0.name) }
            guard stills.count == 1, motions.count == 1 else { continue }
            out[stills[0]] = motions[0]
            out[motions[0]] = stills[0]
        }
        return out
    }

    struct Result: Equatable, Sendable {
        /// The Same photos the run may take, each motion right after its still.
        var photos: [CommonPhoto]
        /// Halves of Live Photos whose other half is not Same beside them:
        /// left out, so no run parts a pair.
        var split: [CommonPhoto]
        /// A kept pair's still SHA-256 (or Quick key) → its motion's.
        var motionOf: [String: String]
    }

    /// The Same photos with Live Photos held together. A pair is kept when
    /// every copy of the still has its motion beside it, all those motions
    /// are one Same photo, and every copy of that photo has the still beside
    /// it; otherwise both halves are split off. Photos that are not Live keep
    /// their place.
    static func pair(_ photos: [CommonPhoto], files: [[CommonPhotosFile]]) -> Result {
        let partner = partners(in: files)
        var photoOf: [CommonPhotosFile: Int] = [:]
        for (index, photo) in photos.enumerated() {
            for file in photo.files.joined() { photoOf[file] = index }
        }
        /// The one photo every copy of `index` has its other half in; nil
        /// when a copy has none, or the halves are not one Same photo.
        func other(_ index: Int) -> Int? {
            var found: Int?
            for file in photos[index].files.joined() {
                guard let half = partner[file], let at = photoOf[half], at != index else { return nil }
                if let found, found != at { return nil }
                found = at
            }
            return found
        }
        var kept: [CommonPhoto] = []
        var split: [CommonPhoto] = []
        var motionOf: [String: String] = [:]
        var done = Set<Int>()
        for index in photos.indices where !done.contains(index) {
            let isLive = photos[index].files.joined().contains { partner[$0] != nil }
            guard isLive else {
                // A motion that is no pair (two stills share its name) never
                // sits right after a still of its name, where a run would
                // take the two for one Live Photo: it goes before it.
                if let last = kept.last, sharesName(motion: photos[index], still: last) {
                    kept.insert(photos[index], at: kept.count - 1)
                } else {
                    kept.append(photos[index])
                }
                continue
            }
            done.insert(index)
            guard let mate = other(index), other(mate) == index, !done.contains(mate) else {
                split.append(photos[index])
                // Its other half, when Same, cannot go alone either.
                if let half = photos[index].files.joined().lazy.compactMap({ partner[$0] }).compactMap({ photoOf[$0] }).first,
                   !done.contains(half) {
                    done.insert(half)
                    split.append(photos[half])
                }
                continue
            }
            done.insert(mate)
            let stillFirst = isStill(photos[index].files[0][0].name)
            let (still, motion) = stillFirst ? (photos[index], photos[mate]) : (photos[mate], photos[index])
            kept.append(still)
            kept.append(motion)
            motionOf[still.sha256] = motion.sha256
        }
        return Result(photos: kept, split: split, motionOf: motionOf)
    }

    /// A listing cut for an incremental scan (§6c), with the other half of
    /// every Live Photo half it kept: a half that is new is checked with
    /// its mate, never alone.
    static func keepingMates(_ cut: [[CommonPhotosFile]], from all: [[CommonPhotosFile]]) -> [[CommonPhotosFile]] {
        let partner = partners(in: all)
        return zip(cut, all).map { kept, folder in
            let keep = Set(kept).union(kept.compactMap { partner[$0] })
            return folder.filter(keep.contains)
        }
    }

    /// `kept` (photos cut from `paired.photos`) with each Live half's mate
    /// put back, in `paired`'s order: when one half is new, the pair goes.
    static func withMates(_ kept: [CommonPhoto], in paired: Result) -> [CommonPhoto] {
        let keys = Set(kept.map(\.sha256))
        let stillOf = Dictionary(paired.motionOf.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
        return paired.photos.filter { photo in
            keys.contains(photo.sha256)
                || paired.motionOf[photo.sha256].map(keys.contains) == true
                || stillOf[photo.sha256].map(keys.contains) == true
        }
    }

    /// The first free name for a Live Photo's still whose motion name — the
    /// same stem with `motionExtension` — is free too, so the pair keeps one
    /// name (`IMG_1 (2).HEIC` with `IMG_1 (2).MOV`).
    static func freeName(forStill name: String, motionExtension: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        var blocked = taken
        while true {
            let candidate = ServerUploadPath.nextFreeName(for: name, existing: blocked)
            if !taken.contains(motionName(for: candidate, motionExtension: motionExtension).lowercased()) { return candidate }
            blocked.insert(candidate.lowercased())
        }
    }

    private static func sharesName(motion: CommonPhoto, still: CommonPhoto) -> Bool {
        let a = still.files[0][0], b = motion.files[0][0]
        return isStill(a.name) && isMotion(b.name) && a.folder == b.folder
            && (a.relativePath as NSString).deletingPathExtension.lowercased() == (b.relativePath as NSString).deletingPathExtension.lowercased()
    }

    /// The motion's name beside a still named `still`.
    static func motionName(for still: String, motionExtension: String) -> String {
        (still as NSString).deletingPathExtension + "." + motionExtension
    }

    /// Where the motion is filed beside a still filed at `stillPath`: the
    /// still's folder and name, the motion's own extension.
    static func motionPath(besideStill stillPath: String, motionExtension: String) -> String {
        let folder = ServerUploadPath.parent(of: stillPath)
        return ServerUploadPath.join(folder, motionName(for: ServerUploadPath.lastComponent(of: stillPath), motionExtension: motionExtension))
    }
}
