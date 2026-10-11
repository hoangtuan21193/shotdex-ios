import Foundation

/// Where one copy goes when it is deleted (FS-19.04 §1).
enum DeletionDestination: Hashable, Sendable {
    /// A Photos asset: Recently Deleted, behind the system's own dialog.
    case recentlyDeleted
    /// A file on a volume with a Trash (Finder's, or Files' Recently Deleted).
    case trash
    /// A file on a volume without one: gone, after a second red dialog.
    case permanent(sourceName: String)
    /// A file on a server source: never deleted from ShotDex, only hidden.
    case hide(sourceName: String)
}

/// What one Move / Delete / Hide of several photos does, counted by where
/// each photo goes, and the words of its confirmation (FS-19.04 §2).
struct MixedDeletionPlan: Equatable, Sendable {
    enum Selection: Sendable {
        /// Cull's Rejected batch.
        case rejected
        /// A grid selection, Duplicates, Compare.
        case photos
    }

    /// Each photo's destinations — one per copy being removed.
    let photos: [[DeletionDestination]]
    let selection: Selection
    /// "the Trash" on the Mac, "Recently Deleted in Files" elsewhere.
    var trashName = String(localized: "Recently Deleted in Files", comment: "Deletion: where a file deleted on iPad, iPhone or Duo goes")

    static let macTrashName = String(localized: "the Trash", comment: "Deletion: where a file deleted on the Mac goes")
    static let footnote = String(localized: "ShotDex never edits file contents.", comment: "Deletion confirmation: the promise under every delete")

    var count: Int { photos.count }

    /// "1 photo" / "2 photos" — grammar agreement on the counted noun.
    private static func inflected(_ text: AttributedString) -> String {
        String(text.inflected().characters)
    }

    /// Photos per destination — a photo with copies to two places counts in both.
    func count(_ destination: DeletionDestination) -> Int {
        photos.filter { $0.contains(destination) }.count
    }

    private var destinations: Set<DeletionDestination> { Set(photos.flatMap { $0 }) }
    private var hasTrash: Bool { destinations.contains(.trash) }
    private var isOnlyHide: Bool { !destinations.isEmpty && destinations.allSatisfy { if case .hide = $0 { true } else { false } } }
    private var isOnlyPhotos: Bool { destinations == [.recentlyDeleted] }
    var permanentSources: [String] { names { if case .permanent(let name) = $0 { name } else { nil } } }
    var hiddenSources: [String] { names { if case .hide(let name) = $0 { name } else { nil } } }

    private func names(_ pick: (DeletionDestination) -> String?) -> [String] {
        Array(Set(destinations.compactMap(pick))).sorted()
    }

    /// The command in menus and toolbars: named after where the photos go.
    var commandName: String {
        switch (selection, verb) {
        case (.rejected, .move): Self.inflected(AttributedString(localized: "Move ^[\(count) Rejected](inflect: true)…", comment: "Cull: deletion that sends files to the Trash"))
        case (.rejected, .delete): Self.inflected(AttributedString(localized: "Delete ^[\(count) Rejected](inflect: true)…", comment: "Cull: deletion of Photos items or of files with no Trash"))
        case (.rejected, .hide): Self.inflected(AttributedString(localized: "Hide ^[\(count) Rejected](inflect: true)…", comment: "Cull: rejected photos that are all on a server"))
        case (.photos, .move): Self.inflected(AttributedString(localized: "Move ^[\(count) Photo](inflect: true)…", comment: "Grid: deletion that sends files to the Trash"))
        case (.photos, .delete): Self.inflected(AttributedString(localized: "Delete ^[\(count) Photo](inflect: true)", comment: "Grid: deletion of Photos items or of files with no Trash"))
        case (.photos, .hide): Self.inflected(AttributedString(localized: "Hide ^[\(count) Photo](inflect: true)", comment: "Grid: photos that are all on a server"))
        }
    }

    enum Verb: Sendable { case move, delete, hide }

    var verb: Verb { hasTrash ? .move : isOnlyHide ? .hide : .delete }

    /// False when only Photos items go: the system's dialog is the only one.
    var needsConfirmation: Bool { !isOnlyPhotos && !destinations.isEmpty }

    /// True when some files cannot be recovered: a second red dialog comes
    /// first, and its Cancel runs nothing.
    var needsPermanentConfirmation: Bool { !permanentSources.isEmpty }

    var title: String {
        switch verb {
        case .hide: Self.inflected(AttributedString(localized: "Hide ^[\(count) photo](inflect: true)?", comment: "Deletion confirmation title: every photo is on a server"))
        case .move where selection == .rejected: Self.inflected(AttributedString(localized: "Move ^[\(count) rejected photo](inflect: true)?", comment: "Cull: confirmation title"))
        case .move: Self.inflected(AttributedString(localized: "Move ^[\(count) photo](inflect: true)?", comment: "Grid: confirmation title when files go to the Trash"))
        case .delete where selection == .rejected: Self.inflected(AttributedString(localized: "Delete ^[\(count) rejected photo](inflect: true)?", comment: "Cull: confirmation title"))
        case .delete: Self.inflected(AttributedString(localized: "Delete ^[\(count) photo](inflect: true)?", comment: "Grid: confirmation title"))
        }
    }

    var confirmTitle: String {
        switch verb {
        case .move: String(localized: "Move", comment: "Deletion confirmation button")
        case .delete: String(localized: "Delete", comment: "Deletion confirmation button")
        case .hide: String(localized: "Hide", comment: "Deletion confirmation button")
        }
    }

    /// "84 go to the Trash, 30 to Recently Deleted. 6 on NAS Home can't be
    /// deleted from ShotDex and will be hidden." Parts that are zero drop out.
    var message: String {
        if isOnlyHide {
            let list = hiddenSources.formatted(.list(type: .and))
            return String(localized: "Files on \(list) stay on the server; ShotDex hides them.", comment: "Deletion confirmation: every photo is on a server")
        }
        var moves: [String] = []
        let trashed = count(.trash), photosItems = count(.recentlyDeleted)
        if trashed > 0 {
            moves.append(trashed == 1
                ? String(localized: "1 goes to \(trashName)", comment: "Deletion confirmation: one file, first destination")
                : String(localized: "\(trashed) go to \(trashName)", comment: "Deletion confirmation: first destination, e.g. '84 go to the Trash'"))
        }
        if photosItems > 0 {
            moves.append(moves.isEmpty
                ? (photosItems == 1
                    ? String(localized: "1 goes to Recently Deleted", comment: "Deletion confirmation: one Photos item, first destination")
                    : String(localized: "\(photosItems) go to Recently Deleted", comment: "Deletion confirmation: Photos items, first destination"))
                : String(localized: "\(photosItems) to Recently Deleted", comment: "Deletion confirmation: Photos items after another destination"))
        }
        var sentences: [String] = moves.isEmpty ? [] : [moves.joined(separator: ", ") + "."]
        for name in permanentSources {
            let n = count(.permanent(sourceName: name))
            sentences.append(n == 1
                ? String(localized: "1 on \(name) is deleted permanently.", comment: "Deletion confirmation: one file on a volume with no Trash")
                : String(localized: "\(n) on \(name) are deleted permanently.", comment: "Deletion confirmation: files on a volume with no Trash"))
        }
        for name in hiddenSources {
            let n = count(.hide(sourceName: name))
            sentences.append(String(localized: "\(n) on \(name) can't be deleted from ShotDex and will be hidden.", comment: "Deletion confirmation: server files are hidden"))
        }
        return sentences.joined(separator: " ")
    }

    /// The second, red dialog for files that cannot be recovered (FS-19.04 §1).
    var permanentTitle: String {
        let n = photos.filter { $0.contains { if case .permanent = $0 { true } else { false } } }.count
        return Self.inflected(AttributedString(localized: "Delete ^[\(n) Photo](inflect: true) Permanently?", comment: "Deletion: second confirmation for a volume with no Trash"))
    }

    var permanentMessage: String {
        let list = permanentSources.map { "“\($0)”" }.formatted(.list(type: .and))
        let n = photos.filter { $0.contains { if case .permanent = $0 { true } else { false } } }.count
        return n == 1
            ? String(localized: "\(list) has no Trash. This file can't be recovered.", comment: "Deletion: second confirmation for one file on a volume with no Trash")
            : String(localized: "\(list) has no Trash. These files can't be recovered.", comment: "Deletion: second confirmation for a volume with no Trash")
    }
}
