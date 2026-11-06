import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The words for the **Original** rule (FS-06.10 §4), named after the device
/// the check ran on — the way Files says On My iPad. The Duo is an iPhone.
extension OriginalPresence {
    var label: String {
        switch self {
        case .onDevice: Self.onThisDevice
        case .iCloudOnly: String(localized: "iCloud Only", comment: "Original rule value: at least one original file of the photo is only in iCloud")
        }
    }

    /// "On This iPhone", "On This iPad" or "On This Mac".
    static var onThisDevice: String {
        #if os(macOS)
        String(localized: "On This Mac", comment: "Original rule value: every original file of the photo is on this Mac")
        #else
        UIDevice.current.userInterfaceIdiom == .pad
            ? String(localized: "On This iPad", comment: "Original rule value: every original file of the photo is on this iPad")
            : String(localized: "On This iPhone", comment: "Original rule value: every original file of the photo is on this iPhone")
        #endif
    }

    /// The Filter menu toggle and its chip: "Original on This iPhone".
    static var filterTitle: String {
        #if os(macOS)
        String(localized: "Original on This Mac", comment: "Filter toggle: only photos whose original files are all on this Mac")
        #else
        UIDevice.current.userInterfaceIdiom == .pad
            ? String(localized: "Original on This iPad", comment: "Filter toggle: only photos whose original files are all on this iPad")
            : String(localized: "Original on This iPhone", comment: "Filter toggle: only photos whose original files are all on this iPhone")
        #endif
    }

    /// The compact chip: "Original on This iPhone" or "Original in iCloud Only".
    var chipTitle: String {
        switch self {
        case .onDevice: Self.filterTitle
        case .iCloudOnly: String(localized: "Original in iCloud Only", comment: "Filter chip: only photos with an original file that is only in iCloud")
        }
    }
}
