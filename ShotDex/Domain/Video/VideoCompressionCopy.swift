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

    /// The running headline: the file being worked on, counted from 1.
    static func running(_ completed: Int, of total: Int) -> String {
        total == 1
            ? String(localized: "Compressing", comment: "Compress Videos: running headline, one video")
            : String(localized: "Compressing \(min(completed + 1, total)) of \(total)", comment: "Compress Videos: running headline, the file being compressed and the total")
    }

    static func savedSoFar(_ value: Int64) -> String {
        String(localized: "Saved \(bytes(value)) so far", comment: "Compress Videos: running detail, space saved by the files already done")
    }

    static func timeLeft(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        return minutes <= 1
            ? String(localized: "About a minute left", comment: "Compress Videos: running detail, time left")
            : String(localized: "About \(minutes) min left", comment: "Compress Videos: running detail, time left in minutes")
    }

    /// The finished headline, the number the user came for.
    static func savedHeadline(_ value: Int64) -> String {
        String(localized: "Saved \(bytes(value))", comment: "Compress Videos summary: headline, total space saved")
    }

    static func doneDetail(done: Int, skipped: Int) -> String {
        let compressed = done == 1
            ? String(localized: "Compressed 1 video", comment: "Compress Videos summary detail, one video")
            : String(localized: "Compressed \(done) videos", comment: "Compress Videos summary detail")
        guard skipped > 0 else { return compressed }
        return compressed + " · " + String(localized: "\(skipped) already compact", comment: "Compress Videos summary detail: files left as they were")
    }

    static func progress(_ completed: Int, of total: Int) -> String {
        String(localized: "\(completed) of \(total) done", comment: "Compress Videos: batch counter")
    }

    static func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file))
    }

    static func name(_ quality: VideoCompressionQuality) -> String {
        switch quality {
        case .maximum: String(localized: "Maximum", comment: "Compress Videos quality level")
        case .high: String(localized: "High Quality", comment: "Compress Videos quality level")
        case .balanced: String(localized: "Balanced", comment: "Compress Videos quality level")
        case .smallest: String(localized: "Smallest", comment: "Compress Videos quality level")
        }
    }

    static func detail(_ quality: VideoCompressionQuality) -> String {
        switch quality {
        case .maximum: String(localized: "Visually identical, larger file", comment: "Compress Videos: Maximum description")
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

    // MARK: Compare (FS-24 §10)

    static let compareBeforeAfter = String(localized: "Compare Before and After", comment: "Compress Videos summary: open Compare Videos on the first compressed file")
    static let deleteOriginal = String(localized: "Delete Original", comment: "Compare Videos: move this video's original to Recently Deleted")
    static let compareHint = String(localized: "Pinch to zoom both · hold a video to see the other", comment: "Compare Videos: how to inspect the two videos")
    static let compareHintMac = String(localized: "Pinch or ⌘-scroll to zoom both · hold Option to see the other · Space play · ← → frame", comment: "Mac Compare Videos: how to inspect the two videos")
    static let compareKeys = String(localized: "Space play · ← → frame · ⌘← ⌘→ video", comment: "Compare Videos on iPad: keyboard shortcuts")
    static let summaryHint = String(localized: "Tap a video to compare it. Originals go to Recently Deleted.", comment: "Compress Videos summary: under the buttons")
    static let summaryHintMac = String(localized: "Double-click a video to compare it. Originals go to Recently Deleted.", comment: "Mac Compress Videos summary: under the buttons")
    static let play = String(localized: "Play", comment: "Compare Videos transport")
    static let pause = String(localized: "Pause", comment: "Compare Videos transport")
    static let previousFrame = String(localized: "Previous Frame", comment: "Compare Videos transport")
    static let nextFrame = String(localized: "Next Frame", comment: "Compare Videos transport")
    static let previousVideo = String(localized: "Previous Video", comment: "Compare Videos: step to the previous compressed file")
    static let nextVideo = String(localized: "Next Video", comment: "Compare Videos: step to the next compressed file")
    static let soundOn = String(localized: "Sound On", comment: "Compare Videos: unmute")
    static let soundOff = String(localized: "Sound Off", comment: "Compare Videos: mute")

    /// "Original · 1.2 GB · H.264".
    static func originalLabel(bytes value: Int64, codec: String?) -> String {
        if let codec {
            return String(localized: "Original · \(bytes(value)) · \(codec)", comment: "Compare Videos: pane A label, size and codec")
        }
        return String(localized: "Original · \(bytes(value))", comment: "Compare Videos: pane A label, size")
    }

    /// "Compressed · 498 MB · −58%".
    static func copyLabel(_ pair: VideoCompareRules.Pair) -> String {
        String(localized: "Compressed · \(bytes(pair.copyBytes)) · −\(percent(pair.reduction))", comment: "Compare Videos: pane B label, size and how much smaller")
    }

    /// "1.2 GB → 498 MB · −58%" — a summary row.
    static func result(_ pair: VideoCompareRules.Pair) -> String {
        String(localized: "\(bytes(pair.originalBytes)) → \(bytes(pair.copyBytes)) · −\(percent(pair.reduction))", comment: "Compress Videos summary row: size before, after, and how much smaller")
    }

    static func saved(_ value: Int64) -> String {
        String(localized: "Saved \(bytes(value))", comment: "Compare Videos: subtitle, space this file saved")
    }

    /// "Video 1 of 4".
    static func position(_ index: Int, of count: Int) -> String {
        String(localized: "Video \(index + 1) of \(count)", comment: "Compare Videos: which compressed file is shown")
    }

    /// The scrubber's VoiceOver value: "0:01, frame 42" — the frame is what
    /// ←/→ and the frame buttons move, and the seconds alone do not show it.
    static func scrubberValue(seconds: Double, frameRate: Double) -> String {
        let value = max(0, seconds) * frameRate
        let frame = value.isFinite ? Int(value.rounded()) : 0
        return String(localized: "\(time(seconds)), frame \(frame)", comment: "Compare Videos: scrubber value for VoiceOver, time and frame number")
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func time(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds.isFinite ? seconds : 0)).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
