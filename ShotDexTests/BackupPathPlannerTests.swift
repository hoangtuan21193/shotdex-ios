import Foundation
import Testing
@testable import ShotDex

/// Organize → destination path (FS-22.01 §3–§5).
@Suite struct BackupPathPlannerTests {
    private static let names: BackupDateName = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return BackupDateName(calendar: calendar, locale: Locale(identifier: "en_US"))
    }()

    /// 2025-10-12 14:03:27 UTC.
    private static let taken = Date(timeIntervalSince1970: 1_760_277_807)

    private func planner(_ edit: (inout BackupOrganize) -> Void = { _ in }) -> BackupPathPlanner {
        var organize = BackupOrganize()
        edit(&organize)
        return BackupPathPlanner(organize: organize, names: Self.names)
    }

    private func photo(_ name: String = "IMG_1.HEIC", album: String? = nil) -> BackupPlacementInput {
        BackupPlacementInput(date: Self.taken, isVideo: false, originalFilename: name, album: album)
    }

    private func video(_ name: String = "IMG_2.MOV", album: String? = nil) -> BackupPlacementInput {
        BackupPlacementInput(date: Self.taken, isVideo: true, originalFilename: name, album: album)
    }

    /// AC-4: the defaults — Year › Month › Day, Oct, 2025.10.12, videos apart
    /// at the top.
    @Test func yearMonthDayVideosAtTop() {
        let p = planner()
        #expect(p.relativePath(for: photo()) == "2025/Oct/2025.10.12/IMG_1.HEIC")
        #expect(p.relativePath(for: video()) == "Videos/2025/Oct/2025.10.12/IMG_2.MOV")
    }

    /// AC-5: every level × file-name style × offered video placement gives
    /// the table's path, and no folder name holds a `/`.
    @Test func everyCombinationMatchesTable() {
        let photoFolders: [BackupOrganize.Levels: [String]] = [
            .yearMonthDay: ["2025", "Oct", "2025.10.12"],
            .yearMonth: ["2025", "Oct"],
            .yearDate: ["2025", "2025.10.12"],
            .dateOnly: ["2025.10.12"],
            .album: ["Trip"],
            .noFolders: [],
        ]
        let fileNames: [BackupOrganize.FileNames: (photo: String, video: String)] = [
            .original: ("IMG_1.HEIC", "IMG_2.MOV"),
            .dateAndTime: ("2025-10-12 14.03.27.HEIC", "2025-10-12 14.03.27.MOV"),
            .dateAndOriginal: ("2025-10-12 14.03.27 IMG_1.HEIC", "2025-10-12 14.03.27 IMG_2.MOV"),
        ]
        var checked = 0
        for levels in BackupOrganize.Levels.allCases {
            for style in BackupOrganize.FileNames.allCases {
                for placement in BackupPathPlanner.videoPlacements(for: levels) {
                    let p = planner {
                        $0.levels = levels
                        $0.fileNames = style
                        $0.videoPlacement = placement
                    }
                    let folders = photoFolders[levels]!
                    let expectedPhoto = (folders + [fileNames[style]!.photo]).joined(separator: "/")
                    var videoFolders = folders
                    switch placement {
                    case .together: break
                    case .apartAtTop: videoFolders.insert("Videos", at: 0)
                    case .apartInYear: videoFolders.insert("Videos", at: 1)
                    case .apartInMonth: videoFolders.insert("Videos", at: 2)
                    case .apartInDay: videoFolders.append("Videos")
                    }
                    let expectedVideo = (videoFolders + [fileNames[style]!.video]).joined(separator: "/")

                    #expect(p.relativePath(for: photo(album: "Trip")) == expectedPhoto, "\(levels) \(style) \(placement)")
                    #expect(p.relativePath(for: video(album: "Trip")) == expectedVideo, "\(levels) \(style) \(placement)")
                    #expect(p.folders(for: video(album: "Trip")).allSatisfy { !$0.contains("/") })
                    checked += 1
                }
            }
        }
        #expect(checked == 3 * (5 + 4 + 4 + 3 + 2 + 2))
    }

    @Test func monthAndDayStylesAreTheirExamples() {
        let months: [BackupOrganize.MonthStyle: String] = [
            .number: "10", .yearMonth: "2025-10", .abbreviated: "Oct", .name: "October",
            .kanji: "10月", .vietnamese: "Tháng 10",
        ]
        for (style, expected) in months {
            #expect(planner { $0.monthStyle = style }.folders(for: photo())[1] == expected)
        }
        let days: [BackupOrganize.DayStyle: String] = [
            .dashed: "2025-10-12", .dotted: "2025.10.12", .underscored: "2025_10_12", .compact: "20251012", .dayOnly: "12",
        ]
        for (style, expected) in days {
            #expect(planner { $0.dayStyle = style }.folders(for: photo())[2] == expected)
        }
        #expect(planner { $0.yearStyle = .short }.folders(for: photo())[0] == "25")
    }

    /// An album named with a slash or a colon is still one folder.
    @Test func albumNameNeverSplitsAFolder() {
        let p = planner { $0.levels = .album }
        #expect(p.relativePath(for: photo(album: "Tokyo/Kyoto: 2025")) == "Tokyo-Kyoto- 2025/IMG_1.HEIC")
        #expect(p.relativePath(for: photo(album: nil)) == "Unfiled/IMG_1.HEIC")
    }

    /// A placement the levels do not offer falls back to the top.
    @Test func unofferedPlacementFallsBackToTop() {
        let p = planner {
            $0.levels = .noFolders
            $0.videoPlacement = .apartInDay
        }
        #expect(p.relativePath(for: video()) == "Videos/IMG_2.MOV")
    }

    /// Every file of an item shares a stem; the edited render adds `_edited`.
    @Test func editedVersionKeepsStemAndAddsSuffix() {
        var edited = photo("IMG_5.JPG")
        edited.isEditedVersion = true
        #expect(planner().fileName(for: edited) == "IMG_5_edited.JPG")
        #expect(planner { $0.fileNames = .dateAndTime }.fileName(for: edited) == "2025-10-12 14.03.27_edited.JPG")
    }

    /// RAW files take the same placements as videos: at the top, or a RAW
    /// folder inside each year, month or the photos' own day folder.
    @Test func rawFolderPlacements() {
        var raw = photo("IMG_1.CR3")
        raw.isRAW = true
        #expect(planner().relativePath(for: raw) == "2025/Oct/2025.10.12/IMG_1.CR3")
        #expect(planner { $0.rawPlacement = .apartAtTop }.relativePath(for: raw) == "RAW/2025/Oct/2025.10.12/IMG_1.CR3")
        #expect(planner { $0.rawPlacement = .apartInMonth }.relativePath(for: raw) == "2025/Oct/RAW/2025.10.12/IMG_1.CR3")
        #expect(planner { $0.rawPlacement = .apartInDay }.relativePath(for: raw) == "2025/Oct/2025.10.12/RAW/IMG_1.CR3")
        // The JPEG of the pair stays with the photos.
        #expect(planner { $0.rawPlacement = .apartInDay }.relativePath(for: photo("IMG_1.JPG")) == "2025/Oct/2025.10.12/IMG_1.JPG")
    }

    /// The Organize preview merges a photo, its RAW and a video into one tree.
    @Test @MainActor func previewTreeShowsPhotoRawAndVideo() {
        var organize = BackupOrganize()
        organize.rawPlacement = .apartInDay
        let rows = BackupPreviewTree.rows(organize: organize)
        let names = rows.map(\.name)
        #expect(names.contains("IMG_8812.CR3"))
        #expect(names.contains("RAW"))
        #expect(names.contains("Videos"))
        #expect(rows.filter { !$0.isFolder }.count == 3)
    }
}
