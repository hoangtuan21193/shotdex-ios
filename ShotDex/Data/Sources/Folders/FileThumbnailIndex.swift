import Foundation
import GRDB
import UIKit

/// Grid thumbnails of photos that are not in Photos (FS-19.01b §5): which
/// cached file stands for each photo, kept in memory so a cell never asks
/// the database while scrolling, and the decoded images in a bounded cache.
final class FileThumbnailIndex: @unchecked Sendable {
    let thumbnails: FolderThumbnails
    private let lock = NSLock()
    private var copyByPhoto: [String: String] = [:]
    /// Photos whose only copies are cloud placeholders (FS-19.01b §4): the
    /// tile draws the cloud glyph and the file's name instead of a picture.
    private var cloudOnly: Set<String> = []
    private let images = NSCache<NSString, UIImage>()

    init(thumbnails: FolderThumbnails = .standard) {
        self.thumbnails = thumbnails
        images.countLimit = 600
    }

    /// Photos with no Photos copy, and the copy whose thumbnail they show —
    /// the first in copy order that has one written.
    func reload(_ database: AppDatabase) {
        let rows = (try? database.reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT c.photoId, c.id FROM photo_copies c JOIN sources s ON s.id = c.sourceId
                WHERE c.kind != 'photos' AND c.missingSince IS NULL
                  AND NOT EXISTS (SELECT 1 FROM photo_copies p WHERE p.photoId = c.photoId AND p.kind = 'photos' AND p.missingSince IS NULL)
                ORDER BY CASE s.kind WHEN 'folder' THEN 0 WHEN 'drive' THEN 1 ELSE 2 END, c.rowid
                """).map { ($0["photoId"] as String, $0["id"] as String) }
        }) ?? []
        var map: [String: String] = [:]
        for (photo, copy) in rows where map[photo] == nil
            && FileManager.default.fileExists(atPath: thumbnails.url(copyId: copy).path) {
            map[photo] = copy
        }
        let placeholders = (try? database.reader.read { db in
            try String.fetchSet(db, sql: """
                SELECT c.photoId FROM photo_copies c
                WHERE c.isCloudPlaceholder = 1 AND c.missingSince IS NULL
                  AND NOT EXISTS (SELECT 1 FROM photo_copies o WHERE o.photoId = c.photoId AND o.isCloudPlaceholder = 0 AND o.missingSince IS NULL)
                """)
        }) ?? []
        lock.withLock {
            copyByPhoto = map
            cloudOnly = placeholders
        }
    }

    func isCloudPlaceholder(_ photoId: String) -> Bool {
        lock.withLock { cloudOnly.contains(photoId) }
    }

    func hasThumbnail(for photoId: String) -> Bool {
        lock.withLock { copyByPhoto[photoId] != nil }
    }

    /// The cached image, decoded once; nil when the photo has none yet.
    func image(for photoId: String) -> UIImage? {
        guard let copy = lock.withLock({ copyByPhoto[photoId] }) else { return nil }
        if let cached = images.object(forKey: copy as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: thumbnails.url(copyId: copy).path)?.preparingForDisplay() else { return nil }
        images.setObject(image, forKey: copy as NSString)
        return image
    }
}
