import Foundation
import ShotDexKit

/// The value lines of Settings — what each row says about its own state
/// (FS-08.01b §1–2).
///
/// Pure functions of the state the section pages read, so the line under
/// "Camera Database" on the root is the same fact the Camera Database page
/// shows, and can be checked without building a screen. `full` lines sit under
/// a row title; `short` ones sit at the trailing edge of a 44pt sidebar row,
/// where a sentence will not fit — `nil` there means "say nothing".
enum SettingsSummary {

    // MARK: Library and viewing

    static func accessTitle(_ access: PhotoAuthorizationState) -> String {
        switch access {
        case .notDetermined: String(localized: "Not Requested", comment: "Settings → Photo Library: photo access not asked for yet")
        case .authorized: String(localized: "Full Access", comment: "Settings → Photo Library: photo access")
        case .limited: String(localized: "Limited Access", comment: "Settings → Photo Library: photo access")
        case .denied: String(localized: "Denied", comment: "Settings → Photo Library: photo access")
        case .restricted: String(localized: "Restricted", comment: "Settings → Photo Library: photo access")
        }
    }

    /// "Full Access · indexing on Wi-Fi only" — the access, then the one
    /// condition that decides whether indexing runs away from Wi-Fi.
    static func photoLibrary(access: PhotoAuthorizationState, allowsCellular: Bool) -> String {
        let accessTitle = accessTitle(access)
        guard access.canReadLibrary else { return accessTitle }
        let network = allowsCellular
            ? String(localized: "indexing on Wi-Fi and cellular", comment: "Settings root, under Photo Library, after the access level")
            : String(localized: "indexing on Wi-Fi only", comment: "Settings root, under Photo Library, after the access level")
        return joined(accessTitle, network)
    }

    /// The sidebar's Photo Library value: the run's percentage while one is
    /// going, nothing otherwise.
    static func photoLibraryShort(indexingPercent: Int?) -> String? {
        indexingPercent.map { "\($0)%" }
    }

    /// What the Access row says under its title.
    static func accessDetail(_ access: PhotoAuthorizationState) -> String {
        let detail: String = switch access {
        case .authorized: String(localized: "every photo and video", comment: "Settings → Access row, after Full Access")
        case .limited: String(localized: "only the photos you picked", comment: "Settings → Access row, after Limited Access")
        case .denied: String(localized: "ShotDex can't read your photos", comment: "Settings → Access row, after Denied")
        case .restricted: String(localized: "access is blocked on this device", comment: "Settings → Access row, after Restricted")
        case .notDetermined: String(localized: "ShotDex asks the first time it opens", comment: "Settings → Access row, after Not Requested")
        }
        return joined(accessTitle(access), detail)
    }

    /// The details a thumbnail carries, as one list: "ISO, aperture, focal
    /// length, file type". Exposure first, in the order the grid draws it.
    static func display(
        showsISO: Bool,
        showsAperture: Bool,
        showsShutterSpeed: Bool,
        showsFocalLength: Bool,
        showsMegapixels: Bool,
        showsFileSize: Bool,
        showsFileType: Bool
    ) -> String {
        let shown: [String] = [
            showsISO ? String(localized: "ISO", comment: "Settings root, Display value: one item of the list of details shown on thumbnails") : nil,
            showsAperture ? String(localized: "aperture", comment: "Settings root, Display value: list item, lowercase mid-sentence") : nil,
            showsShutterSpeed ? String(localized: "shutter speed", comment: "Settings root, Display value: list item, lowercase mid-sentence") : nil,
            showsFocalLength ? String(localized: "focal length", comment: "Settings root, Display value: list item, lowercase mid-sentence") : nil,
            showsMegapixels ? String(localized: "megapixels", comment: "Settings root, Display value: list item, lowercase mid-sentence") : nil,
            showsFileSize ? String(localized: "file size", comment: "Settings root, Display value: list item, lowercase mid-sentence") : nil,
            showsFileType ? String(localized: "file type", comment: "Settings root, Display value: list item, lowercase mid-sentence") : nil,
        ].compactMap { $0 }
        guard let first = shown.first else {
            return String(localized: "Thumbnails show the photo only", comment: "Settings root, Display value when every thumbnail detail is off")
        }
        let separator = String(localized: ", ", comment: "Separator between items of the Display value list")
        let list = shown.joined(separator: separator)
        // Capitalise the first item only — "Aperture, focal length" — without
        // touching an acronym that leads ("ISO").
        return first.prefix(1).localizedUppercase + list.dropFirst()
    }

    /// "Autoplay on · Full HDR off".
    static func playback(autoplaysVideos: Bool, viewsFullHDR: Bool) -> String {
        let autoplay = autoplaysVideos
            ? String(localized: "Autoplay on", comment: "Settings root, Playback value")
            : String(localized: "Autoplay off", comment: "Settings root, Playback value")
        let hdr = viewsFullHDR
            ? String(localized: "Full HDR on", comment: "Settings root, Playback value")
            : String(localized: "Full HDR off", comment: "Settings root, Playback value")
        return joined(autoplay, hdr)
    }

    /// "41,870 of 55,231 photos scanned".
    static func subjectScan(scanned: Int, total: Int, scanningPercent: Int?) -> String {
        if let scanningPercent {
            return String(localized: "Scanning · \(scanningPercent)%", comment: "Settings root, People and Pets value while a scan runs")
        }
        guard total > 0 else {
            return String(localized: "No photos yet", comment: "Settings root, People and Pets value with an empty library")
        }
        if scanned >= total {
            return String(localized: "Every photo scanned", comment: "Settings root, People and Pets value once the scan is complete")
        }
        if scanned == 0 {
            return String(localized: "Not scanned yet", comment: "Settings root, People and Pets value before the first scan")
        }
        return String(
            localized: "\(scanned.formatted()) of \(total.formatted()) photos scanned",
            comment: "Settings root, People and Pets value: photos scanned of the library"
        )
    }

    /// The sidebar's People and Pets value: how far the scan has got.
    static func subjectScanShort(scanned: Int, total: Int, scanningPercent: Int?) -> String? {
        if let scanningPercent { return "\(scanningPercent)%" }
        guard total > 0, scanned > 0 else { return nil }
        return "\(min(100, scanned * 100 / total))%"
    }

    /// "6 cameras need a sensor format" / "Every camera is known".
    static func cameraDatabase(unknownCameras: Int) -> String {
        switch unknownCameras {
        case ...0: String(localized: "Every camera is known", comment: "Settings root, Camera Database value with no unknown camera")
        case 1: String(localized: "1 camera needs a sensor format", comment: "Settings root, Camera Database value with one unknown camera")
        default: String(localized: "\(unknownCameras) cameras need a sensor format", comment: "Settings root, Camera Database value: number of unknown cameras, more than one")
        }
    }

    static func cameraDatabaseShort(unknownCameras: Int) -> String? {
        guard unknownCameras > 0 else { return nil }
        return String(localized: "\(unknownCameras) unknown", comment: "Settings sidebar, Camera Database value: number of unknown cameras")
    }

    // MARK: Sharing and export

    /// "All Metadata · each share can change it".
    static func metadataWhenSharing(_ level: MetadataLevel) -> String {
        joined(
            String(localized: level.title),
            String(localized: "each share can change it", comment: "Settings root, Metadata When Sharing value, after the default level")
        )
    }

    /// "4 built-in · 3 custom" — the custom half only once there is one.
    static func resizePresets(builtIn: Int, custom: Int) -> String {
        let builtInText = String(localized: "\(builtIn) built-in", comment: "Settings, Resize Presets value: number of presets that ship with the app")
        guard custom > 0 else { return builtInText }
        return joined(builtInText, String(localized: "\(custom) custom", comment: "Settings, Resize Presets value: number of presets the user made"))
    }

    /// Settings › AI's root value: who helps search.
    static func ai(search: String?) -> String {
        search ?? String(localized: "Not set up", comment: "Settings › AI value: nothing chosen")
    }

    /// "Studio NAS, MacBook Pro and 2 more" — the first two names, then a count.
    static func fileServers(names: [String]) -> String {
        switch names.count {
        case 0:
            return String(localized: "None yet", comment: "Settings, File Servers value with no server set up")
        case 1:
            return names[0]
        case 2:
            return String(localized: "\(names[0]) and \(names[1])", comment: "Settings, File Servers value: the two server names")
        default:
            return String(
                localized: "\(names[0]), \(names[1]) and \(names.count - 2) more",
                comment: "Settings, File Servers value: two server names and how many others"
            )
        }
    }

    // MARK: Widgets and notifications

    /// "Photo widget · 3 designs".
    static func widgets(designCount: Int) -> String {
        joined(
            String(localized: "Photo widget", comment: "Settings root, Widgets value: the widget kind"),
            widgetsShort(designCount: designCount)
        )
    }

    static func widgetsShort(designCount: Int) -> String {
        designCount == 1
            ? String(localized: "1 design", comment: "Settings, Widgets value: one photo widget design")
            : String(localized: "\(designCount) designs", comment: "Settings, Widgets value: number of photo widget designs")
    }

    /// "On This Day reminder at 9:00 AM" / "Off". `time` comes in formatted,
    /// so the line follows the device's 12/24-hour setting.
    static func notifications(isReminderOn: Bool, isDenied: Bool, time: String) -> String {
        if isDenied {
            return String(localized: "Off · not allowed in iOS Settings", comment: "Settings root, Notifications value when iOS refuses notifications")
        }
        guard isReminderOn else {
            return String(localized: "Off", comment: "Settings root, Notifications value with the reminder off")
        }
        return String(localized: "On This Day reminder at \(time)", comment: "Settings root, Notifications value: the daily reminder time")
    }

    static func notificationsShort(isReminderOn: Bool, isDenied: Bool, time: String) -> String {
        guard isReminderOn, !isDenied else {
            return String(localized: "Off", comment: "Settings sidebar, Notifications value with the reminder off")
        }
        return time
    }

    // MARK: Help

    /// What the Support row says. Replies are not counted here: knowing them
    /// means a signed call to the support server, and opening Settings must
    /// not reach the network (NF-03).
    static func support() -> String {
        String(localized: "No account needed", comment: "Settings root, Support value")
    }

    // MARK: Helpers

    /// Two facts on one line, in the order given.
    static func joined(_ first: String, _ second: String) -> String {
        String(localized: "\(first) · \(second)", comment: "Settings value line: two facts joined by a middle dot")
    }
}
