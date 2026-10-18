import Foundation

/// Whether this system lets the app read and write Photos' own caption and
/// keywords (`PHAsset.extendedMetadata`, iOS 27). The one gate every caption
/// and keyword control asks — Info's editable section, the selection ⋯
/// entry, the Keyword and Caption rule fields (FS-02.07 §6: below iOS 27 the
/// controls are **hidden**, not dimmed).
///
/// Code that decides what to show takes the answer as a parameter defaulting
/// to `isAvailable`, so a test walks both branches on any simulator.
enum ExtendedMetadataSupport {
    static var isAvailable: Bool {
        if #available(iOS 27, macOS 27, *) { return true }
        return false
    }
}
