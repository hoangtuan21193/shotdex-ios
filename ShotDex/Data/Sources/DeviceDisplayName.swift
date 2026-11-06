import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// What this device is called, for the other devices on the same iCloud
/// account (FS-19.07 §12.4: "Hashes from Tuấn's MacBook didn't match"). An
/// iPhone without the device-name entitlement reports its model, "iPhone".
/// Nil when there is none: the device reading it says "another device" in
/// its own language.
enum DeviceDisplayName {
    static func current() async -> String? {
        #if os(macOS)
        Host.current().localizedName
        #else
        await MainActor.run { UIDevice.current.name }
        #endif
    }
}
