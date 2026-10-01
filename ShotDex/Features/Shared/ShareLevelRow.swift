import LinkPresentation
import ShotDexKit
import UIKit

/// One of the app's two rows in the share sheet (FS-08.06 §4): shares this
/// one share again at another metadata level. Settings is never touched.
final class ShareLevelRow: UIActivity {
    let level: MetadataLevel

    init(level: MetadataLevel) {
        self.level = level
        super.init()
    }

    static func title(for level: MetadataLevel) -> String {
        switch level {
        case .all: String(localized: "Share With Location")
        case .noLocation: String(localized: "Share Without Location")
        case .noMetadata: String(localized: "Share Without Metadata")
        }
    }

    static func activityType(for level: MetadataLevel) -> UIActivity.ActivityType {
        UIActivity.ActivityType("com.hoangtuan.shotdex.share.\(level.rawValue)")
    }

    override class var activityCategory: UIActivity.Category { .action }
    override var activityType: UIActivity.ActivityType? { Self.activityType(for: level) }
    override var activityTitle: String? { Self.title(for: level) }
    override var activityImage: UIImage? {
        let symbol = switch level {
        case .all: "location"
        case .noLocation: "location.slash"
        case .noMetadata: "doc.badge.ellipsis"
        }
        return UIImage(systemName: symbol)
    }

    override func canPerform(withActivityItems activityItems: [Any]) -> Bool { true }

    /// Nothing to do here: the share sheet closes, and its completion handler
    /// sees this row's type and prepares the share again.
    override func perform() { activityDidFinish(true) }
}

/// The first item of a photo share, carrying the header the share sheet
/// shows: the photo (or the count) and the metadata level in force. The
/// header is preview information, not a control (spec §4).
final class ShareHeaderItem: NSObject, UIActivityItemSource {
    let file: URL
    let title: String

    init(file: URL, title: String) {
        self.file = file
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { file }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? { file }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = file
        metadata.url = file
        let provider = NSItemProvider(contentsOf: file)
        metadata.imageProvider = provider
        metadata.iconProvider = provider
        return metadata
    }
}

extension ShareBatchPlan.Subtitle {
    var text: String {
        switch self {
        case .allMetadata: String(localized: "All metadata")
        case .locationRemoved: String(localized: "Location removed")
        case .metadataRemoved: String(localized: "Metadata removed")
        }
    }
}
