import Foundation

/// The real RAW samples (CC0, raw.pixls.us, checked for faces) live outside
/// the repo — they are tens of MB each — in `~/Library/Caches/ShotDexFixtures/raw/`
/// on the host, or wherever `SHOTDEX_RAW_FIXTURES` points. A test that needs
/// one is skipped, saying so, when the folder is missing.
enum RAWFixtures {
    static let sony = "Sony-ILCE-7M3.ARW"
    static let fuji = "Fujifilm-X-T4.RAF"
    /// Carries a real GPS position.
    static let dji = "DJI-FC4382.DNG"

    static var folder: URL {
        if let path = ProcessInfo.processInfo.environment["SHOTDEX_RAW_FIXTURES"] {
            return URL(fileURLWithPath: path)
        }
        // The simulator's home is inside the host's; the cache folder is the
        // host user's, reached from the test bundle's path.
        let home = URL(fileURLWithPath: #filePath).pathComponents.prefix(3).joined(separator: "/")
            .replacingOccurrences(of: "//", with: "/")
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Caches/ShotDexFixtures/raw")
    }

    /// The sample's URL if it is on this machine.
    static func available(_ name: String) -> URL? {
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func has(_ name: String) -> Bool { available(name) != nil }
}
