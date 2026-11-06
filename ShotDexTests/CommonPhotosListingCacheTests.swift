import Foundation
import Testing
@testable import ShotDex

/// FS-19.08 §6e: a rescan lists only the day folders that changed.
@Suite struct CommonPhotosListingCacheTests {
    /// When the folders were last written; the first scan lists a minute later.
    static let start = Date(timeIntervalSince1970: 1_790_000_000)
    static let firstScan = start.addingTimeInterval(60)

    /// `A` and `B` each `2025/<month>/<day>/`: 2 months × 5 days, one photo a
    /// day, every folder with a write time.
    private static func nas(subfolderIn day: String? = nil, folderTimes: Bool = true) -> InMemoryRemoteFileClient {
        let nas = InMemoryRemoteFileClient()
        for side in ["A", "B"] {
            for month in ["03", "04"] {
                for day in 10..<15 {
                    let folder = "\(side)/2025/\(month)/\(day)"
                    nas.put("\(folder)/IMG_\(month)\(day).JPG", Data(repeating: UInt8(day), count: 100 + day))
                    if folderTimes { nas.folderModified[folder] = start }
                }
                if folderTimes { nas.folderModified["\(side)/2025/\(month)"] = start }
            }
            if folderTimes { nas.folderModified["\(side)/2025"] = start }
        }
        if let day {
            nas.put("A/2025/03/\(day)/edited/IMG_E.JPG", Data([9]))
            if folderTimes { nas.folderModified["A/2025/03/\(day)/edited"] = start }
        }
        return nas
    }

    private func listings(_ database: AppDatabase, at date: Date) -> CommonPhotosFolderListings {
        CommonPhotosFolderListings(database: database, connectionId: "nas", now: { date })
    }

    /// Folders listed per side: root, year, 2 months, 10 days.
    static let fullListing = (1 + 1 + 2 + 10) * 2

    /// AC-198: a rescan within the day lists root, year and months on each
    /// side, plus the one day folder whose time moved — and finds the new
    /// file; every other file comes from the last listing.
    @Test func rescanListsOnlyTheChangedDay() async throws {
        let nas = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let scanner = CommonPhotosScanner(client: nas)
        _ = try await scanner.list(["A", "B"], listings: listings(database, at: Self.firstScan))
        #expect(nas.listingCount == Self.fullListing)

        nas.put("A/2025/03/12/IMG_NEW.JPG", Data(repeating: 1, count: 500))
        nas.folderModified["A/2025/03/12"] = Self.start.addingTimeInterval(60)
        let before = nas.listingCount
        let again = try await scanner.list(["A", "B"], listings: listings(database, at: Self.start.addingTimeInterval(3_600)))

        #expect(nas.listingCount - before == (1 + 1 + 2) * 2 + 1)
        #expect(again.files[0].contains { $0.relativePath == "2025/03/12/IMG_NEW.JPG" })
        #expect(again.files[0].count == 11)
        #expect(again.files[1].count == 10)
    }

    /// AC-199: a day folder with a folder of its own is listed every time —
    /// a change inside that folder never reaches the day's time. The folder
    /// itself, a leaf whose time the day's fresh listing gives, is reused
    /// while that time holds and listed once it moves.
    @Test func dayWithASubfolderIsListed() async throws {
        let nas = Self.nas(subfolderIn: "13")
        let database = try AppDatabase.makeEmpty()
        let scanner = CommonPhotosScanner(client: nas)
        _ = try await scanner.list(["A", "B"], listings: listings(database, at: Self.firstScan))
        let before = nas.listingCount
        _ = try await scanner.list(["A", "B"], listings: listings(database, at: Self.start.addingTimeInterval(60)))
        #expect(nas.listingCount - before == (1 + 1 + 2) * 2 + 1)

        nas.put("A/2025/03/13/edited/IMG_E2.JPG", Data([8]))
        nas.folderModified["A/2025/03/13/edited"] = Self.start.addingTimeInterval(120)
        let again = nas.listingCount
        let listing = try await scanner.list(["A", "B"], listings: listings(database, at: Self.start.addingTimeInterval(180)))
        #expect(nas.listingCount - again == (1 + 1 + 2) * 2 + 2)
        #expect(listing.files[0].contains { $0.relativePath == "2025/03/13/edited/IMG_E2.JPG" })
    }

    /// AC-200: no folder times from the server, or a listing older than a
    /// day: every folder is listed again.
    @Test func noTimesOrOldListingsListEverything() async throws {
        let untimed = Self.nas(folderTimes: false)
        let database = try AppDatabase.makeEmpty()
        _ = try await CommonPhotosScanner(client: untimed).list(["A", "B"], listings: listings(database, at: Self.firstScan))
        let before = untimed.listingCount
        _ = try await CommonPhotosScanner(client: untimed).list(["A", "B"], listings: listings(database, at: Self.start.addingTimeInterval(60)))
        #expect(untimed.listingCount - before == Self.fullListing)

        let timed = Self.nas()
        let other = try AppDatabase.makeEmpty()
        _ = try await CommonPhotosScanner(client: timed).list(["A", "B"], listings: listings(other, at: Self.firstScan))
        let earlier = timed.listingCount
        _ = try await CommonPhotosScanner(client: timed).list(["A", "B"], listings: listings(other, at: Self.firstScan.addingTimeInterval(25 * 3_600)))
        #expect(timed.listingCount - earlier == Self.fullListing)
    }

    /// AC-200 (Scan Everything) + AC-221: the sheet lists every folder for
    /// Scan Everything; a rescan lists root, year and months only, for a
    /// Move as for a Copy — the run asks each copy again before it acts.
    @Test @MainActor func scanEverythingListsEverything() async throws {
        let nas = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let sheet = CommonPhotosScanModel(connectionId: "nas", sourceId: "source", folders: ["A", "B"], client: nas, database: database)
        await sheet.scanToEnd()
        var before = nas.listingCount
        await sheet.scanToEnd()
        #expect(nas.listingCount - before == (1 + 1 + 2) * 2)

        before = nas.listingCount
        await sheet.scanToEnd(everything: true)
        #expect(nas.listingCount - before == Self.fullListing)

        sheet.action = .move
        before = nas.listingCount
        await sheet.scanToEnd()
        #expect(nas.listingCount - before == (1 + 1 + 2) * 2)
    }

    /// A folder written seconds before it was listed is not kept: a file
    /// added in that same second would not move its time.
    @Test func justWrittenFoldersAreNotKept() async throws {
        let nas = Self.nas()
        let database = try AppDatabase.makeEmpty()
        let scanner = CommonPhotosScanner(client: nas)
        _ = try await scanner.list(["A", "B"], listings: listings(database, at: Self.start.addingTimeInterval(1)))
        let before = nas.listingCount
        _ = try await scanner.list(["A", "B"], listings: listings(database, at: Self.start.addingTimeInterval(120)))
        #expect(nas.listingCount - before == Self.fullListing)
    }

    /// Rows not listed for a week go when the next scan writes.
    @Test func weekOldRowsGo() async throws {
        let database = try AppDatabase.makeEmpty()
        let old = listings(database, at: Self.firstScan)
        _ = try await CommonPhotosScanner(client: Self.nas()).list(["A", "B"], listings: old)
        #expect(try old.listed("A/2025/03/10") != nil)
        let later = listings(database, at: Self.firstScan.addingTimeInterval(8 * 24 * 3_600))
        _ = try await CommonPhotosScanner(client: InMemoryRemoteFileClient()).list(["Z"], listings: later)
        #expect(try later.listed("A/2025/03/10") == nil)
    }

    /// The rule on its own.
    @Test func reuseRule() {
        let listed = CommonPhotosListingCache.Listed(folderModified: Int(Self.start.timeIntervalSince1970), hasSubfolders: false,
                                                     entries: [], listedAt: Self.start)
        let later = Self.start.addingTimeInterval(60)
        #expect(CommonPhotosListingCache.reuses(listed, folderModified: Self.start, now: later))
        #expect(!CommonPhotosListingCache.reuses(listed, folderModified: Self.start.addingTimeInterval(1), now: later))
        #expect(!CommonPhotosListingCache.reuses(listed, folderModified: nil, now: later))
        #expect(!CommonPhotosListingCache.reuses(nil, folderModified: Self.start, now: later))
        var nested = listed
        nested.hasSubfolders = true
        #expect(!CommonPhotosListingCache.reuses(nested, folderModified: Self.start, now: later))
        #expect(!CommonPhotosListingCache.reuses(listed, folderModified: Self.start, now: Self.start.addingTimeInterval(24 * 3_600)))
    }
}
