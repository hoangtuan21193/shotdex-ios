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

/// Files the system RAW decoder refuses (FS-03.04b M2), made from the samples
/// at test time — no real camera is unsupported on iOS 26.5, and nothing new
/// is downloaded.
extension RAWFixtures {
    /// The X-T4 sample with its model renamed `X-Q9`: the decoder gives no
    /// image, while ImageIO still reads Make/Model and the 4416 × 2944
    /// embedded preview — a camera iOS does not support yet.
    static func unsupportedCamera(in folder: URL) throws -> URL? {
        guard let source = available(fuji) else { return nil }
        var data = try Data(contentsOf: source)
        let from = Data("X-T4".utf8), to = Data("X-Q9".utf8)
        var start = data.startIndex
        while let range = data.range(of: from, in: start..<data.endIndex) {
            data.replaceSubrange(range, with: to)
            start = range.upperBound
        }
        let url = folder.appendingPathComponent("DSCF0001.RAF")
        try data.write(to: url)
        return url
    }

    /// The first `bytes` of a sample: 200 KB still reads as the camera's RAW
    /// with a 160 × 120 thumbnail and no image; 2 KB is beyond ImageIO.
    static func truncated(_ name: String, bytes: Int, in folder: URL) throws -> URL? {
        guard let source = available(name) else { return nil }
        let url = folder.appendingPathComponent("cut-\(bytes)-\(name)")
        try Data(contentsOf: source).prefix(bytes).write(to: url)
        return url
    }

    /// Bytes that are no image at all, under a RAW extension.
    static func junk(extension ext: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("junk.\(ext)")
        try Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 2_654_435_761 >> 13) }).write(to: url)
        return url
    }
}
