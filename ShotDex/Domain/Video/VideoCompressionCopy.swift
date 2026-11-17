import Foundation

/// Every string the Compress Videos screen shows, on iOS and the Mac (FS-24).
enum VideoCompressionCopy {
    static let command = String(localized: "Compress Videos", comment: "Selection menu command: compress the selected videos to HEVC")
    static let compress = String(localized: "Compress", comment: "Compress Videos: primary button")
    static let stop = String(localized: "Stop", comment: "Compress Videos: stop the running batch")
    static let done = String(localized: "Done", comment: "Compress Videos: close the summary")
    static let deleteOriginals = String(localized: "Delete Originals", comment: "Compress Videos summary: move the originals of compressed videos to Recently Deleted")
    static let originalsDeleted = String(localized: "Originals moved to Recently Deleted", comment: "Compress Videos summary: after Delete Originals")
    static let quality = String(localized: "Quality", comment: "Compress Videos: section label")
    static let size = String(localized: "Size", comment: "Compress Videos: section label (resolution cap)")
    static let note = String(localized: "HDR stays HDR. Originals are kept until you delete them.", comment: "Compress Videos: footnote under the choices")
    static let preparing = String(localized: "Reading videos…", comment: "Compress Videos: loading sizes before the estimate")

    static func title(_ count: Int) -> String {
        count == 1
            ? String(localized: "Compress Video", comment: "Compress Videos: title for one video")
            : String(localized: "Compress \(count) Videos", comment: "Compress Videos: title for several videos")
    }

    static func leftOut(_ photos: Int) -> String {
        photos == 1
            ? String(localized: "1 photo in the selection is left out", comment: "Compress Videos: the selection also held one photo, which this tool skips")
            : String(localized: "\(photos) photos in the selection are left out", comment: "Compress Videos: the selection also held photos, which this tool skips")
    }

    static func estimate(before: Int64, after: Int64) -> String {
        let saved = max(before - after, 0)
        return String(localized: "\(bytes(before)) → about \(bytes(after)) · saves about \(bytes(saved))", comment: "Compress Videos: estimate line, total before → estimated after and the space saved")
    }

    static func summary(done: Int, saved: Int64) -> String {
        done == 1
            ? String(localized: "Compressed 1 video · saved \(bytes(saved))", comment: "Compress Videos summary headline, one video")
            : String(localized: "Compressed \(done) videos · saved \(bytes(saved))", comment: "Compress Videos summary headline")
    }

    static func progress(_ completed: Int, of total: Int) -> String {
        String(localized: "\(completed) of \(total) done", comment: "Compress Videos: batch counter")
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    static func name(_ quality: VideoCompressionQuality) -> String {
        switch quality {
        case .high: String(localized: "High Quality", comment: "Compress Videos quality level")
        case .balanced: String(localized: "Balanced", comment: "Compress Videos quality level")
        case .smallest: String(localized: "Smallest", comment: "Compress Videos quality level")
        }
    }

    static func detail(_ quality: VideoCompressionQuality) -> String {
        switch quality {
        case .high: String(localized: "Looks like the original", comment: "Compress Videos: High Quality description")
        case .balanced: String(localized: "Smaller, hard to tell apart", comment: "Compress Videos: Balanced description")
        case .smallest: String(localized: "Smallest file, some softening", comment: "Compress Videos: Smallest description")
        }
    }

    static func name(_ size: VideoCompressionSize) -> String {
        switch size {
        case .original: String(localized: "Original", comment: "Compress Videos size: keep the resolution")
        case .uhd4K: String(localized: "4K", comment: "Compress Videos size: cap at 4K")
        case .fullHD: String(localized: "1080p", comment: "Compress Videos size: cap at 1080p")
        }
    }

    static func state(_ state: VideoCompressionBatch.ItemState) -> String {
        switch state {
        case .waiting: String(localized: "Waiting", comment: "Compress Videos row state")
        case .downloading(let value): String(localized: "Downloading \(Int(value * 100))%", comment: "Compress Videos row state: iCloud download")
        case .encoding(let value): String(localized: "Compressing \(Int(value * 100))%", comment: "Compress Videos row state")
        case .saving: String(localized: "Saving…", comment: "Compress Videos row state")
        case .done(let saved): String(localized: "Saved \(bytes(saved))", comment: "Compress Videos row state: finished, with space saved")
        case .skipped(let reason): reason
        case .failed(let message): message
        case .stopped: String(localized: "Stopped", comment: "Compress Videos row state")
        }
    }
}
