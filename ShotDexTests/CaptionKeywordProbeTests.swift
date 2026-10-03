import Foundation
import ImageIO
import Photos
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-02.07 plan M1–M5, M7 — measurements, not feature tests. On iOS 27 each
/// test writes captions and keywords onto library assets through
/// `PHAssetChangeRequest` and prints what PhotoKit did, then puts every value
/// it wrote back the way it found it.
///
/// - M1: does a caption or keyword write move `modificationDate`, and does the
///   id come back in `fetchPersistentChanges(…).updatedLocalIdentifiers`?
/// - M2: does Photos take IPTC Keywords / Caption-Abstract from a file into
///   its own keywords and caption on import? (`m2ImportedIPTC` reads what a
///   host-side `simctl addmedia` brought in, and imports one file itself.)
/// - M3: one block of 1,000 and 5,000 keyword writes — time, any system prompt.
/// - M4: `canPerform(.properties)` on the user's own assets.
/// - M5: length ceilings, empty and whitespace keywords, case and diacritics.
/// - M7: does `prefetchAssetExtendedMetadata` apply to a fetch by identifier?
///
/// Skips itself below iOS 27 and without full photo access, so it never runs
/// in `Tools/gate` on the 26.5 simulator. Run it on purpose:
/// `-only-testing:ShotDexTests/CaptionKeywordProbeTests` with an iOS 27
/// destination.
@Suite(.serialized)
struct CaptionKeywordProbeTests {

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("[CaptionKeywordProbe] \(line)\n".utf8))
    }

    private static var canRun: Bool {
        guard #available(iOS 27, *) else { return false }
        return PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized
    }

    private static func images(_ count: Int, skipping: Int = 0) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let fetch = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        let end = min(fetch.count, skipping + count)
        guard end > skipping else { return [] }
        fetch.enumerateObjects(at: IndexSet(integersIn: skipping..<end), options: []) { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    @available(iOS 27, *)
    private static func extended(_ ids: [String]) -> [String: PHAssetExtendedMetadata] {
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
        var result: [String: PHAssetExtendedMetadata] = [:]
        fetch.enumerateObjects { asset, _, _ in result[asset.localIdentifier] = asset.extendedMetadata }
        return result
    }

    private static func modificationDates(_ ids: [String]) -> [String: Date?] {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var dates: [String: Date?] = [:]
        fetch.enumerateObjects { asset, _, _ in dates[asset.localIdentifier] = asset.modificationDate }
        return dates
    }

    private static func updatedSince(_ token: PHPersistentChangeToken) -> Set<String> {
        var updated = Set<String>()
        guard let changes = try? PHPhotoLibrary.shared().fetchPersistentChanges(since: token) else { return [] }
        for change in changes {
            guard let details = try? change.changeDetails(for: .asset) else { continue }
            updated.formUnion(details.updatedLocalIdentifiers)
        }
        return updated
    }

    /// One write, reported: block time, read-back, date moved, in "updated".
    @available(iOS 27, *)
    private static func measure(
        _ label: String, ids: [String], _ change: @escaping @Sendable (PHAssetChangeRequest) -> Void
    ) async throws {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        let before = modificationDates(ids)
        let token = PHPhotoLibrary.shared().currentChangeToken
        let start = ContinuousClock.now
        var failure: String?
        do {
            try await PHPhotoLibrary.shared().performChanges {
                assets.enumerateObjects { asset, _, _ in change(PHAssetChangeRequest(for: asset)) }
            }
        } catch {
            failure = "\(error)"
        }
        let elapsed = ContinuousClock.now - start
        try await Task.sleep(for: .seconds(2))
        let after = modificationDates(ids)
        let moved = ids.filter { (before[$0] ?? nil) != (after[$0] ?? nil) }.count
        let updated = updatedSince(token)
        let inUpdated = ids.filter(updated.contains).count
        log("""
            \(label): count=\(ids.count) block=\(elapsed) error=\(failure ?? "none") \
            modificationDateMoved=\(moved) inUpdatedLocalIdentifiers=\(inUpdated)
            """)
    }

    // MARK: - M1

    @Test func m1CaptionAndKeywordWrites() async throws {
        guard Self.canRun, #available(iOS 27, *) else {
            Self.log("skipped: needs iOS 27 and full photo access")
            return
        }
        let assets = Self.images(3, skipping: 40)
        guard assets.count == 3 else { return }
        let a = assets[0].localIdentifier, b = assets[1].localIdentifier, c = assets[2].localIdentifier
        let start = Self.extended([a, b, c])
        Self.log("M1 before: \(start.mapValues { "caption=\($0.caption ?? "nil") keywords=\($0.keywords)" })")

        try await Self.measure("M1 caption+keyword on A", ids: [a]) {
            $0.caption = "Probe caption"
            $0.addKeyword("ProbeKW")
        }
        try await Self.measure("M1 caption only on B", ids: [b]) { $0.caption = "Probe caption B" }
        try await Self.measure("M1 keyword only on C", ids: [c]) { $0.addKeyword("ProbeKW") }
        let written = Self.extended([a, b, c])
        Self.log("M1 readBack: \(written.mapValues { "caption=\($0.caption ?? "nil") keywords=\($0.keywords)" })")

        // The same values again: does a write that changes nothing count?
        try await Self.measure("M1 no-op addKeyword already present on C", ids: [c]) { $0.addKeyword("ProbeKW") }
        try await Self.measure("M1 no-op same caption on B", ids: [b]) { $0.caption = "Probe caption B" }
        try await Self.measure("M1 no-op removeKeyword absent on B", ids: [b]) { $0.removeKeyword("NotThere") }

        // Video.
        let videos = PHAsset.fetchAssets(with: .video, options: nil)
        if let video = videos.firstObject {
            try await Self.measure("M1 video keyword+caption", ids: [video.localIdentifier]) {
                $0.caption = "Probe video"
                $0.addKeyword("ProbeKW")
            }
            Self.log("M1 video readBack: \(Self.extended([video.localIdentifier]).values.map { "\($0.caption ?? "nil") \($0.keywords)" })")
            try await Self.measure("M1 video reset", ids: [video.localIdentifier]) {
                $0.caption = ""
                $0.removeKeyword("ProbeKW")
            }
        }

        try await Self.measure("M1 reset caption nil + removeKeyword", ids: [a, b, c]) {
            $0.caption = nil
            $0.removeKeyword("ProbeKW")
        }
        try await Self.measure("M1 clear caption with empty string on A", ids: [a]) { $0.caption = "" }
        let reset = Self.extended([a, b, c])
        Self.log("M1 after reset: \(reset.mapValues { "caption=\($0.caption.map { "\"\($0)\"" } ?? "nil") keywords=\($0.keywords)" })")
    }

    // MARK: - M1, the Photos-app half

    private static var tokenURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("caption-keyword-probe.token")
    }

    /// Step 1: remember where Photos' history stands. Then add the keyword
    /// `PhotosAppKW` to one photo **in the Photos app** (`Tools/ui-drive`).
    @Test func m1aSaveToken() async throws {
        guard Self.canRun, #available(iOS 27, *) else { return }
        let token = PHPhotoLibrary.shared().currentChangeToken
        let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        try data.write(to: Self.tokenURL)
        Self.log("M1 Photos app: token saved at \(Date())")
    }

    /// Step 2: did the Photos-app edit move the date and land in "updated"?
    @Test func m1bPhotosAppEdit() async throws {
        guard Self.canRun, #available(iOS 27, *) else { return }
        let data = try Data(contentsOf: Self.tokenURL)
        guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: PHPersistentChangeToken.self, from: data) else { return }
        let saved = (try? FileManager.default.attributesOfItem(atPath: Self.tokenURL.path)[.modificationDate] as? Date) ?? .distantPast
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        var tagged: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            if asset.extendedMetadata.keywords.contains("PhotosAppKW") { tagged.append(asset) }
        }
        let updated = Self.updatedSince(token)
        for asset in tagged {
            Self.log("""
                M1 Photos app: keyword found on \(asset.localIdentifier) \
                inUpdatedLocalIdentifiers=\(updated.contains(asset.localIdentifier)) \
                modificationDateMovedAfterToken=\((asset.modificationDate ?? .distantPast) > saved)
                """)
        }
        Self.log("M1 Photos app: tagged=\(tagged.count) updatedSinceToken=\(updated.count)")
    }

    // MARK: - M5

    @Test func m5LengthsCaseAndDiacritics() async throws {
        guard Self.canRun, #available(iOS 27, *) else {
            Self.log("skipped: needs iOS 27 and full photo access")
            return
        }
        guard let asset = Self.images(1, skipping: 50).first else { return }
        let id = asset.localIdentifier

        for length in [1, 2_000, 2_001, 4_000, 4_096, 8_000, 16_000, 20_000] {
            let caption = String(repeating: "ă", count: length)
            try await Self.measure("M5 caption \(length)", ids: [id]) { $0.caption = caption }
            let back = Self.extended([id])[id]?.caption ?? ""
            Self.log("M5 caption \(length): readBack length=\(back.count) equal=\(back == caption)")
        }
        try await Self.measure("M5 caption reset", ids: [id]) { $0.caption = "" }

        for length in [1, 255, 2_000, 4_000, 10_000, 20_000] {
            let keyword = String(repeating: "k", count: length)
            try await Self.measure("M5 keyword \(length)", ids: [id]) { $0.addKeyword(keyword) }
            let back = Self.extended([id])[id]?.keywords ?? []
            Self.log("M5 keyword \(length): readBack lengths=\(back.map(\.count)) contains=\(back.contains(keyword))")
            try await Self.measure("M5 keyword \(length) reset", ids: [id]) { $0.removeKeyword(keyword) }
        }

        for (label, keyword) in [("empty", ""), ("whitespace", "   "), ("padded", "  Padded  "), ("comma", "a, b")] {
            try await Self.measure("M5 keyword \(label)", ids: [id]) { $0.addKeyword(keyword) }
            let back = Self.extended([id])[id]?.keywords ?? []
            Self.log("M5 keyword \(label): readBack=\(back.map { "\"\($0)\"" })")
            try await Self.measure("M5 keyword \(label) reset", ids: [id]) {
                $0.removeKeyword(keyword)
                $0.removeKeyword(keyword.trimmingCharacters(in: .whitespaces))
            }
        }

        // Case: does Photos keep `Sunset` and `sunset` apart on one asset, and
        // does removing one spelling take the other?
        try await Self.measure("M5 case add Sunset", ids: [id]) { $0.addKeyword("ProbeSunset") }
        try await Self.measure("M5 case add sunset", ids: [id]) { $0.addKeyword("probesunset") }
        Self.log("M5 case readBack=\(Self.extended([id])[id]?.keywords ?? [])")
        try await Self.measure("M5 case remove lowercase only", ids: [id]) { $0.removeKeyword("probesunset") }
        Self.log("M5 case after removing lowercase=\(Self.extended([id])[id]?.keywords ?? [])")
        try await Self.measure("M5 case reset", ids: [id]) {
            $0.removeKeyword("ProbeSunset")
            $0.removeKeyword("probesunset")
        }

        // Case across assets: B already has `ProbeCase`, A gets `probecase`.
        let others = Self.images(1, skipping: 51)
        if let other = others.first?.localIdentifier {
            try await Self.measure("M5 cross-asset add ProbeCase on B", ids: [other]) { $0.addKeyword("ProbeCase") }
            try await Self.measure("M5 cross-asset add probecase on A", ids: [id]) { $0.addKeyword("probecase") }
            let both = Self.extended([id, other])
            Self.log("M5 cross-asset readBack A=\(both[id]?.keywords ?? []) B=\(both[other]?.keywords ?? [])")
            try await Self.measure("M5 cross-asset reset", ids: [id, other]) {
                $0.removeKeyword("ProbeCase")
                $0.removeKeyword("probecase")
            }
        }

        try await Self.measure("M5 diacritics", ids: [id]) {
            $0.addKeyword("Đà Lạt Probe")
            $0.addKeyword("Da Lat Probe")
        }
        Self.log("M5 diacritics readBack=\(Self.extended([id])[id]?.keywords ?? [])")
        try await Self.measure("M5 diacritics reset", ids: [id]) {
            $0.removeKeyword("Đà Lạt Probe")
            $0.removeKeyword("Da Lat Probe")
        }
        Self.log("M5 final=\(Self.extended([id])[id].map { "caption=\($0.caption ?? "nil") keywords=\($0.keywords)" } ?? "-")")
    }

    // MARK: - M4

    @Test func m4EditPermission() async throws {
        guard Self.canRun, #available(iOS 27, *) else {
            Self.log("skipped: needs iOS 27 and full photo access")
            return
        }
        let assets = Self.images(500)
        let allowed = assets.filter { $0.canPerform(.properties) }.count
        let content = assets.filter { $0.canPerform(.content) }.count
        Self.log("M4 properties allowed=\(allowed)/\(assets.count) content allowed=\(content)/\(assets.count)")
        let sources = Dictionary(grouping: assets, by: { $0.sourceType.rawValue }).mapValues(\.count)
        Self.log("M4 sourceTypes=\(sources)")
    }

    // MARK: - M3

    @Test func m3BulkKeywordWrite() async throws {
        guard Self.canRun, #available(iOS 27, *) else {
            Self.log("skipped: needs iOS 27 and full photo access")
            return
        }
        for count in [1_000, 5_000] {
            let ids = Self.images(count, skipping: 100).map(\.localIdentifier)
            Self.log("M3 \(count): start \(Date())")
            try await Self.measure("M3 add keyword x\(ids.count)", ids: ids) { $0.addKeyword("ProbeBulk") }
            let back = Self.extended(ids).values.filter { $0.keywords.contains("ProbeBulk") }.count
            Self.log("M3 \(count): readBack=\(back)/\(ids.count)")
            try await Self.measure("M3 caption x\(ids.count)", ids: ids) { $0.caption = "Probe bulk" }
            try await Self.measure("M3 reset x\(ids.count)", ids: ids) {
                $0.removeKeyword("ProbeBulk")
                $0.caption = ""
            }
            Self.log("M3 \(count): end \(Date())")
        }
    }

    // MARK: - M7

    @Test func m7PrefetchByIdentifier() async throws {
        guard Self.canRun, #available(iOS 27, *) else {
            Self.log("skipped: needs iOS 27 and full photo access")
            return
        }
        let ids = Self.images(1_000, skipping: 2_000).map(\.localIdentifier)

        func read(prefetch: Bool, label: String) {
            let options = PHFetchOptions()
            options.prefetchAssetExtendedMetadata = prefetch
            let start = ContinuousClock.now
            let fetch = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: options)
            var keywords = 0
            let fetched = ContinuousClock.now
            fetch.enumerateObjects { asset, _, _ in keywords += asset.extendedMetadata.keywords.count }
            let end = ContinuousClock.now
            Self.log("M7 \(label): count=\(fetch.count) fetch=\(fetched - start) readAll=\(end - fetched) keywords=\(keywords)")
        }
        read(prefetch: true, label: "byId prefetch (cold)")
        read(prefetch: false, label: "byId lazy")
        read(prefetch: true, label: "byId prefetch (warm)")

        // The same 1,000 through a predicate fetch, for comparison.
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        options.fetchLimit = 1_000
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let start = ContinuousClock.now
        let fetch = PHAsset.fetchAssets(with: options)
        var count = 0
        fetch.enumerateObjects { asset, _, _ in count += asset.extendedMetadata.keywords.count }
        Self.log("M7 fetchLimit prefetch: count=\(fetch.count) total=\(ContinuousClock.now - start)")
    }

    // MARK: - M2

    /// Reads every asset Photos imported with keywords or a caption — after a
    /// host-side `xcrun simctl addmedia` of a JPEG carrying IPTC Keywords
    /// `Lightroom, test` — and imports one such file itself through
    /// `PHAssetCreationRequest`, to compare the two doors.
    @Test func m2ImportedIPTC() async throws {
        guard Self.canRun, #available(iOS 27, *) else {
            Self.log("skipped: needs iOS 27 and full photo access")
            return
        }
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let fetch = PHAsset.fetchAssets(with: .image, options: options)
        var found: [String] = []
        var tagged = 0
        fetch.enumerateObjects { asset, _, _ in
            let meta = asset.extendedMetadata
            if !meta.keywords.isEmpty || meta.caption != nil { tagged += 1 }
            if let name = meta.originalFilename, name.hasPrefix("lr-iptc") || name.hasPrefix("probe-iptc") {
                found.append("\(name): caption=\(meta.caption ?? "nil") keywords=\(meta.keywords)")
            }
        }
        Self.log("M2 assets with Photos keywords or caption: \(tagged); IPTC files: \(found)")

        guard !found.contains(where: { $0.hasPrefix("probe-iptc") }) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("probe-iptc.jpg")
        try Self.writeIPTCJPEG(to: url)
        var createdId: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, fileURL: url, options: nil)
            createdId = request.placeholderForCreatedAsset?.localIdentifier
        }
        if let createdId {
            try await Task.sleep(for: .seconds(2))
            let meta = Self.extended([createdId])[createdId]
            Self.log("M2 creationRequest: caption=\(meta?.caption ?? "nil") keywords=\(meta?.keywords ?? []) name=\(meta?.originalFilename ?? "nil")")
        }
    }

    /// 64×64 noise with IPTC Keywords and Caption-Abstract. No face.
    private static func writeIPTCJPEG(to url: URL) throws {
        let image = MetadataFixture.image(width: 64, height: 64)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = [
            kCGImagePropertyIPTCDictionary: [
                kCGImagePropertyIPTCKeywords: ["Lightroom", "test"],
                kCGImagePropertyIPTCCaptionAbstract: "Probe IPTC caption",
            ],
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Puts back what earlier probe runs left: every caption a probe wrote
    /// (`caption = nil` does **not** clear on 27.0 — only `""` does) and
    /// every `Probe…` keyword. The two IPTC imports keep theirs.
    @Test func zzCleanup() async throws {
        guard Self.canRun, #available(iOS 27, *) else { return }
        let options = PHFetchOptions()
        options.prefetchAssetExtendedMetadata = true
        let fetch = PHAsset.fetchAssets(with: options)
        var dirty: [PHAsset] = []
        fetch.enumerateObjects { asset, _, _ in
            let meta = asset.extendedMetadata
            if meta.originalFilename?.hasPrefix("lr-iptc") == true || meta.originalFilename?.hasPrefix("probe-iptc") == true { return }
            if meta.caption != nil || !meta.keywords.isEmpty { dirty.append(asset) }
        }
        try await PHPhotoLibrary.shared().performChanges {
            for asset in dirty {
                let request = PHAssetChangeRequest(for: asset)
                request.caption = ""
                for keyword in asset.extendedMetadata.keywords { request.removeKeyword(keyword) }
            }
        }
        var left = 0
        PHAsset.fetchAssets(withLocalIdentifiers: dirty.map(\.localIdentifier), options: options).enumerateObjects { asset, _, _ in
            if asset.extendedMetadata.caption != nil || !asset.extendedMetadata.keywords.isEmpty { left += 1 }
        }
        Self.log("cleanup: cleared \(dirty.count), still tagged \(left)")
    }

    /// Support for the UI proofs, not a measurement: `Sunset` on 40 photos,
    /// `Sunrise` on 12, `Sun Valley` on 3 — the library AC-3 assumes — on
    /// the oldest images, so the newest stay bare for typing into. Run on
    /// purpose with `-only-testing:…/seedSunsetLibrary()`; `zzCleanup` takes
    /// them off again.
    @Test func seedSunsetLibrary() async throws {
        guard Self.canRun, #available(iOS 27, *),
              ProcessInfo.processInfo.environment["SHOTDEX_SEED_KEYWORDS"] != nil
                || FileManager.default.fileExists(atPath: FileManager.default.temporaryDirectory.appendingPathComponent("seed-keywords").path)
        else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
        let fetch = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        fetch.enumerateObjects { asset, index, stop in
            assets.append(asset)
            if assets.count == 40 { stop.pointee = true }
        }
        try await PHPhotoLibrary.shared().performChanges {
            for (index, asset) in assets.enumerated() {
                let request = PHAssetChangeRequest(for: asset)
                request.addKeyword("Sunset")
                if index < 12 { request.addKeyword("Sunrise") }
                if index < 3 { request.addKeyword("Sun Valley") }
            }
        }
        Self.log("seeded Sunset on \(assets.count), Sunrise on \(min(12, assets.count)), Sun Valley on \(min(3, assets.count))")
    }

    /// M6 on the simulator, as far as it goes (the 55k answer needs the
    /// device): the app's own reader over every asset in pages of 1,000 —
    /// time and fetches; the footprint the pass logs is the app's.
    @Test func m6SimulatorFullRead() async throws {
        guard Self.canRun, #available(iOS 27, *) else { return }
        let all = PHAsset.fetchAssets(with: nil)
        var ids: [String] = []
        all.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        let reader = PhotoKitExtendedMetadataReader()
        let start = ContinuousClock.now
        var pages = 0
        var tagged = 0
        for offset in stride(from: 0, to: ids.count, by: 1_000) {
            let page = Array(ids[offset..<min(offset + 1_000, ids.count)])
            tagged += reader.read(ids: page).values.filter { !$0.isEmpty }.count
            pages += 1
        }
        Self.log("M6 sim: assets=\(ids.count) pages=\(pages) total=\(ContinuousClock.now - start) tagged=\(tagged)")
    }
}
