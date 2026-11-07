import Foundation

/// The Library's count under its title (FS-18.02 §5): "54,027 photos ·
/// 1,204 videos" for the whole library, "212 of 55,231 photos" while a
/// filter narrows it — "items" instead when the library holds videos, since
/// the filtered line does not split them.
enum LibraryCountLine {
    /// - Parameters:
    ///   - shown: items in the grid.
    ///   - videos: how many of `shown` are videos.
    ///   - total: the whole library, when known.
    ///   - isFiltered: a filter, search or advanced query is on.
    ///   - libraryHasVideos: the whole library holds a video.
    static func text(shown: Int, videos: Int, total: Int?, isFiltered: Bool, libraryHasVideos: Bool = false) -> String {
        if isFiltered, let total {
            if libraryHasVideos {
                return total == 1
                    ? String(localized: "\(shown.formatted()) of 1 item", comment: "Mac toolbar subtitle while a filter is on: shown of a one-item library")
                    : String(localized: "\(shown.formatted()) of \(total.formatted()) items", comment: "Mac toolbar subtitle while a filter is on, library with videos: shown of all items")
            }
            return total == 1
                ? String(localized: "\(shown.formatted()) of 1 photo", comment: "Mac toolbar subtitle while a filter is on: shown of a one-photo library")
                : String(localized: "\(shown.formatted()) of \(total.formatted()) photos", comment: "Mac toolbar subtitle while a filter is on: shown of all photos")
        }
        let photos = shown - videos
        var parts: [String] = []
        // Videos alone (the Videos place) say only videos: no "0 photos".
        if photos > 0 || videos == 0 {
            parts.append(photos == 1 ? String(localized: "1 photo", comment: "Mac toolbar subtitle")
                                     : String(localized: "\(photos.formatted()) photos", comment: "Mac toolbar subtitle"))
        }
        if videos > 0 {
            parts.append(videos == 1 ? String(localized: "1 video", comment: "Mac toolbar subtitle")
                                     : String(localized: "\(videos.formatted()) videos", comment: "Mac toolbar subtitle"))
        }
        return parts.joined(separator: " · ")
    }
}

/// The Mac popover's Sort By pair (board `MAC_FilterPopover`): a field and a
/// direction, over the six orders `SortOption.menuOrders` offers.
enum LibrarySortField: String, CaseIterable, Identifiable, Sendable {
    case dateTaken
    case dateModified
    case fileSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateTaken: String(localized: "Date Taken", comment: "Mac Filter and Sort: sort by capture date")
        case .dateModified: String(localized: "Date Modified", comment: "Mac Filter and Sort: sort by modification date")
        case .fileSize: String(localized: "File Size", comment: "Mac Filter and Sort: sort by file size")
        }
    }

    /// The field of `sort`; a metric order (not in the menu) reads as Date Taken.
    init(_ sort: SortOption) {
        switch sort {
        case .dateModifiedNewest, .dateModifiedOldest: self = .dateModified
        case .fileSizeLargest, .fileSizeSmallest: self = .fileSize
        default: self = .dateTaken
        }
    }

    /// `newestFirst` is the direction toggle's "first" end: newest for a
    /// date, largest for a size.
    func sort(newestFirst: Bool) -> SortOption {
        switch self {
        case .dateTaken: newestFirst ? .dateTakenNewest : .dateTakenOldest
        case .dateModified: newestFirst ? .dateModifiedNewest : .dateModifiedOldest
        case .fileSize: newestFirst ? .fileSizeLargest : .fileSizeSmallest
        }
    }

    /// Newest (or Largest) First unless `sort` is one of the three
    /// oldest/smallest-first menu orders.
    static func isNewestFirst(_ sort: SortOption) -> Bool {
        !(sort == .dateTakenOldest || sort == .dateModifiedOldest || sort == .fileSizeSmallest)
    }
}
