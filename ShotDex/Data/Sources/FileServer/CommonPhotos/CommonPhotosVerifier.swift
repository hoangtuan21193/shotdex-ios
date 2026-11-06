import CryptoKit
import Foundation
import os

/// Steps 4 and 5 of the common-photos scan (FS-19.08 §5): three 64 KB
/// samples drop most look-alikes, then the SHA-256 of the whole file decides
/// Same. Groups holding a Likely file go first, so what the user expects
/// turns Same soonest.
///
/// Same is what a Move deletes on, so every way a read can come back wrong
/// drops the file instead: a read shorter than asked, a hash over fewer
/// bytes than listed, a cached hash with no write time to vouch for it.
struct CommonPhotosVerifier {
    let client: RemoteFileClient

    /// One sample's length; a file no longer than three of them is read
    /// whole, and that read is its SHA-256.
    static let sampleLength = 64 * 1024

    /// Where the scan is, in the units the sheet counts (FS-19.08 §4, §7):
    /// photos of the first folder, since a common photo is there at least
    /// once.
    struct Progress: Equatable, Sendable {
        var checkedFiles = 0
        var totalFiles = 0
        var checkedBytes: Int64 = 0
        var totalBytes: Int64 = 0
        /// Photos found Same so far.
        var sameCount = 0
        /// Files dropped because they could not be read, or read back other
        /// than listed.
        var unreadableCount = 0

        var bytesLeft: Int64 { max(0, totalBytes - checkedBytes) }
    }

    /// The photos every folder holds. `knownHashes` are SHA-256s taken
    /// earlier for the same path, size and write time (`copy_files`, or an
    /// earlier scan, FS-19.08 §6c); a file listed with no write time has
    /// nothing to vouch for its hash, so its entry is ignored. They stand in
    /// for the first folder's copies only — unless `trustsCache`: then every
    /// copy's known hash stands and a group known throughout is not read at
    /// all. The sheet always trusts it, for a Copy and a Move alike (user
    /// 2026-11-06: one scan for both); a Move asks each copy again for its
    /// size and write time before it removes it.
    /// `hashed` hears every SHA-256 this scan worked out, group by group,
    /// for the next scan. `found` hears each size group's Same photos as
    /// they are decided; `progress` hears after every group and while a big
    /// file hashes. A server that went away stops the scan.
    ///
    /// `quick` (Copy only, FS-19.08 §6e): a first-folder copy and a copy in
    /// each other folder at the same path — case and Unicode form aside —
    /// whose samples match are Same without a SHA-256; every other copy goes
    /// the long way, so a photo filed under another day is still found.
    /// `fullSizes` are sizes never settled quick (a photo left out there).
    func verify(_ preview: CommonPhotosMatcher.Preview, folders: [String],
                knownHashes: [CommonPhotosFile: String] = [:],
                trustsCache: Bool = false,
                quick: Bool = false,
                fullSizes: Set<Int64> = [],
                unreadable: @Sendable (CommonPhotosFile, String) -> Void = { _, _ in },
                hashed: @Sendable ([CommonPhotosFile: String]) -> Void = { _ in },
                found: @Sendable ([CommonPhoto]) -> Void = { _ in },
                progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> [CommonPhoto] {
        let groups = Self.order(preview)
        var state = Progress(totalFiles: preview.candidateCount, totalBytes: preview.candidateBytes)
        var photos: [CommonPhoto] = []
        for group in groups {
            try Task.checkCancellation()
            let known = group.files.joined().compactMap { file in
                file.modified == nil ? nil : knownHashes[file].map { (file, $0) }
            }
            if trustsCache, known.count == group.files.joined().count {
                // Every copy known, nothing changed since: no byte read.
                let hashes = Dictionary(known, uniquingKeysWith: { first, _ in first })
                let groupPhotos = CommonPhotosMatcher.shared(group.files, keys: hashes).sorted(by: { $0.key < $1.key })
                    .map { CommonPhoto(sha256: $0.key, size: group.size, files: $0.value) }
                photos += groupPhotos
                state.checkedFiles += group.files[0].count
                state.checkedBytes += group.size * Int64(group.files[0].count)
                state.sameCount = photos.count
                if !groupPhotos.isEmpty { found(groupPhotos) }
                progress(state)
                continue
            }
            var samples: [CommonPhotosFile: String] = [:]
            for file in group.files.joined() {
                try Task.checkCancellation()
                samples[file] = try await skippingUnreadable(file, unreadable) { try await sample(file, folders: folders) }
            }
            state.unreadableCount += group.files.joined().count - samples.count
            var candidates = Self.flatten(CommonPhotosMatcher.shared(group.files, keys: samples), folderCount: group.files.count)

            // Quick Check: same path and samples in every folder — Same now.
            var quickPhotos: [CommonPhoto] = []
            // A size the set has a photo left out at goes the long way: the
            // Left Out list knows photos by their SHA-256.
            if quick, !fullSizes.contains(group.size), group.size > Int64(Self.sampleLength) * 3, candidates.count > 1 {
                (quickPhotos, candidates) = Self.quickPairs(candidates, samples: samples, size: group.size)
            }

            var hashes: [CommonPhotosFile: String] = [:]
            var fresh: Set<CommonPhotosFile> = []
            if group.size <= Int64(Self.sampleLength) * 3 {
                // Read whole: the sample is the SHA-256.
                hashes = samples
                fresh = Set(samples.keys)
            } else if candidates.allSatisfy({ !$0.isEmpty }) {
                for file in candidates.joined() {
                    // A cached hash stands in only for the first folder's
                    // copy — the one a Move renames, never deletes — unless
                    // the scan trusts the cache.
                    if file.folder == 0 || trustsCache, file.modified != nil, let known = knownHashes[file] {
                        hashes[file] = known
                        continue
                    }
                    try Task.checkCancellation()
                    let hashed = try await skippingUnreadable(file, unreadable) { try await fullHash(file, folders: folders, state: state, progress: progress) }
                    if let hashed {
                        hashes[file] = hashed
                        fresh.insert(file)
                    } else {
                        state.unreadableCount += 1
                    }
                }
            }

            let worked = hashes.filter { fresh.contains($0.key) }
            if !worked.isEmpty { hashed(worked) }
            var groupPhotos: [CommonPhoto] = quickPhotos
            for (sha256, files) in CommonPhotosMatcher.shared(candidates, keys: hashes).sorted(by: { $0.key < $1.key }) {
                // Nothing read this time vouches for these bytes: read one
                // — not when the scan trusts the cache.
                if !trustsCache, !files.joined().contains(where: fresh.contains) {
                    let check = try await skippingUnreadable(files[0][0], unreadable) { try await fullHash(files[0][0], folders: folders, state: state, progress: progress) }
                    guard check == sha256 else { continue }
                }
                groupPhotos.append(CommonPhoto(sha256: sha256, size: group.size, files: files))
            }
            photos += groupPhotos
            state.checkedFiles += group.files[0].count
            state.checkedBytes += group.size * Int64(group.files[0].count)
            state.sameCount = photos.count
            if !groupPhotos.isEmpty { found(groupPhotos) }
            progress(state)
        }
        return photos
    }

    /// SHA-256 over the start, middle and end of the file — or the whole
    /// file when it is that short, which is then its real SHA-256. A read
    /// shorter than asked means the file is not what was listed.
    func sample(_ file: CommonPhotosFile, folders: [String]) async throws -> String {
        let path = ServerUploadPath.join(folders[file.folder], file.relativePath)
        let length = Int64(Self.sampleLength)
        let reads = file.size <= length * 3
            ? [(offset: Int64(0), length: file.size)]
            : [0, file.size / 2 - length / 2, file.size - length].map { (offset: $0, length: length) }
        var hasher = SHA256()
        for read in reads {
            let data = try await client.readRange(path, offset: read.offset, length: Int(read.length))
            guard Int64(data.count) == read.length else { throw RemoteFileError.other("changed since listing") }
            hasher.update(data: data)
        }
        return FileChecksum.hex(hasher.finalize())
    }

    /// The whole file's SHA-256, refused when the bytes hashed are not the
    /// bytes listed (a file rewritten since, a read cut short).
    private func fullHash(_ file: CommonPhotosFile, folders: [String], state: Progress,
                          progress: @escaping @Sendable (Progress) -> Void) async throws -> String {
        let path = ServerUploadPath.join(folders[file.folder], file.relativePath)
        let hashed = OSAllocatedUnfairLock(initialState: Int64(0))
        let firstFolder = file.folder == 0
        let sha256 = try await client.sha256(of: path) { bytes in
            hashed.withLock { $0 = bytes }
            // Bytes left count the first folder only, as the sheet does.
            guard firstFolder else { return }
            var moving = state
            moving.checkedBytes += bytes
            progress(moving)
        }
        let total = hashed.withLock { $0 }
        // A file that comes back with no bytes, or other than listed, has
        // changed (a client that reports nothing hashed reports 0).
        if total != file.size, total > 0 || file.size > 0 { throw RemoteFileError.other("changed since listing") }
        return sha256
    }

    /// The size groups in the order they are checked: those holding a
    /// Likely file first. The sheet counts a stopped scan's Not checked
    /// files in the same order.
    static func order(_ preview: CommonPhotosMatcher.Preview) -> [CommonPhotosMatcher.SizeGroup] {
        let holdsLikely = { (group: CommonPhotosMatcher.SizeGroup) in group.files.joined().contains(where: preview.likely.contains) }
        return preview.groups.filter(holdsLikely) + preview.groups.filter { !holdsLikely($0) }
    }

    /// The value, or nil when this one file cannot be read (gone since the
    /// listing, no permission, read back other than listed) — told to
    /// `unreadable` with the server's words; failures every later file
    /// would meet too are thrown.
    private func skippingUnreadable(_ file: CommonPhotosFile, _ unreadable: @Sendable (CommonPhotosFile, String) -> Void,
                                    _ work: () async throws -> String) async throws -> String? {
        do {
            return try await work()
        } catch let error as RemoteFileError where !error.stopsBatch {
            unreadable(file, error.errorDescription ?? error.localizedDescription)
            return nil
        }
    }

    /// Splits `candidates` into the photos Quick Check settles — a
    /// first-folder copy with a copy at the same path and with the same
    /// samples in every other folder — and what is left to hash. A sample
    /// that more than one file of a folder holds (the same photo twice in
    /// one folder) is left to the hash, which groups every copy into one
    /// photo instead of one per pair.
    static func quickPairs(_ candidates: [[CommonPhotosFile]], samples: [CommonPhotosFile: String],
                           size: Int64) -> (photos: [CommonPhoto], rest: [[CommonPhotosFile]]) {
        let pathKey = { (file: CommonPhotosFile) in file.relativePath.precomposedStringWithCanonicalMapping.lowercased() }
        // Per folder: how many files hold each sample, and the file at each (path, sample).
        let perFolder = candidates.map { files -> (counts: [String: Int], byPath: [String: CommonPhotosFile]) in
            var counts: [String: Int] = [:]
            var byPath: [String: CommonPhotosFile] = [:]
            for file in files {
                guard let sample = samples[file] else { continue }
                counts[sample, default: 0] += 1
                byPath[pathKey(file) + "\u{0}" + sample] = file
            }
            return (counts, byPath)
        }
        var taken = Set<CommonPhotosFile>()
        var photos: [CommonPhoto] = []
        for first in candidates[0] {
            guard let sample = samples[first], perFolder.allSatisfy({ $0.counts[sample] == 1 }) else { continue }
            let key = pathKey(first) + "\u{0}" + sample
            let copies = perFolder.compactMap { $0.byPath[key] }
            guard copies.count == candidates.count else { continue }
            photos.append(CommonPhoto(sha256: CommonPhoto.quickKey(samples: sample, firstCopy: first), size: size, files: copies.map { [$0] }))
            taken.formUnion(copies)
        }
        return (photos, candidates.map { $0.filter { !taken.contains($0) } })
    }

    private static func flatten(_ byKey: [String: [[CommonPhotosFile]]], folderCount: Int) -> [[CommonPhotosFile]] {
        byKey.values.reduce(into: Array(repeating: [CommonPhotosFile](), count: folderCount)) { out, perFolder in
            for (index, files) in perFolder.enumerated() { out[index] += files }
        }
    }
}
