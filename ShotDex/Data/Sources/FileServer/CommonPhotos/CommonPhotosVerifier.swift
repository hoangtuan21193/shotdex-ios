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
/// bytes than listed, a cached hash with no write time to vouch for it. A
/// photo whose hashes all came from the cache is hashed once more.
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
    /// earlier for the same path, size and write time (`copy_files`); a file
    /// listed with no write time has nothing to vouch for its hash, so its
    /// entry is ignored. `found` hears each size group's Same photos as they
    /// are decided; `progress` hears after every group and while a big file
    /// hashes. A server that went away stops the scan.
    func verify(_ preview: CommonPhotosMatcher.Preview, folders: [String],
                knownHashes: [CommonPhotosFile: String] = [:],
                found: @Sendable ([CommonPhoto]) -> Void = { _ in },
                progress: @escaping @Sendable (Progress) -> Void = { _ in }) async throws -> [CommonPhoto] {
        let holdsLikely = { (group: CommonPhotosMatcher.SizeGroup) in group.files.joined().contains(where: preview.likely.contains) }
        let groups = preview.groups.filter(holdsLikely) + preview.groups.filter { !holdsLikely($0) }
        var state = Progress(totalFiles: preview.candidateCount, totalBytes: preview.candidateBytes)
        var photos: [CommonPhoto] = []
        for group in groups {
            try Task.checkCancellation()
            var samples: [CommonPhotosFile: String] = [:]
            for file in group.files.joined() {
                try Task.checkCancellation()
                samples[file] = try await skippingUnreadable { try await sample(file, folders: folders) }
            }
            state.unreadableCount += group.files.joined().count - samples.count
            let candidates = Self.flatten(CommonPhotosMatcher.shared(group.files, keys: samples), folderCount: group.files.count)

            var hashes: [CommonPhotosFile: String] = [:]
            var fresh: Set<CommonPhotosFile> = []
            if group.size <= Int64(Self.sampleLength) * 3 {
                // Read whole: the sample is the SHA-256.
                hashes = samples
                fresh = Set(samples.keys)
            } else if candidates.allSatisfy({ !$0.isEmpty }) {
                for file in candidates.joined() {
                    if file.modified != nil, let known = knownHashes[file] {
                        hashes[file] = known
                        continue
                    }
                    try Task.checkCancellation()
                    let hashed = try await skippingUnreadable { try await fullHash(file, folders: folders, state: state, progress: progress) }
                    if let hashed {
                        hashes[file] = hashed
                        fresh.insert(file)
                    } else {
                        state.unreadableCount += 1
                    }
                }
            }

            var groupPhotos: [CommonPhoto] = []
            for (sha256, files) in CommonPhotosMatcher.shared(candidates, keys: hashes).sorted(by: { $0.key < $1.key }) {
                // Nothing read this time vouches for these bytes: read one.
                if !files.joined().contains(where: fresh.contains) {
                    let check = try await skippingUnreadable { try await fullHash(files[0][0], folders: folders, state: state, progress: progress) }
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
        if total > 0, total != file.size { throw RemoteFileError.other("changed since listing") }
        return sha256
    }

    /// The value, or nil when this one file cannot be read (gone since the
    /// listing, no permission, read back other than listed); failures every
    /// later file would meet too are thrown.
    private func skippingUnreadable(_ work: () async throws -> String) async throws -> String? {
        do {
            return try await work()
        } catch let error as RemoteFileError where !error.stopsBatch {
            return nil
        }
    }

    private static func flatten(_ byKey: [String: [[CommonPhotosFile]]], folderCount: Int) -> [[CommonPhotosFile]] {
        byKey.values.reduce(into: Array(repeating: [CommonPhotosFile](), count: folderCount)) { out, perFolder in
            for (index, files) in perFolder.enumerated() { out[index] += files }
        }
    }
}
