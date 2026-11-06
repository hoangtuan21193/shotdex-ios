import Foundation
import os

/// Adds a keyword to, or takes one off, every selected photo (the Mac
/// inspector, FS-18.02 §2), and writes Get Info's caption and title (§8): photos in Photos through Photos itself
/// (`CaptionKeywordService`, FS-02.07 §4 — the mirror follows), file photos
/// into `photo_user_keyword` and on to their `.xmp` sidecars (FS-19.02 §5).
/// A photo with both kinds of copy gets both. Keywords are matched by case
/// (`caseKey`) as everywhere else: an add skips a photo that has the word in
/// another case, a remove takes every case off. Everything runs off the main
/// actor; the caller re-reads the selection when it returns.
struct MacKeywordEditor {
    let database: AppDatabase
    let captionKeywords: CaptionKeywordService?
    let sidecarQueue: SidecarWriteQueue
    let filterSuggestions: FilterSuggestionCache

    private static let log = Logger(subsystem: "com.hoangtuan.shotdex", category: "keywords")

    enum Outcome: Equatable {
        case done
        /// These many photos are in Photos and did not take the change:
        /// Photos cannot be written here (before macOS 27), it refused them
        /// (a shared library), or it no longer has them.
        case skipped(Int)
        case failed

        /// A failure outweighs photos skipped, which outweigh done.
        func combined(with other: Outcome) -> Outcome {
            switch (self, other) {
            case (.failed, _), (_, .failed): .failed
            case let (.skipped(a), .skipped(b)): .skipped(a + b)
            case (.skipped, .done): self
            case (.done, _): other
            }
        }
    }

    func add(_ keyword: String, to ids: [String]) async -> Outcome {
        let key = KeywordInput.caseKey(keyword)
        return await write(ids: ids, files: { store, files in try store.addKeyword(keyword, photoIds: files) }) { current in
            current.keywords.contains { KeywordInput.caseKey($0) == key } ? nil : CaptionKeywordChange(add: [keyword])
        }
    }

    func remove(_ keyword: String, from ids: [String]) async -> Outcome {
        let key = KeywordInput.caseKey(keyword)
        return await write(ids: ids, files: { store, files in try store.removeKeyword(keyword, photoIds: files) }) { current in
            // Photos removes by exact spelling: every spelling it holds goes.
            let spellings = current.keywords.filter { KeywordInput.caseKey($0) == key }
            return spellings.isEmpty ? nil : CaptionKeywordChange(remove: spellings)
        }
    }

    /// Get Info's caption: a file photo's own row (and sidecar), Photos'
    /// caption for a photo in Photos. Empty clears it.
    func setCaption(_ text: String, for id: String) async -> Outcome {
        let caption: CaptionKeywordChange.Caption = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .clear : .set(text)
        return await write(ids: [id], files: { store, files in try store.setCaption(text, photoIds: files) }) { current in
            current.caption == (caption == .clear ? nil : text) ? nil : CaptionKeywordChange(caption: caption)
        }
    }

    /// Creator and Copyright: ShotDex's own fields for every photo, sent on
    /// to the sidecar of a file photo (Photos has no such field).
    func setCreator(_ text: String, for id: String) async -> Outcome {
        await setUserText(id) { try $0.setCreator(text, photoIds: [id]) }
    }

    func setCopyright(_ text: String, for id: String) async -> Outcome {
        await setUserText(id) { try $0.setCopyright(text, photoIds: [id]) }
    }

    private func setUserText(_ id: String, _ write: @escaping @Sendable (PhotoUserMarksStore) throws -> Void) async -> Outcome {
        let store = PhotoUserMarksStore(database: database)
        do {
            try await Task.detached(priority: .userInitiated) { try write(store) }.value
            await sidecarQueue.schedule([id])
            return .done
        } catch {
            Self.log.error("user field write failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// A file photo's title (Photos keeps none ShotDex writes).
    func setTitle(_ text: String, for id: String) async -> Outcome {
        let store = PhotoUserMarksStore(database: database)
        do {
            try await Task.detached(priority: .userInitiated) { try store.setTitle(text, photoIds: [id]) }.value
            await sidecarQueue.schedule([id])
            return .done
        } catch {
            Self.log.error("title write failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// `change` turns a photo's keywords as Photos holds them into its own
    /// change, or nil when it needs none.
    private func write(ids: [String],
                       files: @escaping @Sendable (PhotoUserMarksStore, [String]) throws -> Void,
                       change: @escaping @Sendable (CaptionKeywords) -> CaptionKeywordChange?) async -> Outcome {
        let store = PhotoUserMarksStore(database: database)
        let kinds: (files: Set<String>, photos: Set<String>)
        do {
            kinds = try await Task.detached(priority: .userInitiated) { try store.copyKinds(ids: ids) }.value
        } catch {
            Self.log.error("keyword write: copy kinds failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
        // A photo with no copy row yet is a Photos asset the copy table has
        // not caught up with (`copyKinds`).
        let photos = ids.filter { kinds.photos.contains($0) || !kinds.files.contains($0) }
        let fileIds = ids.filter { kinds.files.contains($0) }
        var outcome = Outcome.done
        if !fileIds.isEmpty {
            do {
                try await Task.detached(priority: .userInitiated) { try files(store, fileIds) }.value
                await sidecarQueue.schedule(fileIds)
            } catch {
                Self.log.error("keyword write: file photos failed: \(error.localizedDescription, privacy: .public)")
                outcome = .failed
            }
        }
        if !photos.isEmpty {
            outcome = outcome.combined(with: await writePhotos(photos, change: change))
        }
        _ = await filterSuggestions.refreshKeywords()
        return outcome
    }

    private func writePhotos(_ ids: [String], change: @escaping @Sendable (CaptionKeywords) -> CaptionKeywordChange?) async -> Outcome {
        #if DEBUG
        // The demo has no Photos library: its keywords are only the mirror's rows.
        if MacDemoLibrary.isOn {
            let store = PhotoKeywordStore(database: database)
            do {
                try await Task.detached(priority: .userInitiated) {
                    let current = try store.values(ids: ids)
                    let changed = ids.reduce(into: [String: CaptionKeywords]()) { result, id in
                        let value = current[id] ?? .empty
                        if let change = change(value) { result[id] = change.applied(to: value) }
                    }
                    try store.replace(changed)
                }.value
                return .done
            } catch {
                return .failed
            }
        }
        #endif
        guard let captionKeywords else { return .skipped(ids.count) }
        // What Photos holds now, read live off the main actor; a photo it no
        // longer has is skipped (and said), not reported done.
        let current = await Task.detached(priority: .userInitiated) { captionKeywords.read(ids: ids) }.value
        let changes = current.reduce(into: [String: CaptionKeywordChange]()) { result, entry in
            if let change = change(entry.value) { result[entry.key] = change }
        }
        let missing = ids.count - current.count
        guard !changes.isEmpty else { return missing > 0 ? .skipped(missing) : .done }
        do {
            let result = try await captionKeywords.apply(changes)
            let skipped = result.refused.count + missing
            return skipped > 0 ? .skipped(skipped) : .done
        } catch {
            Self.log.error("keyword write: Photos refused the block: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }
}
