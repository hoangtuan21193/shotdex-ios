import Foundation

/// Where one batch's preparation of originals stands (FS-02.06 §5), and every
/// number and sentence the screens show for it. Pure: the run that drives it
/// lives in `OriginalPreparation`, the clock is whoever asks.
struct OriginalPreparationState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Asking each photo, with the network off, whether its original is
        /// already here; then checking the room for the rest.
        case checking
        case downloading
        /// Some downloads failed: the user picks Continue, Retry or Cancel.
        case failed
        /// The batch needs more room than the device has (step 2, or the
        /// disk filled up mid-download).
        case notEnoughSpace(needed: Int64, free: Int64)
        /// Everything that is going to arrive is here.
        case ready
        case cancelled
    }

    /// One photo of the batch that has to come down from iCloud.
    struct Download: Equatable, Sendable {
        let id: String
        let filename: String
        /// Bytes, when the index or PhotoKit knew.
        var byteCount: Int64?
        var fraction: Double = 0
        var isFinished = false
        var hasFailed = false
    }

    var phase: Phase = .checking
    /// Every photo of the batch, the ones already on the device included.
    var batchCount: Int
    /// Only the photos that have to be downloaded, in batch order. Photos
    /// already on the device are not counted (step 1).
    var downloads: [Download] = []

    init(batchCount: Int) {
        self.batchCount = batchCount
    }

    // MARK: Numbers

    /// Photos that have to come down.
    var downloadCount: Int { downloads.count }

    var finishedCount: Int { downloads.filter(\.isFinished).count }

    var failedNames: [String] { downloads.filter(\.hasFailed).map(\.filename) }

    /// The one the "k of n" names: the first photo not finished yet, counted
    /// from one, and never past n.
    var currentOrdinal: Int { min(downloadCount, finishedCount + 1) }

    /// The average per photo: a finished photo counts 1, one on its way the
    /// part that has arrived (step 3). A failed one counts what it got to.
    var fraction: Double {
        guard !downloads.isEmpty else { return 1 }
        let sum = downloads.reduce(0.0) { $0 + ($1.isFinished ? 1 : min(1, max(0, $1.fraction))) }
        return sum / Double(downloads.count)
    }

    var percent: Int { Int((fraction * 100).rounded(.down)) }

    /// The size of what is being downloaded, when any of it is known.
    var totalBytes: Int64? {
        let known = downloads.compactMap(\.byteCount)
        return known.isEmpty ? nil : known.reduce(0, +)
    }

    /// Whether any download is running and none has moved: the stall clock
    /// runs only then.
    var isAtZero: Bool {
        phase == .downloading
            && downloads.contains { !$0.isFinished && !$0.hasFailed }
            && downloads.allSatisfy { $0.isFinished || $0.hasFailed || $0.fraction == 0 }
    }

    var isFinished: Bool {
        switch phase {
        case .ready, .cancelled: true
        default: false
        }
    }

    // MARK: Timing

    /// Preparation shows nothing for its first 350 ms — the viewer's spinner
    /// threshold — so a batch already on the device never flashes a modal
    /// (§3). A question for the user shows at once.
    static let showDelay: Duration = .milliseconds(350)

    /// 15 s at 0% across every running download: iCloud is not answering.
    /// The downloads are not cancelled (§3).
    static let stallWindow: Duration = .seconds(15)

    func isShown(elapsed: Duration) -> Bool {
        switch phase {
        case .failed, .notEnoughSpace: true
        case .ready, .cancelled: false
        case .checking, .downloading: elapsed >= Self.showDelay
        }
    }

    /// Whether the batch has sat at 0% for the stall window. `atZeroFor` is
    /// how long `isAtZero` has held.
    func isStalled(atZeroFor: Duration) -> Bool {
        isAtZero && atZeroFor >= Self.stallWindow
    }

    // MARK: Room (step 2)

    /// Whether `needed` bytes fit in `free`. Unknown free space never stops
    /// a batch: the caller shows no warning rather than a wrong one.
    static func fits(needed: Int64, free: Int64?) -> Bool {
        guard let free else { return true }
        return needed < free
    }

    // MARK: Words

    /// Byte counts the way Files writes them: "1.4 GB", "380 MB".
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// The line inside a processing modal (Resize, Collage):
    /// "Downloading from iCloud · 3 of 12 · 42%".
    var progressLine: String {
        String(localized: "Downloading from iCloud · \(currentOrdinal) of \(downloadCount) · \(percent)%",
               comment: "Resize/Collage processing modal: k of n originals, overall percent")
    }

    /// The Share modal's line: "Downloading from iCloud · 63% · 24 MB".
    var shareLine: String {
        if let totalBytes {
            String(localized: "Downloading from iCloud · \(percent)% · \(Self.bytes(totalBytes))",
                   comment: "Share modal: overall percent and the size being downloaded")
        } else {
            String(localized: "Downloading from iCloud · \(percent)%", comment: "Share modal: overall percent")
        }
    }

    /// What VoiceOver reads for a ring without a number (§8).
    static func accessibilityProgress(_ fraction: Double) -> String {
        let percent = Int((min(1, max(0, fraction)) * 100).rounded(.down))
        return String(localized: "Downloading from iCloud, \(percent) percent",
                      comment: "VoiceOver: iCloud download ring")
    }

    /// "2 of 12 photos couldn't be downloaded from iCloud."
    var failureTitle: String {
        let failed = failedNames.count
        return failed == 1 && batchCount == 1
            ? String(localized: "This photo couldn't be downloaded from iCloud.", comment: "Preparation failure, one photo")
            : String(localized: "\(failed) of \(batchCount) photos couldn't be downloaded from iCloud.",
                     comment: "Preparation failure: failed of batch")
    }

    /// The names under the failure title: five at most, then "and N more",
    /// so a long list cannot push the buttons off a 669 pt screen.
    var failureNamesText: String {
        Self.names(failedNames)
    }

    static func names(_ names: [String], limit: Int = 5) -> String {
        guard names.count > limit else { return names.joined(separator: ", ") }
        let shown = names.prefix(limit).joined(separator: ", ")
        return String(localized: "\(shown) and \(names.count - limit) more", comment: "Failed photo names, cut short")
    }

    /// How many photos Continue goes on with.
    var continueCount: Int { batchCount - failedNames.count }

    /// "Not enough space to download these originals — needs 1.4 GB, 380 MB free."
    static func notEnoughSpaceMessage(needed: Int64, free: Int64) -> String {
        String(localized: "Not enough space to download these originals — needs \(bytes(needed)), \(bytes(free)) free.",
               comment: "Preparation: the batch does not fit on the device")
    }

    static let stallMessage = String(
        localized: "iCloud isn't responding — check iCloud Photos in Settings or the Photos app.",
        comment: "A download that has sat at 0% for 15 seconds"
    )
}
