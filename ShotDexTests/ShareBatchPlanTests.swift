import Foundation
import Photos
import ShotDexKit
import Testing
@testable import ShotDex

/// FS-08.06 §4 — the share sheet's header line and the app's two rows.
struct ShareBatchPlanTests {

    /// AC-7: at No Location the header says so and the two rows are the two
    /// other levels; the level in force has no row.
    @Test func rowsAndSubtitle() {
        let plan = ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 0)
        #expect(plan.subtitle == .locationRemoved)
        #expect(plan.rows == [.all, .noMetadata])
        #expect(ShareLevelRow.title(for: .all) == "Share With Location")
        #expect(ShareLevelRow.title(for: .noMetadata) == "Share Without Metadata")

        let all = ShareBatchPlan(level: .all, photoCount: 3, videoCount: 0)
        #expect(all.subtitle == .allMetadata)
        #expect(all.rows == [.noLocation, .noMetadata])
        #expect(ShareLevelRow.title(for: .noLocation) == "Share Without Location")

        let none = ShareBatchPlan(level: .noMetadata, photoCount: 2, videoCount: 0)
        #expect(none.subtitle == .metadataRemoved)
        #expect(none.rows == [.all, .noLocation])
        for plan in [plan, all, none] { #expect(plan.rows.count == 2) }
    }

    /// FS-05.04 §4: the watermark leads the header's second line, joined to
    /// the other notes by " · "; no watermark, no segment.
    @Test func watermarkNote() {
        var plan = ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 1)
        #expect(PhotoShareSheet.headerNote(plan: plan) == "Videos keep their metadata")
        plan.watermarkName = "Credit"
        #expect(PhotoShareSheet.headerNote(plan: plan)?.hasPrefix("Watermark: Credit · Videos keep their metadata") == true)
        #expect(ShareBatchPlan(level: .all, photoCount: 0, videoCount: 1, watermarkName: "Credit").watermarkNote == nil)
    }

    /// Video goes as it is at every level, so a share of only videos has no
    /// level to change.
    @Test func videosOnlyHaveNoRows() {
        #expect(ShareBatchPlan(level: .noLocation, photoCount: 0, videoCount: 2).rows.isEmpty)
    }

    /// AC-20 (and the Settings half of AC-2): a row changes this share only.
    /// Nothing in the share path writes the Settings level — the only
    /// writers are the Settings picker and the one-time carry-over of the
    /// old switch — and a row's choice reaches the gather as an argument.
    @Test func oneShotOverrideKeepsSettings() throws {
        let root = AssetMetadataCarryOverTests.repository.appendingPathComponent("ShotDex")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var writers: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            if text.contains("SettingsKeys.shareMetadataLevel") { writers.append(file.lastPathComponent) }
        }
        #expect(Set(writers) == ["SettingsKeys.swift", "SettingsScreen.swift"], "\(writers)")

        let sheet = try AssetMetadataCarryOverTests.codeLines(of: "ShotDex/Features/Shared/PhotoShareSheet.swift")
            .joined(separator: "\n")
        #expect(sheet.contains("let again = await regather(level)"))
        #expect(!sheet.contains("UserDefaults"))
    }

    /// AC-6 / AC-7: the header adds "Videos keep their metadata" only when
    /// the share has a video and the level removes something.
    @Test func videoNote() {
        #expect(ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 1).notesVideosKeepMetadata)
        #expect(ShareBatchPlan(level: .noMetadata, photoCount: 1, videoCount: 2).notesVideosKeepMetadata)
        #expect(!ShareBatchPlan(level: .all, photoCount: 1, videoCount: 1).notesVideosKeepMetadata)
        #expect(!ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 0).notesVideosKeepMetadata)
    }

    /// AC-9: two ARW and photo A at No Location — one question for the
    /// share, naming two RAW files and the location.
    @Test func rawAlertOnce() {
        let sources = [
            ShareSource(id: "1", kind: .raw, filename: "DSC00001.ARW"),
            ShareSource(id: "2", kind: .raw, filename: "DSC00002.ARW"),
            ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC"),
        ]
        let plan = ShareBatchPlan(sources: sources, level: .noLocation)
        #expect(plan.asksAboutRAW)
        #expect(plan.rawQuestion == .init(count: 2, removes: .location))
        #expect(plan.offersJPEG)
        #expect(ShareBatchPlan(sources: sources, level: .noMetadata).rawQuestion.removes == .metadata)
        // All Metadata hands RAW over as it is: nothing to ask.
        #expect(!ShareBatchPlan(sources: sources, level: .all).asksAboutRAW)
        #expect(!ShareBatchPlan(sources: [sources[2]], level: .noLocation).asksAboutRAW)
    }

    /// FS-03.04b: a RAW this device cannot decode has no JPEG to offer.
    @Test func unreadableRAWDimsShareAsJPEG() {
        let sources = [
            ShareSource(id: "1", kind: .raw, filename: "DSC00001.ARW", isReadable: false),
            ShareSource(id: "A", kind: .photo, filename: "IMG_0001.HEIC"),
        ]
        let plan = ShareBatchPlan(sources: sources, level: .noLocation)
        #expect(plan.asksAboutRAW)
        #expect(!plan.offersJPEG)
    }

    /// A RAW-only photo is told apart from its edited rendering by the type
    /// of the resource that would be shared.
    @Test func rawIsRecognisedByTheSharedResource() {
        #expect(ShareSource.kind(mediaType: .image, sharedType: "com.sony.arw-raw-image") == .raw)
        #expect(ShareSource.kind(mediaType: .image, sharedType: "com.fuji.raw-image") == .raw)
        #expect(ShareSource.kind(mediaType: .image, sharedType: "com.adobe.raw-image") == .raw)
        #expect(ShareSource.kind(mediaType: .image, sharedType: "public.heic") == .photo)
        #expect(ShareSource.kind(mediaType: .image, sharedType: "public.jpeg") == .photo)
        #expect(ShareSource.kind(mediaType: .video, sharedType: nil) == .video)
    }

    /// AC-16: after Share RAW with Location the header must not claim the
    /// location is gone without saying the RAW files keep it.
    @Test func headerOwnsUpToWhatKeepsItsMetadata() {
        var plan = ShareBatchPlan(level: .noLocation, photoCount: 3, videoCount: 0, rawSharedAsIsCount: 2)
        #expect(plan.keepsNote == .raw)
        plan = ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 1, rawSharedAsIsCount: 1)
        #expect(plan.keepsNote == .videosAndRAW)
        #expect(ShareBatchPlan(level: .noMetadata, photoCount: 1, videoCount: 1).keepsNote == .videos)
        #expect(ShareBatchPlan(level: .noLocation, photoCount: 1, videoCount: 0).keepsNote == nil)
        #expect(ShareBatchPlan(level: .all, photoCount: 1, videoCount: 1, rawSharedAsIsCount: 1).keepsNote == nil)
    }

    /// AC-2: a HEIC sent as JPEG is said on the header's second line.
    @Test func heicAsJPEGIsSaid() {
        #expect(ShareBatchPlan(level: .noMetadata, photoCount: 2, videoCount: 0, heicAsJPEGCount: 1).notesHEICAsJPEG)
        #expect(!ShareBatchPlan(level: .noMetadata, photoCount: 2, videoCount: 0).notesHEICAsJPEG)
    }
}
