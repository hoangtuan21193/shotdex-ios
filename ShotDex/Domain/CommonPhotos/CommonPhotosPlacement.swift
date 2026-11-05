import Foundation

/// Where a Common Photos run's Organize files a photo under the
/// destination (FS-19.08 §6e): Backup's planner, fed with what a server
/// folder knows — the date from `CommonPhotosOrganizeDate`, and for Same
/// as Source the folders the photo sits in under the first folder.
enum CommonPhotosPlacement {
    /// Whether filing needs the photo's date — the date levels, or a file
    /// name made from it.
    static func needsDate(_ organize: BackupOrganize) -> Bool {
        ![.sameAsSource, .noFolders, .album].contains(organize.levels) || organize.fileNames != .original
    }

    /// The folders `path` sits in under `firstFolder`, `/`-separated; "" at
    /// its top or outside it.
    static func sourceFolder(of path: String, firstFolder: String) -> String {
        let parent = ServerUploadPath.parent(of: path)
        let root = firstFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmed = parent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard trimmed.lowercased().hasPrefix(root.lowercased() + "/") else { return "" }
        return String(trimmed.dropFirst(root.count + 1))
    }

    /// Where `organize` files a photo whose first copy is `sourcePath`,
    /// reading what it needs from the server: when filing needs a date, the
    /// capture date in the head of a photo (never a video's, which is not
    /// read for it), else the date its folder names, else its write time,
    /// else now. A head that cannot be read is no date, not a failure; a
    /// server gone away throws. Dates in folder names are read in the
    /// Gregorian calendar; names are written in this Mac's, as Backup's are.
    static func place(sourcePath: String, size: Int64, modifiedAt: Int?, organize: BackupOrganize, firstFolder: String,
                      client: any RemoteFileClient, timeZone: TimeZone, locale: Locale, now: Date) async throws -> String? {
        let date = needsDate(organize)
            ? try await self.date(sourcePath: sourcePath, size: size, modifiedAt: modifiedAt, firstFolder: firstFolder,
                                  client: client, timeZone: timeZone) ?? now
            : now
        return relativePath(organize: organize, sourcePath: sourcePath, firstFolder: firstFolder, date: date,
                            names: names(timeZone: timeZone, locale: locale))
    }

    /// The date a photo is filed by, read from the server as `place` reads
    /// it; nil when nothing gives one. Which Organize asks does not change
    /// it, so a plan keeps it while the user tries levels.
    static func date(sourcePath: String, size: Int64, modifiedAt: Int?, firstFolder: String,
                     client: any RemoteFileClient, timeZone: TimeZone) async throws -> Date? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        var taken: Date?
        if !PairingRule.isMovie(ServerUploadPath.lastComponent(of: sourcePath)) {
            do {
                let head = try await client.readRange(sourcePath, offset: 0, length: Int(min(size, Int64(EmbeddedPreview.firstRead))))
                taken = EmbeddedPreview.captureDate(from: head, timeZone: timeZone)
            } catch let error as RemoteFileError where !error.stopsBatch {
                taken = nil
            }
        }
        let modified = modifiedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        return CommonPhotosOrganizeDate.date(taken: taken, folder: sourceFolder(of: sourcePath, firstFolder: firstFolder),
                                             modified: modified, calendar: gregorian)
    }

    /// Folder names in this Mac's calendar and `locale`, as Backup writes them.
    static func names(timeZone: TimeZone, locale: Locale) -> BackupDateName {
        var calendar = Calendar.current
        calendar.timeZone = timeZone
        return BackupDateName(calendar: calendar, locale: locale)
    }

    /// The path under the destination; nil when that is the photo's own
    /// name at the top — what a run without Organize does.
    static func relativePath(organize: BackupOrganize, sourcePath: String, firstFolder: String, date: Date,
                             names: BackupDateName) -> String? {
        let name = ServerUploadPath.lastComponent(of: sourcePath)
        let input = BackupPlacementInput(
            date: date, isVideo: PairingRule.isMovie(name), originalFilename: name,
            isRAW: FileTypeBadge.isRAW(filename: name),
            sourceFolder: sourceFolder(of: sourcePath, firstFolder: firstFolder))
        let path = BackupPathPlanner(organize: organize, names: names).relativePath(for: input)
        return path == name ? nil : path
    }
}
