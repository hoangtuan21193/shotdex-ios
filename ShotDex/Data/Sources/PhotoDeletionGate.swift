import Foundation
import GRDB

/// The one door a Photos deletion goes through (FS-19.07 §9). An item that
/// is on a server folder — every original file matched there — is deleted
/// only once the server is asked, just before, that each matched file is
/// still at its path with the same size and write time. A file not at its
/// path is looked for again by listing the source (the listing follows a
/// moved file by fast hash and size). Items that are not on a server pass
/// straight through. Only the Photos copy is ever deleted: the server copy
/// is not touched or hidden.
struct PhotoDeletionGate: Sendable {
    let database: AppDatabase
    /// A client for a connection, and the connection's root folder.
    let connect: @Sendable (_ connectionId: String) -> (client: any RemoteFileClient, root: String)?
    /// Lists the source again, so a moved file is found at its new path.
    let relist: @Sendable (_ sourceId: String) async -> Void

    /// What may be deleted now and what may not, by source name.
    struct Outcome: Equatable, Sendable {
        /// Not on any server folder: deleted as before.
        var plain: [String] = []
        /// On a server, and the server confirmed every file.
        var verified: [String] = []
        /// On a server when last checked; the file is gone or changed.
        var notOnServer: [String: [String]] = [:]
        /// The server did not answer.
        var unreachable: [String: [String]] = [:]

        /// Deleted without asking more.
        var deletable: [String] { plain + verified }
    }

    /// What a delete without its own alerts (every entry point but the
    /// three with `PhotoDeletionFlow`) reports for the photos it kept.
    struct Kept: LocalizedError, Equatable {
        let outcome: Outcome

        var errorDescription: String? {
            if let name = outcome.unreachable.keys.sorted().first {
                let count = outcome.unreachable.values.reduce(0) { $0 + $1.count }
                return count == 1
                    ? String(localized: "Can't reach \(name), so 1 photo wasn't deleted. ShotDex couldn't check that it's still there.",
                             comment: "Delete: a photo kept because its server did not answer")
                    : String(localized: "Can't reach \(name), so \(count) photos weren't deleted. ShotDex couldn't check that they're still there.",
                             comment: "Delete: photos kept because their server did not answer")
            }
            let name = outcome.notOnServer.keys.sorted().first ?? ""
            let count = outcome.notOnServer.values.reduce(0) { $0 + $1.count }
            return count == 1
                ? String(localized: "1 photo wasn't deleted — it's no longer on \(name).", comment: "Delete: a photo kept because its server copy is gone")
                : String(localized: "\(count) photos weren't deleted — they're no longer on \(name).", comment: "Delete: photos kept because their server copies are gone")
        }
    }

    func check(photoIds: [String]) async -> Outcome {
        var outcome = Outcome()
        let relying = (try? relyingSources(photoIds: photoIds)) ?? [:]
        outcome.plain = photoIds.filter { relying[$0] == nil }
        var sources: [String: (name: String, connectionId: String, photos: [String])] = [:]
        for (photo, list) in relying {
            for source in list {
                sources[source.id, default: (source.name, source.connectionId, [])].photos.append(photo)
            }
        }
        // A photo on two sources needs one to answer for it.
        var verdicts: [String: [Verdict]] = [:]
        for (sourceId, source) in sources.sorted(by: { $0.key < $1.key }) {
            let result = await verify(photos: source.photos, sourceId: sourceId, connectionId: source.connectionId)
            for (photo, verdict) in result { verdicts[photo, default: []].append(verdict.named(source.name)) }
        }
        for photo in photoIds where relying[photo] != nil {
            let list = verdicts[photo] ?? []
            if list.contains(where: { if case .same = $0 { true } else { false } }) {
                outcome.verified.append(photo)
            } else if let name = list.lazy.compactMap({ if case .unreachable(let n) = $0 { n } else { nil } }).first {
                outcome.unreachable[name, default: []].append(photo)
            } else {
                let name = list.lazy.compactMap({ if case .notThere(let n) = $0 { n } else { nil } }).first ?? ""
                outcome.notOnServer[name, default: []].append(photo)
            }
        }
        return outcome
    }

    private enum Verdict: Equatable {
        case same, notThere(String), unreachable(String)

        func named(_ name: String) -> Verdict {
            switch self {
            case .same: .same
            case .notThere: .notThere(name)
            case .unreachable: .unreachable(name)
            }
        }
    }

    /// Asks the source's server about every matched file of the photos;
    /// what is not where it was is looked for once more after a listing.
    private func verify(photos: [String], sourceId: String, connectionId: String) async -> [String: Verdict] {
        let unreachable = Dictionary(uniqueKeysWithValues: photos.map { ($0, Verdict.unreachable("")) })
        guard let (client, root) = connect(connectionId) else { return unreachable }
        let result: [String: Verdict]
        do {
            try await client.connect()
            var first = try await look(photos: photos, sourceId: sourceId, client: client, root: root)
            let missing = first.filter { $0.value == .notThere("") }.map(\.key)
            if !missing.isEmpty {
                await relist(sourceId)
                let stillOn = try presentPhotos(missing, sourceId: sourceId)
                let again = try await look(photos: Array(stillOn), sourceId: sourceId, client: client, root: root)
                for photo in missing { first[photo] = again[photo] ?? .notThere("") }
            }
            result = first
        } catch {
            result = unreachable
        }
        await client.disconnect()
        return result
    }

    /// One listing per folder: each required file of each photo needs one
    /// matched server file that is still the same.
    private func look(photos: [String], sourceId: String, client: any RemoteFileClient, root: String) async throws -> [String: Verdict] {
        let matches = try self.matches(photoIds: photos, sourceId: sourceId)
        var listings: [String: [String: RemoteEntry]] = [:]
        var out: [String: Verdict] = [:]
        for photo in photos {
            let files = matches[photo] ?? [:]
            var allSame = !files.isEmpty
            for (_, candidates) in files {
                var fileSame = false
                for candidate in candidates {
                    let full = ServerUploadPath.join(root, candidate.path)
                    let folder = ServerUploadPath.parent(of: full)
                    if listings[folder] == nil {
                        do {
                            let entries = try await client.entries(in: folder)
                            listings[folder] = Dictionary(entries.map { ($0.name, $0) }) { first, _ in first }
                        } catch let error as RemoteFileError where !error.stopsBatch {
                            listings[folder] = [:]
                        }
                    }
                    let entry = listings[folder]?[ServerUploadPath.lastComponent(of: full)]
                    if ServerCopyVerification.compare(size: candidate.size, modifiedAt: candidate.modifiedAt, entry: entry) == .same {
                        fileSame = true
                        break
                    }
                }
                if !fileSame { allSame = false; break }
            }
            out[photo] = allSame ? .same : .notThere("")
        }
        return out
    }

    // MARK: - Reading

    struct Source: Hashable, Sendable {
        var id: String
        var name: String
        var connectionId: String
    }

    /// The server sources each photo is on now (FS-19.07 §3).
    func relyingSources(photoIds: [String]) throws -> [String: [Source]] {
        let sources = try database.reader.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name, connectionId FROM sources WHERE kind = 'server' AND connectionId IS NOT NULL")
                .map { Source(id: $0["id"], name: $0["name"], connectionId: $0["connectionId"]) }
        }
        var out: [String: [Source]] = [:]
        for source in sources {
            for photo in try presentPhotos(photoIds, sourceId: source.id) { out[photo, default: []].append(source) }
        }
        return out
    }

    private func presentPhotos(_ photoIds: [String], sourceId: String) throws -> Set<String> {
        guard !photoIds.isEmpty else { return [] }
        let (present, values) = OnServerPresenceSQL.present(sourceId: sourceId, folder: nil)
        let ids = String(data: try JSONEncoder().encode(photoIds), encoding: .utf8)
        return try database.reader.read { db in
            Set(try String.fetchAll(db, sql: """
                SELECT assetId FROM photo_metadata WHERE assetId IN (SELECT value FROM json_each(?)) AND \(present)
                """, arguments: StatementArguments([ids] + values)))
        }
    }

    struct Match: Hashable, Sendable {
        var path: String
        var size: Int64?
        var modifiedAt: Int?
    }

    /// Per photo, per required Photos file: the server files of the source
    /// with its bytes, as the last listing saw them.
    private func matches(photoIds: [String], sourceId: String) throws -> [String: [String: [Match]]] {
        let ids = String(data: try JSONEncoder().encode(photoIds), encoding: .utf8)
        return try database.reader.read { db in
            var out: [String: [String: [Match]]] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT pc.photoId, f.fileKey, sf.size, sf.modifiedAt,
                       CASE sf.fileKey WHEN 'companion' THEN sc.pairedPath ELSE sc.relativePath END AS path
                FROM photo_copies pc
                JOIN copy_files f ON f.copyId = pc.id AND f.role IN \(OnServerPresenceSQL.roles) AND f.sha256 IS NOT NULL
                JOIN copy_files sf ON sf.sha256 = f.sha256
                JOIN photo_copies sc ON sc.id = sf.copyId AND sc.kind = 'server' AND sc.missingSince IS NULL AND sc.sourceId = ?
                WHERE pc.kind = 'photos' AND pc.photoId IN (SELECT value FROM json_each(?))
                ORDER BY sc.relativePathKey
                """, arguments: [sourceId, ids]) {
                guard let path: String = row["path"] else { continue }
                out[row["photoId"], default: [:]][row["fileKey"], default: []]
                    .append(Match(path: path, size: row["size"], modifiedAt: row["modifiedAt"]))
            }
            return out
        }
    }
}
