import Foundation

/// The browser's Sort menu (FS-17.01 §2), remembered per connection.
enum ServerPhotoSort: String, CaseIterable, Identifiable, Sendable {
    case name
    case dateTaken
    case dateModified
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: String(localized: "Name", comment: "Server photo browser sort: file name")
        case .dateTaken: String(localized: "Date Taken", comment: "Server photo browser sort: EXIF capture date")
        case .dateModified: String(localized: "Date Modified", comment: "Server photo browser sort: file write date")
        case .size: String(localized: "Size", comment: "Server photo browser sort: file size")
        }
    }

    /// The direction a sort starts in, as in Files: names A to Z, dates and
    /// sizes newest or largest first.
    var defaultAscending: Bool { self == .name }

    /// Orders `photos`. Date Taken falls back to the write date for a photo
    /// whose capture date is unknown; photos with no date at all go last;
    /// ties go by name, so the order never shuffles between two reads.
    func sorted(_ photos: [ServerPhoto], ascending: Bool, captureDates: [String: Date] = [:]) -> [ServerPhoto] {
        func byName(_ lhs: ServerPhoto, _ rhs: ServerPhoto) -> Bool {
            lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        func date(_ photo: ServerPhoto) -> Date? {
            switch self {
            case .name: nil
            case .dateTaken: captureDates[photo.id] ?? photo.modified
            case .dateModified: photo.modified
            case .size: nil
            }
        }
        if self == .name {
            let ordered = photos.sorted(by: byName)
            return ascending ? ordered : ordered.reversed()
        }
        if self == .size {
            return photos.sorted { lhs, rhs in
                if lhs.totalBytes != rhs.totalBytes {
                    return ascending ? lhs.totalBytes < rhs.totalBytes : lhs.totalBytes > rhs.totalBytes
                }
                return byName(lhs, rhs)
            }
        }
        let dated = photos.filter { date($0) != nil }.sorted { lhs, rhs in
            let left = date(lhs)!, right = date(rhs)!
            if left != right { return ascending ? left < right : left > right }
            return byName(lhs, rhs)
        }
        return dated + photos.filter { date($0) == nil }.sorted(by: byName)
    }
}
