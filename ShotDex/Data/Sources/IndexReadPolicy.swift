import Foundation

/// What an index run may do to get a photo's EXIF on this device
/// (intents 2026-11-02-mac-local-only-index and -icloud-shared-index).
enum IndexReadPolicy {
    /// Read only originals already on this device: no iCloud download and no
    /// downscaled derivative. Photos without a local original wait for another
    /// device's result, or for "Index Now". On the Mac it is the user's switch;
    /// on iPhone and iPad it follows the Mac indexing for every device.
    static var readsOriginalsOnly: Bool {
        #if os(macOS)
        UserDefaults.standard.bool(forKey: SettingsKeys.indexesOriginalsOnly)
        #else
        defersToMac
        #endif
    }

    /// iPhone/iPad: a Mac on this iCloud account indexes for every device and
    /// this device has not opted out. Always false on the Mac.
    static var defersToMac: Bool {
        #if os(macOS)
        false
        #else
        IndexShareService.sharesIndex
            && UserDefaults.standard.bool(forKey: SettingsKeys.macIndexesForAll)
            && !UserDefaults.standard.bool(forKey: SettingsKeys.ignoresMacIndex)
        #endif
    }
}
