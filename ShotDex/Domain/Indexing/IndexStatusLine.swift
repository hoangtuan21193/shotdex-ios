import Foundation

/// What the Mac says about the index — Settings › Sources › Index and the
/// sidebar foot (FS-18.04 §3, AC-70, AC-71): how far a run is, or what the
/// finished index holds and when it last ran.
enum IndexStatusLine {
    enum State: Equatable {
        /// A run started but has not counted its work yet (listing, change
        /// history): it is running, not up to date.
        case preparing
        case indexing(processed: Int, total: Int)
        case upToDate(lastIndexed: Date?)
    }

    /// Rows whose read has finished — never the placeholders a run writes
    /// first (`MetadataStore.rowCount()` is the denominator, not this).
    struct Counts: Equatable {
        var photos: Int
        var videos: Int
        /// Bytes of every read item whose size the index knows; 0 when none does.
        var bytes: Int64 = 0

        var isEmpty: Bool { photos + videos == 0 }
    }

    /// `Indexing 12,400 of 55,231`, `54,027 photos · 1,204 videos`, or
    /// `Not indexed yet` for a library nothing has read.
    static func title(_ state: State, counts: Counts) -> String {
        switch state {
        case .preparing:
            String(localized: "Preparing to index…", comment: "Mac index status: a run is counting its work")
        case .indexing(let processed, let total):
            String(localized: "Indexing \(processed, format: .number) of \(total, format: .number)",
                   comment: "Mac index status: a run is going; processed and total items")
        case .upToDate(let lastIndexed):
            counts.isEmpty && lastIndexed == nil
                ? String(localized: "Not indexed yet", comment: "Mac index status: nothing has been read")
                : countsLine(counts)
        }
    }

    /// Under the title: what has been read so far while a run goes, else size
    /// and when the last run ended. Nil when there is nothing true to say.
    static func detail(_ state: State, counts: Counts, now: Date = Date()) -> String? {
        switch state {
        case .preparing, .indexing:
            guard !counts.isEmpty else { return nil }
            return String(localized: "\(countsLine(counts)) read so far",
                          comment: "Mac index status: under a running index, what is already read, e.g. 54,027 photos · 1,204 videos read so far")
        case .upToDate(let lastIndexed):
            guard let lastIndexed else { return nil }
            var parts: [String] = []
            if counts.bytes > 0 {
                parts.append(String(localized: "\(counts.bytes.formatted(.byteCount(style: .file))) of originals",
                                    comment: "Mac index status: summed file size of the indexed photos and videos"))
            }
            parts.append(String(localized: "up to date", comment: "Mac index status: nothing left to read, mid-sentence"))
            parts.append(indexedAgo(lastIndexed, now: now))
            return parts.joined(separator: " · ")
        }
    }

    /// 0…1 while a run goes and its total is known; nil otherwise (no bar,
    /// or an indeterminate one while preparing).
    static func fraction(_ state: State) -> Double? {
        guard case .indexing(let processed, let total) = state, total > 0 else { return nil }
        return min(1, Double(processed) / Double(total))
    }

    static func indexedAgo(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else {
            return String(localized: "indexed just now", comment: "Mac index status: the last run ended under a minute ago")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let ago = formatter.localizedString(for: date, relativeTo: now)
        return String(localized: "indexed \(ago)", comment: "Mac index status: when the last run ended, e.g. indexed 2 minutes ago")
    }

    /// `54,027 photos · 1,204 videos`; `1 photo`; videos only when there are some.
    static func countsLine(_ counts: Counts) -> String {
        var parts = [counts.photos == 1
            ? String(localized: "1 photo", comment: "Mac index status: one indexed photo")
            : String(localized: "\(counts.photos, format: .number) photos", comment: "Mac index status: indexed photos")]
        if counts.videos > 0 {
            parts.append(counts.videos == 1
                ? String(localized: "1 video", comment: "Mac index status: one indexed video")
                : String(localized: "\(counts.videos, format: .number) videos", comment: "Mac index status: indexed videos"))
        }
        return parts.joined(separator: " · ")
    }
}
