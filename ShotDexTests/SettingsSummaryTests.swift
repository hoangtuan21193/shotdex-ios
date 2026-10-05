import Foundation
import ShotDexKit
import Testing
@testable import ShotDex

/// The value lines under Settings rows (FS-08.01b §1–2) and the library card.
/// Numbers stay under 1,000 so the expectations do not depend on the
/// simulator's grouping separator.
struct SettingsSummaryTests {

    // MARK: Library and viewing

    /// Access, then the network condition indexing runs under (AC-3).
    @Test func photoLibraryLineFollowsAccessAndCellular() {
        #expect(SettingsSummary.photoLibrary(access: .authorized, allowsCellular: false)
            == "Full Access · indexing on Wi-Fi only")
        #expect(SettingsSummary.photoLibrary(access: .authorized, allowsCellular: true)
            == "Full Access · indexing on Wi-Fi and cellular")
        // AC-6: limited access says so.
        #expect(SettingsSummary.photoLibrary(access: .limited, allowsCellular: false)
            == "Limited Access · indexing on Wi-Fi only")
        // Without access there is no indexing to describe.
        #expect(SettingsSummary.photoLibrary(access: .denied, allowsCellular: true) == "Denied")
    }

    @Test func accessRowSaysWhatTheAccessCovers() {
        #expect(SettingsSummary.accessDetail(.authorized) == "Full Access · every photo and video")
        #expect(SettingsSummary.accessDetail(.limited) == "Limited Access · only the photos you picked")
    }

    /// The thumbnail details in grid order, the first one capitalised.
    @Test func displayLineListsWhatThumbnailsShow() {
        #expect(SettingsSummary.display(
            showsISO: true, showsAperture: true, showsShutterSpeed: false,
            showsFocalLength: true, showsMegapixels: false, showsFileSize: false,
            showsFileType: true
        ) == "ISO, aperture, focal length, file type")
        #expect(SettingsSummary.display(
            showsISO: false, showsAperture: true, showsShutterSpeed: false,
            showsFocalLength: false, showsMegapixels: false, showsFileSize: true,
            showsFileType: false
        ) == "Aperture, file size")
        #expect(SettingsSummary.display(
            showsISO: false, showsAperture: false, showsShutterSpeed: false,
            showsFocalLength: false, showsMegapixels: false, showsFileSize: false,
            showsFileType: false
        ) == "Thumbnails show the photo only")
    }

    @Test func playbackLineNamesBothSwitches() {
        #expect(SettingsSummary.playback(autoplaysVideos: true, viewsFullHDR: false)
            == "Autoplay on · Full HDR off")
        #expect(SettingsSummary.playback(autoplaysVideos: false, viewsFullHDR: true)
            == "Autoplay off · Full HDR on")
    }

    @Test func subjectScanLineCountsScannedPhotos() {
        #expect(SettingsSummary.subjectScan(scanned: 418, total: 552, scanningPercent: nil)
            == "418 of 552 photos scanned")
        #expect(SettingsSummary.subjectScan(scanned: 552, total: 552, scanningPercent: nil)
            == "Every photo scanned")
        #expect(SettingsSummary.subjectScan(scanned: 0, total: 552, scanningPercent: nil)
            == "Not scanned yet")
        #expect(SettingsSummary.subjectScan(scanned: 0, total: 0, scanningPercent: nil)
            == "No photos yet")
        #expect(SettingsSummary.subjectScan(scanned: 10, total: 552, scanningPercent: 64)
            == "Scanning · 64%")
        // The sidebar's short form is the percentage.
        #expect(SettingsSummary.subjectScanShort(scanned: 418, total: 552, scanningPercent: nil) == "75%")
        #expect(SettingsSummary.subjectScanShort(scanned: 0, total: 552, scanningPercent: nil) == nil)
    }

    @Test func cameraDatabaseLineCountsUnknownCameras() {
        #expect(SettingsSummary.cameraDatabase(unknownCameras: 6) == "6 cameras need a sensor format")
        #expect(SettingsSummary.cameraDatabase(unknownCameras: 1) == "1 camera needs a sensor format")
        #expect(SettingsSummary.cameraDatabase(unknownCameras: 0) == "Every camera is known")
        #expect(SettingsSummary.cameraDatabaseShort(unknownCameras: 6) == "6 unknown")
        #expect(SettingsSummary.cameraDatabaseShort(unknownCameras: 0) == nil)
    }

    // MARK: Sharing and export

    @Test func metadataLineNamesTheDefaultLevel() {
        #expect(SettingsSummary.metadataWhenSharing(.all) == "All Metadata · each share can change it")
        #expect(SettingsSummary.metadataWhenSharing(.noLocation) == "No Location · each share can change it")
    }

    /// AC-7's wording: "4 built-in · 3 custom"; no custom half until there is one.
    @Test func resizePresetsLineCountsBothKinds() {
        #expect(SettingsSummary.resizePresets(builtIn: 4, custom: 3) == "4 built-in · 3 custom")
        #expect(SettingsSummary.resizePresets(builtIn: 4, custom: 0) == "4 built-in")
        #expect(ResizePreset.builtIns.count == 4)
    }

    /// The first two names, then a count of the rest.
    @Test func fileServersLineNamesTheFirstTwo() {
        #expect(SettingsSummary.fileServers(names: []) == "None yet")
        #expect(SettingsSummary.fileServers(names: ["Studio NAS"]) == "Studio NAS")
        #expect(SettingsSummary.fileServers(names: ["Studio NAS", "MacBook Pro"])
            == "Studio NAS and MacBook Pro")
        #expect(SettingsSummary.fileServers(names: ["Studio NAS", "MacBook Pro", "Archive"])
            == "Studio NAS, MacBook Pro and 1 more")
        #expect(SettingsSummary.fileServers(names: ["Studio NAS", "MacBook Pro", "Archive", "Backup"])
            == "Studio NAS, MacBook Pro and 2 more")
    }

    // MARK: Widgets and notifications

    @Test func widgetsLineCountsDesigns() {
        #expect(SettingsSummary.widgets(designCount: 3) == "Photo widget · 3 designs")
        #expect(SettingsSummary.widgetsShort(designCount: 1) == "1 design")
    }

    @Test func notificationsLineSaysWhenTheReminderFires() {
        #expect(SettingsSummary.notifications(isReminderOn: true, isDenied: false, time: "9:00 AM")
            == "On This Day reminder at 9:00 AM")
        #expect(SettingsSummary.notifications(isReminderOn: false, isDenied: false, time: "9:00 AM") == "Off")
        #expect(SettingsSummary.notificationsShort(isReminderOn: true, isDenied: false, time: "9:00 AM") == "9:00 AM")
        // A reminder iOS will not deliver is not "on".
        #expect(SettingsSummary.notificationsShort(isReminderOn: true, isDenied: true, time: "9:00 AM") == "Off")
    }

    // MARK: The library card

    private func status(
        access: PhotoAuthorizationState = .authorized,
        photos: Int = 500, videos: Int = 20,
        read: Int, total: Int,
        indexing: Bool = false, run: Double? = nil,
        last: Date? = nil, now: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> SettingsLibraryStatus {
        SettingsLibraryStatus(.init(
            access: access, photoCount: photos, videoCount: videos,
            readCount: read, totalCount: total,
            isIndexing: indexing, runFraction: run, lastIndexedAt: last
        ), now: now, locale: Locale(identifier: "en_US"))
    }

    /// Fully read: counts with "indexed", a full green bar, and how long ago.
    @Test func cardWhenUpToDate() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let card = status(read: 520, total: 520, last: now.addingTimeInterval(-125), now: now)
        #expect(card.counts == "500 photos · 20 videos · indexed")
        #expect(card.fraction == 1)
        #expect(card.isComplete)
        #expect(card.status == "Up to date · 2 min. ago")
        #expect(status(read: 520, total: 520, last: now.addingTimeInterval(-5), now: now).status
            == "Up to date · just now")
    }

    /// AC-4: a run at 64% says so, and the bar follows the run.
    @Test func cardWhileIndexing() {
        let card = status(read: 100, total: 520, indexing: true, run: 0.64)
        #expect(card.status == "Reading photo info · 64%")
        #expect(abs(card.fraction - 0.64) < 0.02)
        #expect(card.isComplete == false)
        #expect(card.counts == "500 photos · 20 videos")
    }

    /// A run that stopped part-way shows how far it got.
    @Test func cardWhenPartlyRead() {
        let card = status(read: 130, total: 520)
        #expect(card.status == "130 of 520 read")
        #expect(abs(card.fraction - 0.25) < 0.001)
    }

    @Test func cardBeforeTheFirstIndexAndWithoutAccess() {
        #expect(status(photos: 0, videos: 0, read: 0, total: 0).status == "Not indexed yet")
        #expect(status(access: .denied, read: 0, total: 0).status == "ShotDex has no access to your photos")
    }

    /// One photo is "1 photo", not "1 photos".
    @Test func cardCountsAgreeInNumber() {
        #expect(status(photos: 1, videos: 1, read: 2, total: 2).counts == "1 photo · 1 video · indexed")
    }
}
