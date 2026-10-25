#if DEBUG
import Foundation
import os
import Photos

/// FS-19.07b §1: the measurements a simulator cannot make — run on a real
/// iPhone, launched from Xcode with one argument, numbers written to the
/// console (category `on-server-spike`) and appended to
/// `Documents/on-server-spike.log`. Not shipped: DEBUG only.
///
/// - `-ShotDexOnServerSpike S1` downloads 50 photos and 5 videos that are
///   not on the device (iCloud full, Optimize Storage on), one at a time,
///   each to a temporary file deleted at once: result, seconds, error code.
/// - `-ShotDexOnServerSpike S2` downloads up to 10 GB that way, then logs
///   free space before, right after, and on each later launch with `S2`
///   (run it again after 1 hour and after 24 hours).
/// - S3 needs no argument: every background slot of the check appends
///   one line (`OnServerBackgroundService`).
/// - `-ShotDexOnServerSpike S4` hashes the 3 largest videos with the
///   streaming SHA-256 the check uses, sampling the memory footprint and
///   the thermal state.
enum OnServerSpike {
    static let argument = "-ShotDexOnServerSpike"
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "on-server-spike")

    /// Starts the spike named on the command line, if any.
    static func runIfAsked() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: argument), args.indices.contains(index + 1) else { return }
        let name = args[index + 1]
        Task.detached(priority: .utility) {
            log("start \(name) · \(ProcessInfo.processInfo.operatingSystemVersionString) · free \(gb(freeBytes()))")
            switch name {
            case "S1": await s1()
            case "S2": await s2()
            case "S4": await s4()
            default: log("unknown spike \(name)")
            }
            log("end \(name)")
        }
    }

    // MARK: - S1

    private static func s1() async {
        let photos = notLocal(.image, limit: 50)
        let videos = notLocal(.video, limit: 5)
        log("S1: \(photos.count) photos + \(videos.count) videos not on the device")
        var ok = 0
        for asset in photos + videos {
            let started = Date()
            switch await downloadAndDelete(asset) {
            case .success(let bytes):
                ok += 1
                log("S1 ok \(asset.mediaType == .video ? "video" : "photo") \(mb(bytes)) in \(seconds(since: started))")
            case .failure(let error):
                let ns = error as NSError
                log("S1 FAIL \(ns.domain) \(ns.code) after \(seconds(since: started)): \(ns.localizedDescription)")
            }
        }
        log("S1 result \(ok)/\(photos.count + videos.count) (pass: ≥ 54/55)")
    }

    // MARK: - S2

    private static let s2Key = "OnServerSpike.S2.baseline"

    private static func s2() async {
        let defaults = UserDefaults.standard
        if let baseline = defaults.object(forKey: s2Key) as? [String: Double] {
            let before = Int64(baseline["before"] ?? 0)
            let hours = (Date().timeIntervalSince1970 - (baseline["at"] ?? 0)) / 3600
            log(String(format: "S2 after %.1f h: free %@ (before download %@, change %@)", hours,
                       gb(freeBytes()), gb(before), gb((freeBytes() ?? 0) - before)))
            return
        }
        let before = freeBytes() ?? 0
        var total: Int64 = 0
        for asset in notLocal(.video, limit: 400) + notLocal(.image, limit: 2_000) where total < 10_000_000_000 {
            if case .success(let bytes) = await downloadAndDelete(asset) { total += bytes }
        }
        let after = freeBytes() ?? 0
        defaults.set(["before": Double(before), "at": Date().timeIntervalSince1970], forKey: s2Key)
        log("S2 downloaded \(gb(total)) and deleted each file: free before \(gb(before)), right after \(gb(after)), change \(gb(after - before)) (pass: ≤ 1 GB lost after 24 h)")
    }

    // MARK: - S4

    private static func s4() async {
        let fetch = PHAsset.fetchAssets(with: .video, options: nil)
        var videos: [(PHAsset, PHAssetResource, Int64)] = []
        fetch.enumerateObjects { asset, _, _ in
            guard let resource = PHAssetResource.assetResources(for: asset).first(where: { $0.type == .video }),
                  let size = resource.value(forKey: "fileSize") as? Int64 else { return }
            videos.append((asset, resource, size))
        }
        for (_, resource, size) in videos.sorted(by: { $0.2 > $1.2 }).prefix(3) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("spike-\(UUID().uuidString)")
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            do {
                try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
                let base = footprint()
                let peak = OSAllocatedUnfairLock(initialState: base)
                let sampler = Task.detached {
                    while !Task.isCancelled {
                        let now = footprint()
                        peak.withLock { $0 = max($0, now) }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
                let started = Date()
                _ = try FileChecksum.sha256(of: url)
                sampler.cancel()
                let grew = Int64(peak.withLock { $0 }) - Int64(base)
                log("S4 \(mb(size)) hashed in \(seconds(since: started)), memory +\(mb(grew)) (pass: ≤ 64 MB), thermal \(ProcessInfo.processInfo.thermalState.rawValue)")
            } catch {
                log("S4 FAIL \((error as NSError).code): \(error.localizedDescription)")
            }
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    /// Assets whose original is not on the device: a local-only request for
    /// the first resource fails at once.
    private static func notLocal(_ type: PHAssetMediaType, limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: type, options: options)
        var out: [PHAsset] = []
        fetch.enumerateObjects { asset, _, stop in
            guard let resource = PHAssetResource.assetResources(for: asset).first else { return }
            if (resource.value(forKey: "locallyAvailable") as? Bool) == false { out.append(asset) }
            if out.count >= limit { stop.pointee = true }
        }
        return out
    }

    private static func downloadAndDelete(_ asset: PHAsset) async -> Result<Int64, Error> {
        guard let resource = PHAssetResource.assetResources(for: asset).first else {
            return .failure(CocoaError(.fileNoSuchFile))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("spike-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        do {
            try await PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            return .success(size)
        } catch {
            return .failure(error)
        }
    }

    /// A line from elsewhere in the app — the background slot (S3).
    static func record(_ line: String) { log(line) }

    private static func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("on-server-spike.log")
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }

    private static func freeBytes() -> Int64? { DiskSpace.availableBytes() }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private static func gb(_ bytes: Int64?) -> String { String(format: "%.2f GB", Double(bytes ?? 0) / 1e9) }
    private static func mb(_ bytes: Int64) -> String { String(format: "%.1f MB", Double(bytes) / 1_048_576) }
    private static func seconds(since date: Date) -> String { String(format: "%.1f s", Date().timeIntervalSince(date)) }
}
#endif
