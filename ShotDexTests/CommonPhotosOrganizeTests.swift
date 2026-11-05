import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ShotDex

/// FS-19.08 §6e Organize: a Common Photos run files each photo the way a
/// Backup does — by the date it was taken (or its folder's, or its write
/// time), or by the folder it has in the first folder (Same as Source).
@Suite struct CommonPhotosOrganizeTests {
    private static let utc = TimeZone(identifier: "UTC")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day)
    }

    private static func components(_ date: Date?) -> DateComponents? {
        date.map { calendar.dateComponents([.year, .month, .day], from: $0) }
    }

    /// A small JPEG whose EXIF says it was taken at `taken`
    /// (`2025:10:12 14:03:27`), padded so it is not three samples long.
    static func jpeg(taken: String, padding: Int = 0) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: taken],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data + Data(repeating: 0x5A, count: padding)
    }

    // MARK: Dates

    @Test func folderNamesADate() {
        let cal = Self.calendar
        #expect(Self.components(CommonPhotosOrganizeDate.folderDate("2025/03/15", calendar: cal)) == Self.day(2025, 3, 15))
        #expect(Self.components(CommonPhotosOrganizeDate.folderDate("Trip/2025-03-15", calendar: cal)) == Self.day(2025, 3, 15))
        #expect(Self.components(CommonPhotosOrganizeDate.folderDate("20250315", calendar: cal)) == Self.day(2025, 3, 15))
        #expect(Self.components(CommonPhotosOrganizeDate.folderDate("2025/3", calendar: cal)) == Self.day(2025, 3, 1))
        // The deepest folder wins.
        #expect(Self.components(CommonPhotosOrganizeDate.folderDate("2024/01/01/2025.03.15", calendar: cal)) == Self.day(2025, 3, 15))
        #expect(CommonPhotosOrganizeDate.folderDate("Trip", calendar: cal) == nil)
        #expect(CommonPhotosOrganizeDate.folderDate("2025/13/40", calendar: cal) == nil)
        // No 30 February: the month folder above it names the 1st.
        #expect(Self.components(CommonPhotosOrganizeDate.folderDate("2025/02/30", calendar: cal)) == Self.day(2025, 2, 1))
        #expect(CommonPhotosOrganizeDate.folderDate("IMG-20250315", calendar: cal) == nil)
        #expect(CommonPhotosOrganizeDate.folderDate("", calendar: cal) == nil)
    }

    /// Taken beats the folder, the folder beats the write time.
    @Test func dateOrder() {
        let taken = Date(timeIntervalSince1970: 1_760_277_807)
        let written = Date(timeIntervalSince1970: 1_722_470_400)
        #expect(CommonPhotosOrganizeDate.date(taken: taken, folder: "2025/03/15", modified: written, calendar: Self.calendar) == taken)
        #expect(Self.components(CommonPhotosOrganizeDate.date(taken: nil, folder: "2025/03/15", modified: written, calendar: Self.calendar))
                == Self.day(2025, 3, 15))
        #expect(CommonPhotosOrganizeDate.date(taken: nil, folder: "Trip", modified: written, calendar: Self.calendar) == written)
        #expect(CommonPhotosOrganizeDate.date(taken: nil, folder: "Trip", modified: nil, calendar: Self.calendar) == nil)
    }

    // MARK: Placement

    @Test func sameAsSourceKeepsTheFirstFoldersSubfolders() {
        var organize = BackupOrganize()
        organize.levels = .sameAsSource
        organize.videoPlacement = .together
        let names = BackupDateName(calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        let date = Date()
        #expect(CommonPhotosPlacement.relativePath(organize: organize, sourcePath: "photos/Tuấn/2025/03/15/X.CR3", firstFolder: "photos/Tuấn",
                                                   date: date, names: names) == "2025/03/15/X.CR3")
        // At the first folder's top: the photo's own name — no placement.
        #expect(CommonPhotosPlacement.relativePath(organize: organize, sourcePath: "photos/Tuấn/X.CR3", firstFolder: "photos/Tuấn",
                                                   date: date, names: names) == nil)
        // A folder name Windows refuses is mended as Backup mends it; `..` never climbs.
        #expect(CommonPhotosPlacement.relativePath(organize: organize, sourcePath: "photos/Tuấn/Trip. /a:b/X.CR3", firstFolder: "photos/Tuấn",
                                                   date: date, names: names) == "Trip/a-b/X.CR3")
        #expect(CommonPhotosPlacement.relativePath(organize: organize, sourcePath: "photos/Tuấn/../X.CR3", firstFolder: "photos/Tuấn",
                                                   date: date, names: names) == "-/X.CR3")
        organize.levels = .noFolders
        #expect(CommonPhotosPlacement.relativePath(organize: organize, sourcePath: "photos/Tuấn/2025/X.CR3", firstFolder: "photos/Tuấn",
                                                   date: date, names: names) == nil)
        #expect(!CommonPhotosPlacement.needsDate(organize))
        organize.fileNames = .dateAndTime
        #expect(CommonPhotosPlacement.needsDate(organize))
    }

    @Test func safeFolderNames() {
        #expect(BackupDateName.safeFolderName("Trip. ") == "Trip")
        #expect(BackupDateName.safeFolderName("..") == "-")
        #expect(BackupDateName.safeFolderName(".") == "-")
        #expect(BackupDateName.safeFolderName("a*b") == "a-b")
        #expect(BackupDateName.safeFolderName("con") == "con-")
        #expect(BackupDateName.safeFolderName("COM1.old") == "COM1.old-")
        #expect(BackupDateName.safeFolderName("Console") == "Console")
    }

    /// Backup's Organize never offers Same as Source; Common Photos' never
    /// offers Album.
    @Test func levelLists() {
        #expect(!BackupOrganize.Levels.backup.contains(.sameAsSource))
        #expect(BackupOrganize.Levels.commonPhotos.first == .sameAsSource)
        #expect(!BackupOrganize.Levels.commonPhotos.contains(.album))
        #expect(BackupPathPlanner.videoPlacements(for: .sameAsSource) == [.together, .apartAtTop])
    }

    // MARK: Runs

    private func run(_ nas: InMemoryRemoteFileClient, organize: BackupOrganize, action: CommonPhotosRun.Action = .copy)
        async throws -> (CommonPhotosStore, Int) {
        let folders = ["photos/Tuấn", "photos/Vợ"]
        let listing = try await CommonPhotosScanner(client: nas).list(folders)
        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: folders)
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        var run = CommonPhotosRun(id: "R", connectionId: "nas", folders: folders, destination: "photos/Shared", action: action)
        run.organize = organize
        try store.start(run, items: CommonPhotosRunner.items(for: photos, runId: "R", folders: folders,
                                                            files: listing.files, sidecars: listing.sidecars))
        let readsBefore = nas.rangeReadPaths.count
        var runner = CommonPhotosRunner(client: nas, store: store,
                                        workDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("Organize-\(UUID().uuidString)"))
        runner.timeZone = Self.utc
        runner.locale = Locale(identifier: "en_US")
        try await runner.run("R")
        return (store, readsBefore)
    }

    private static var yearMonthDay: BackupOrganize {
        var organize = BackupOrganize()
        organize.levels = .yearMonthDay
        organize.monthStyle = .abbreviated
        organize.dayStyle = .dotted
        organize.videoPlacement = .apartAtTop
        return organize
    }

    /// AC-204 + AC-205: the photo by its EXIF date, the video by its
    /// folder's — its head never read for it; a video in `Trip/` by its
    /// write time.
    @Test func filesByDate() async throws {
        let nas = InMemoryRemoteFileClient()
        let photo = try Self.jpeg(taken: "2025:10:12 14:03:27")
        let movie = CommonPhotosQuickCheckTests.photo(7)
        let trip = CommonPhotosQuickCheckTests.photo(8, count: 290_000)
        for folder in ["photos/Tuấn", "photos/Vợ"] {
            nas.put("\(folder)/2025/10/12/IMG_8812.JPG", photo)
            nas.put("\(folder)/2025/03/15/IMG_8813.MOV", movie)
            nas.put("\(folder)/Trip/IMG_9000.MOV", trip)
        }
        nas.modified["photos/Tuấn/Trip/IMG_9000.MOV"] = Date(timeIntervalSince1970: 1_722_513_600) // 2024-08-01 12:00 UTC

        let (store, readsBefore) = try await run(nas, organize: Self.yearMonthDay)

        #expect(nas.files["photos/Shared/2025/Oct/2025.10.12/IMG_8812.JPG"] == photo)
        #expect(nas.files["photos/Shared/Videos/2025/Mar/2025.03.15/IMG_8813.MOV"] == movie)
        #expect(nas.files["photos/Shared/Videos/2024/Aug/2024.08.01/IMG_9000.MOV"] == trip)
        let runReads = nas.rangeReadPaths.dropFirst(readsBefore)
        #expect(Array(runReads) == ["photos/Tuấn/2025/10/12/IMG_8812.JPG"])
        let items = try store.items(runId: "R")
        #expect(items.allSatisfy { $0.status == .copied })
        #expect(Set(items.compactMap(\.placement)) == ["2025/Oct/2025.10.12/IMG_8812.JPG", "Videos/2025/Mar/2025.03.15/IMG_8813.MOV",
                                                      "Videos/2024/Aug/2024.08.01/IMG_9000.MOV"])
        // The log stays at the destination's top.
        #expect(nas.files.keys.contains { $0.hasPrefix("photos/Shared/ShotDex Common Photos ") && $0.hasSuffix(".csv") })
    }

    /// AC-206: File Names Date and Time, the name taken in that day's folder
    /// by other bytes — the next free name there, nothing written over.
    @Test func dateNamesTakeTheNextFreeName() async throws {
        let nas = InMemoryRemoteFileClient()
        let photo = try Self.jpeg(taken: "2025:10:12 14:03:27")
        for folder in ["photos/Tuấn", "photos/Vợ"] { nas.put("\(folder)/IMG_8812.HEIC", photo) }
        let other = Data("someone else's".utf8)
        nas.put("photos/Shared/2025/Oct/2025.10.12/2025-10-12 14.03.27.HEIC", other)
        var organize = Self.yearMonthDay
        organize.fileNames = .dateAndTime

        _ = try await run(nas, organize: organize)

        #expect(nas.files["photos/Shared/2025/Oct/2025.10.12/2025-10-12 14.03.27.HEIC"] == other)
        #expect(nas.files["photos/Shared/2025/Oct/2025.10.12/2025-10-12 14.03.27 (2).HEIC"] == photo)
    }

    /// AC-226: Same as Source — the same name on two days lands on two
    /// days; a folder Windows refuses (`Trip. `) is mended, not a failure.
    @Test func sameAsSourceRun() async throws {
        let nas = InMemoryRemoteFileClient()
        let raw = CommonPhotosQuickCheckTests.photo(11)
        let jpeg = CommonPhotosQuickCheckTests.photo(12, count: 280_000)
        let trip = CommonPhotosQuickCheckTests.photo(13, count: 270_000)
        for folder in ["photos/Tuấn", "photos/Vợ"] {
            nas.put("\(folder)/2025/03/15/X.CR3", raw)
            nas.put("\(folder)/2025/03/16/X.JPG", jpeg)
        }
        nas.put("photos/Tuấn/Trip. /Y.JPG", trip)
        nas.put("photos/Vợ/Y.JPG", trip)
        var organize = BackupOrganize()
        organize.levels = .sameAsSource

        let (store, _) = try await run(nas, organize: organize)

        #expect(nas.files["photos/Shared/2025/03/15/X.CR3"] == raw)
        #expect(nas.files["photos/Shared/2025/03/16/X.JPG"] == jpeg)
        #expect(nas.files["photos/Shared/Trip/Y.JPG"] == trip)
        #expect(try store.items(runId: "R").allSatisfy { $0.status == .copied })
    }

    /// AC-207 (the run's half): the same bytes already in the day folder —
    /// Skipped there; the same bytes at the destination's top do not count.
    @Test func alreadyThereIsJudgedInTheFolderFiledTo() async throws {
        let nas = InMemoryRemoteFileClient()
        let raw = CommonPhotosQuickCheckTests.photo(21)
        for folder in ["photos/Tuấn", "photos/Vợ"] { nas.put("\(folder)/2025/03/15/X.ARW", raw) }
        nas.put("photos/Shared/X.ARW", raw)
        var organize = BackupOrganize()
        organize.levels = .sameAsSource

        let (store, _) = try await run(nas, organize: organize)
        let item = try #require(try store.items(runId: "R").first)
        #expect(item.status == .copied)
        #expect(item.destinationPath == "photos/Shared/2025/03/15/X.ARW")

        nas.put("photos/Tuấn/2025/03/15/Z.ARW", CommonPhotosQuickCheckTests.photo(22))
        nas.put("photos/Vợ/2025/03/15/Z.ARW", CommonPhotosQuickCheckTests.photo(22))
        nas.put("photos/Shared/2025/03/15/Z.ARW", CommonPhotosQuickCheckTests.photo(22))
        let (second, _) = try await run(nas, organize: organize)
        let z = try #require(try second.items(runId: "R").first { $0.sources.first?.path.hasSuffix("Z.ARW") == true })
        #expect(z.status == .skipped)
        #expect(z.destinationPath == "photos/Shared/2025/03/15/Z.ARW")
    }

    /// A Move renames into the day folder, made first.
    @Test func moveFilesIntoTheFolder() async throws {
        let nas = InMemoryRemoteFileClient()
        let raw = CommonPhotosQuickCheckTests.photo(31)
        for folder in ["photos/Tuấn", "photos/Vợ"] { nas.put("\(folder)/2025/03/15/X.ARW", raw) }
        var organize = BackupOrganize()
        organize.levels = .sameAsSource

        let (store, _) = try await run(nas, organize: organize, action: .move)

        #expect(nas.files["photos/Shared/2025/03/15/X.ARW"] == raw)
        #expect(nas.files["photos/Tuấn/2025/03/15/X.ARW"] == nil)
        #expect(nas.files["photos/Vợ/2025/03/15/X.ARW"] == nil)
        #expect(try store.items(runId: "R").first?.status == .moved)
    }

    /// A Move whose second folder sits inside the destination, at the very
    /// folder Organize files the photo to: that copy is the destination's —
    /// already there, kept; only the first folder's goes.
    @Test func moveKeepsACopyAtTheDestinationsTop() async throws {
        let nas = InMemoryRemoteFileClient()
        let raw = CommonPhotosQuickCheckTests.photo(41)
        nas.put("photos/Tuấn/2025/03/15/X.ARW", raw)
        nas.put("photos/Shared/2025/03/15/X.ARW", raw)
        let folders = ["photos/Tuấn", "photos/Shared/2025/03/15"]
        let listing = try await CommonPhotosScanner(client: nas).list(folders)
        let photos = try await CommonPhotosVerifier(client: nas).verify(CommonPhotosMatcher.preview(listing.files), folders: folders)
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        var run = CommonPhotosRun(id: "R", connectionId: "nas", folders: folders, destination: "photos/Shared", action: .move)
        run.organize = { var o = BackupOrganize(); o.levels = .sameAsSource; return o }()
        try store.start(run, items: CommonPhotosRunner.items(for: photos, runId: "R", folders: folders,
                                                            files: listing.files, sidecars: listing.sidecars))
        try await CommonPhotosRunner(client: nas, store: store,
                                     workDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("Organize-\(UUID().uuidString)")).run("R")

        #expect(nas.files["photos/Shared/2025/03/15/X.ARW"] == raw)
        #expect(nas.files["photos/Tuấn/2025/03/15/X.ARW"] == nil)
        #expect(try store.items(runId: "R").first?.status == .moved)
    }

    /// An Organize the app cannot read makes the run Discard only.
    @Test func unreadableOrganizeIsDiscardOnly() throws {
        let database = try AppDatabase.makeEmpty()
        let store = CommonPhotosStore(database: database)
        try store.start(CommonPhotosRun(id: "R", connectionId: "nas", folders: ["A", "B"], destination: "C", action: .copy), items: [])
        try database.writer.write { try $0.execute(sql: "UPDATE common_photo_runs SET organize = '{bad' WHERE id = 'R'") }
        let run = try #require(try store.run(id: "R"))
        #expect(!run.isReadable)
        #expect(!run.canResume)
    }

    /// A run with no Organize files at the top, as before §6e; the run's
    /// Organize survives the database.
    @Test func organizeIsStored() throws {
        let store = CommonPhotosStore(database: try AppDatabase.makeEmpty())
        var run = CommonPhotosRun(id: "R", connectionId: "nas", folders: ["A", "B"], destination: "C", action: .copy)
        run.organize = Self.yearMonthDay
        var item = CommonPhotosItem(runId: "R", position: 0, sha256: "x", size: 1,
                                    sources: [.init(path: "A/1.JPG", size: 1, modifiedAt: nil, sidecar: nil)])
        item.placement = "2025/Oct/2025.10.12/1.JPG"
        try store.start(run, items: [item])
        #expect(try store.run(id: "R")?.organize == Self.yearMonthDay)
        #expect(try store.items(runId: "R").first?.placement == "2025/Oct/2025.10.12/1.JPG")
    }
}
