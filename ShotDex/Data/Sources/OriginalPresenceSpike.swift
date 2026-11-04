#if DEBUG
import Foundation
import os
import Photos

/// FS-06.10 AC-1: the two ways to tell whether a photo's originals are on
/// this device, measured on a real iPhone (a simulator has no iCloud
/// library). Launch from Xcode with `-ShotDexOriginalSpike` (optionally
/// followed by a number: how many photos, default all). Numbers go to the
/// console (category `original-spike`) and to `Documents/original-spike.log`.
/// Not shipped: DEBUG only.
///
/// - (a) the shipping probe, `OriginalPresenceProbe.check`, in batches of
///   200 as the check runs them: seconds, CPU seconds, peak footprint;
/// - (b) the unpublished `locallyAvailable` key of every required
///   resource: the same numbers;
/// - how often the two agree, and the first disagreements by id.
enum OriginalPresenceSpike {
    static let argument = "-ShotDexOriginalSpike"
    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "original-spike")

    static func runIfAsked() {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: argument) else { return }
        let limit = args.indices.contains(index + 1) ? Int(args[index + 1]) : nil
        Task.detached(priority: .utility) { await run(limit: limit) }
    }

    private static func run(limit: Int?) async {
        // Default source types: the same scope as the check's id fetch.
        let fetch = PHAsset.fetchAssets(with: nil)
        var ids: [String] = []
        fetch.enumerateObjects { asset, _, stop in
            ids.append(asset.localIdentifier)
            if let limit, ids.count >= limit { stop.pointee = true }
        }
        log("start · \(ids.count) photos · (a) runs first, cold cache · \(ProcessInfo.processInfo.operatingSystemVersionString)")

        let (a, aStats) = await measure {
            var all: [String: OriginalPresence?] = [:]
            for start in stride(from: 0, to: ids.count, by: 200) {
                let batch = Array(ids[start..<min(start + 200, ids.count)])
                all.merge(await OriginalPresenceProbe.check(batch)) { $1 }
            }
            return all
        }
        log("(a) probe · \(aStats) · " + summary(a))

        let (b, bStats) = await measure { kvc(ids) }
        log("(b) locallyAvailable · \(bStats) · " + summary(b))

        var same = 0, compared = 0
        var differ: [String] = []
        for id in ids {
            guard let left = a[id], let right = b[id], let left, let right else { continue }
            compared += 1
            if left == right { same += 1 } else if differ.count < 20 { differ.append("\(id) a=\(left) b=\(right)") }
        }
        // (c) photos (a) calls on device, checked again by the header-size
        // probe the viewer uses: a local preview handed over as the file
        // would show here (FS-02.06 AC-11 premise).
        let sample = ids.filter { a[$0] == .some(.onDevice) }.prefix(500)
        var previews = 0
        let fetcher = PhotoKitOriginalFetcher()
        let sampled = PHAsset.fetchAssets(withLocalIdentifiers: Array(sample), options: nil)
        var items: [OriginalItem] = []
        sampled.enumerateObjects { asset, _, _ in if asset.mediaType == .image { items.append(OriginalItem(asset: asset)) } }
        for item in items where await fetcher.probe(item) == .inCloud {
            previews += 1
            if previews <= 20 { log("header says preview: \(item.id)") }
        }
        log("(c) header check on \(items.count) photos (a) called on device: \(previews) look like previews")

        log(String(format: "agree %d of %d compared (%.3f%%)", same, compared, compared == 0 ? 0 : Double(same) * 100 / Double(compared)))
        for line in differ { log("differ \(line)") }
        log("end")
    }

    /// (b): the unpublished key, read on each required resource.
    private static func kvc(_ ids: [String]) -> [String: OriginalPresence?] {
        var out: [String: OriginalPresence?] = [:]
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        assets.enumerateObjects { asset, _, _ in
            let all = PHAssetResource.assetResources(for: asset)
            let required = Set(OriginalPresence.required(among: all.map { OriginalPresenceProbe.resource($0.type) }))
            let answers: [OriginalAvailability] = all.filter { required.contains(OriginalPresenceProbe.resource($0.type)) }.map {
                guard $0.responds(to: Selector(("locallyAvailable"))),
                      let value = $0.value(forKey: "locallyAvailable") as? Bool else { return .unknown }
                return value ? .local : .inCloud
            }
            out[asset.localIdentifier] = .some(OriginalPresence.judge(answers))
        }
        return out
    }

    private static func summary(_ results: [String: OriginalPresence?]) -> String {
        let on = results.values.filter { $0 == .onDevice }.count
        let cloud = results.values.filter { $0 == .iCloudOnly }.count
        return "on device \(on) · iCloud only \(cloud) · could not tell \(results.count - on - cloud)"
    }

    private static func measure<T>(_ work: () async -> T) async -> (T, String) {
        let peak = OSAllocatedUnfairLock(initialState: footprint())
        let sampling = Task.detached {
            while !Task.isCancelled {
                let now = footprint()
                peak.withLock { $0 = max($0, now) }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        let cpu0 = cpuSeconds(), start = Date()
        let value = await work()
        let elapsed = Date().timeIntervalSince(start), cpu = cpuSeconds() - cpu0
        sampling.cancel()
        return (value, String(format: "%.1f s · CPU %.1f s · peak %.1f MB", elapsed, cpu, Double(peak.withLock { $0 }) / 1_048_576))
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }

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

    private static func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("original-spike.log")
        let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(line)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
            try? handle.close()
        } else {
            try? Data(stamped.utf8).write(to: url)
        }
    }
}
#endif
