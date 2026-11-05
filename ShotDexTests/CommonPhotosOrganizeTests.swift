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

/// FS-19.08 §6e Organize as a set carries it: the sheet's default, the
/// plan's paths, the note after a change, Undo's empty folders, Keep
/// gathering's runs.
@Suite(.serialized) @MainActor struct CommonPhotosOrganizeSetTests {
    private static let folders = ["photos/Tuấn", "photos/Vợ"]

    private static func waitForPlan(_ sheet: CommonPhotosScanModel) async throws {
        sheet.scan()
        for _ in 0..<600 where sheet.phase != .done || sheet.isCutting || sheet.isPlanning {
            if case .failed(let message) = sheet.phase { Issue.record("scan failed: \(message)"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(sheet.phase == .done)
    }

    private static func sheet(_ nas: InMemoryRemoteFileClient, _ database: AppDatabase) -> CommonPhotosScanModel {
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: folders, client: nas, database: database)
        sheet.destination = "photos/Shared"
        return sheet
    }

    private static func run(_ made: (run: CommonPhotosRun, items: [CommonPhotosItem]), nas: InMemoryRemoteFileClient,
                            database: AppDatabase) async throws -> CommonPhotosStore {
        let store = CommonPhotosStore(database: database)
        try store.start(made.run, items: made.items)
        try await CommonPhotosRunner(client: nas, store: store,
                                     workDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("OrganizeSet-\(UUID().uuidString)"))
            .run(made.run.id)
        return store
    }

    /// AC-202: a new set starts at Same as Source; its plan names the full
    /// path and the run puts the photo there.
    @Test func newSetIsSameAsSource() async throws {
        let nas = InMemoryRemoteFileClient()
        let raw = CommonPhotosQuickCheckTests.photo(51)
        nas.put("photos/Tuấn/2025/03/15/X.ARW", raw)
        nas.put("photos/Vợ/x/X.ARW", raw)
        let database = try AppDatabase.makeEmpty()
        let sheet = Self.sheet(nas, database)
        #expect(sheet.organize == CommonPhotosScanModel.newSetOrganize)
        #expect(BackupOrganizeText.summary(sheet.organize).hasPrefix("Same as Source"))

        try await Self.waitForPlan(sheet)

        #expect(sheet.rows.first?.landing == .name("2025/03/15/X.ARW"))
        let made = try #require(sheet.makeRun())
        #expect(made.run.organize == CommonPhotosScanModel.newSetOrganize)
        #expect(made.items.first?.placement == "2025/03/15/X.ARW")
        _ = try await Self.run(made, nas: nas, database: database)
        #expect(nas.files["photos/Shared/2025/03/15/X.ARW"] == raw)
    }

    /// AC-203 + AC-208: a set that ran flat before §6e keeps No Folders;
    /// changed to Same as Source, the sheet says the photos gathered stay,
    /// nothing is done with them, and the new photo goes into its folder.
    @Test func oldSetStaysFlatAndAChangeIsForNewPhotos() async throws {
        let nas = InMemoryRemoteFileClient()
        let old = CommonPhotosQuickCheckTests.photo(61)
        nas.put("photos/Tuấn/2025/03/15/OLD.ARW", old)
        nas.put("photos/Vợ/2025/03/15/OLD.ARW", old)
        let database = try AppDatabase.makeEmpty()
        // The run before §6e: no Organize, the photo at the top.
        let first = Self.sheet(nas, database)
        first.organize = CommonPhotosScanModel.flatOrganize
        try await Self.waitForPlan(first)
        var made = try #require(first.makeRun())
        made.run.organize = nil
        _ = try await Self.run(made, nas: nas, database: database)
        #expect(nas.files["photos/Shared/OLD.ARW"] == old)

        let fresh = CommonPhotosQuickCheckTests.photo(62)
        nas.put("photos/Tuấn/2025/03/16/NEW.ARW", fresh)
        nas.put("photos/Vợ/2025/03/16/NEW.ARW", fresh)
        let sheet = Self.sheet(nas, database)
        #expect(sheet.organize == CommonPhotosScanModel.flatOrganize)
        try await Self.waitForPlan(sheet)
        #expect(sheet.alreadyGathered == 1)
        #expect(!sheet.organizeAffectsNewOnly)
        sheet.organize = CommonPhotosScanModel.newSetOrganize
        #expect(sheet.organizeAffectsNewOnly)
        for _ in 0..<300 where sheet.isPlanning || sheet.landings.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(sheet.rows.map(\.name) == ["NEW.ARW"])
        #expect(sheet.rows.first?.landing == .name("2025/03/16/NEW.ARW"))
        let before = nas.commands.count
        _ = try await Self.run(try #require(sheet.makeRun()), nas: nas, database: database)
        #expect(nas.files["photos/Shared/2025/03/16/NEW.ARW"] == fresh)
        #expect(nas.files["photos/Shared/OLD.ARW"] == old)
        #expect(!nas.commands.dropFirst(before).contains { $0.contains("OLD.ARW") })

        // Gathered in a folder, it is still gathered: not offered again.
        let again = Self.sheet(nas, database)
        try await Self.waitForPlan(again)
        #expect(again.rows.isEmpty)
        #expect(again.alreadyGathered == 2)
    }

    /// AC-209: Undo takes the photos back and the folders the run made with
    /// them, when nothing else is in them — deepest first; a folder holding
    /// the user's `note.txt` stays, and so does what is above it.
    @Test func undoRemovesTheEmptyFoldersItMade() async throws {
        let nas = InMemoryRemoteFileClient()
        for (index, day) in ["15", "15", "16"].enumerated() {
            let bytes = CommonPhotosQuickCheckTests.photo(UInt8(70 + index))
            nas.put("photos/Tuấn/2025/03/\(day)/P\(index).ARW", bytes)
            nas.put("photos/Vợ/2025/03/\(day)/P\(index).ARW", bytes)
        }
        let database = try AppDatabase.makeEmpty()
        let sheet = Self.sheet(nas, database)
        try await Self.waitForPlan(sheet)
        let made = try #require(sheet.makeRun())
        let store = try await Self.run(made, nas: nas, database: database)
        #expect(Set(try #require(try store.run(id: made.run.id)).createdFolders)
                == ["2025", "2025/03", "2025/03/15", "2025/03/16"])
        nas.put("photos/Shared/2025/03/16/note.txt", Data("mine".utf8))

        let undo = try store.startUndo(of: made.run.id)
        try await CommonPhotosUndoer(client: nas, store: store,
                                     workDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("OrganizeUndo-\(UUID().uuidString)"))
            .run(undo.id)

        #expect(try await !nas.directoryExists("photos/Shared/2025/03/15"))
        #expect(try await nas.directoryExists("photos/Shared/2025/03/16"))
        #expect(nas.files["photos/Shared/2025/03/16/note.txt"] != nil)
        #expect(try await nas.directoryExists("photos/Shared/2025/03"))
        #expect(!nas.files.keys.contains { $0.hasSuffix(".ARW") && $0.hasPrefix("photos/Shared/") })
    }

    /// AC-210: Keep gathering's pass files new photos as the set does —
    /// here Year › Month, from the set's last run.
    @Test func gatherUsesTheSetsOrganize() async throws {
        let nas = InMemoryRemoteFileClient()
        let first = CommonPhotosQuickCheckTests.photo(81)
        nas.put("photos/Tuấn/2025/03/15/A.ARW", first)
        nas.put("photos/Vợ/2025/03/15/A.ARW", first)
        let database = try AppDatabase.makeEmpty()
        let sheet = Self.sheet(nas, database)
        var yearMonth = CommonPhotosScanModel.newSetOrganize
        yearMonth.levels = .yearMonth
        yearMonth.monthStyle = .number
        sheet.organize = yearMonth
        try await Self.waitForPlan(sheet)
        _ = try await Self.run(try #require(sheet.makeRun()), nas: nas, database: database)

        for (index, name) in ["B.ARW", "C.ARW"].enumerated() {
            let bytes = CommonPhotosQuickCheckTests.photo(UInt8(82 + index))
            nas.put("photos/Tuấn/2025/04/02/\(name)", bytes)
            nas.put("photos/Vợ/2025/04/02/\(name)", bytes)
        }
        // As the pass does: a scan with no sheet, no plan.
        let pass = Self.sheet(nas, database)
        #expect(pass.organize == yearMonth)
        await pass.scanToEnd()
        let made = try #require(pass.makeRun())
        #expect(made.items.count == 2)
        #expect(made.run.organize == yearMonth)
        _ = try await Self.run(made, nas: nas, database: database)
        #expect(nas.files["photos/Shared/2025/04/B.ARW"] != nil)
        #expect(nas.files["photos/Shared/2025/04/C.ARW"] != nil)
    }
}
