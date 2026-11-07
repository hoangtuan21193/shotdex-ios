import AppKit
import SwiftUI

/// What the menu bar can do in the key library window (board `MAC_MenuBar`,
/// FS-18.01b §2): the window publishes it as a focused scene value, so with
/// two library windows each menu command acts on the front one.
struct MacLibraryTarget {
    var hasSelection: Bool
    var showsInspector: Bool
    var sort: SortOption
    var quickLook: () -> Void
    var showInFinder: () -> Void
    var toggleFavorite: () -> Void
    var rate: (Int) -> Void
    var flag: (PhotoFlag?) -> Void
    var moveToTrash: () -> Void
    var hide: () -> Void
    var advancedSearch: () -> Void
    var toggleInspector: () -> Void
    var setSort: (SortOption) -> Void
}

/// Go's way into the front window, whatever it shows (Backup, a server).
struct MacGoTarget {
    var go: (MacSidebarItem) -> Void
    /// On This Day's Choose Date…, nil on any other place.
    var chooseDate: (() -> Void)?
}

extension FocusedValues {
    @Entry var macLibrary: MacLibraryTarget?
    @Entry var macGo: MacGoTarget?
    /// The viewer's zoom while a photo is open (View › Zoom to Fit / Actual Size).
    @Entry var macViewerZoom: Binding<MacViewerZoom>?
}

/// The menu bar's library commands: Image (marks, Quick Look, Show in
/// Finder, Move to Trash), Edit (Deselect All, Advanced Search…), View
/// (Sort By, Show Inspector; Filter and Sort… is `MacFilterCommands`) and
/// Go's places. A command with nothing to act on is off, never silent.
struct MacLibraryCommands: Commands {
    @FocusedValue(\.macLibrary) private var library
    @FocusedValue(\.macViewerZoom) private var viewerZoom

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            // Select All ⌘A is the grid's or list's own; this is its pair.
            Button(String(localized: "Deselect All", comment: "Mac menu: Edit › Deselect All")) {
                NSApp.sendAction(Selector(("deselectAll:")), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(library?.hasSelection != true)
            Button(String(localized: "Advanced Search…", comment: "Mac menu: Edit › Advanced Search…")) { library?.advancedSearch() }
                .disabled(library == nil)
        }
        CommandGroup(after: .toolbar) {
            Picker(String(localized: "Sort By", comment: "Mac menu: View › Sort By"), selection: Binding(
                get: { library?.sort ?? .dateTakenNewest },
                set: { library?.setSort($0) }
            )) {
                ForEach(SortOption.menuOrders) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .disabled(library == nil)
            Divider()
            Button(library?.showsInspector == true ? String(localized: "Hide Inspector", comment: "Mac menu: View › Hide Inspector")
                                                   : String(localized: "Show Inspector", comment: "Mac menu: View › Show Inspector")) {
                library?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(library == nil)
            Divider()
            // The viewer's zoom, as Photos: ⌘0 fits, ⌘9 is one pixel per pixel; off while the grid shows.
            Button(String(localized: "Zoom to Fit", comment: "Mac menu: View › Zoom to Fit (viewer)")) { viewerZoom?.wrappedValue = .fit }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(viewerZoom == nil)
            Button(String(localized: "Actual Size", comment: "Mac menu: View › Actual Size (viewer)")) { viewerZoom?.wrappedValue = .actual }
                .keyboardShortcut("9", modifiers: .command)
                .disabled(viewerZoom == nil)
        }
        CommandGroup(after: .newItem) {
            Divider()
            Button(String(localized: "Show in Finder", comment: "Mac menu: File › Show in Finder")) { library?.showInFinder() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(library?.hasSelection != true)
        }
    }
}

/// Image's marks and actions on the selection (FS-18.01b §2). The single
/// keys (. Favorite, 0–5, P, X, U) are the grid's and list's own
/// (`MacPhotoMenu.markKey`): a menu key equivalent without ⌘ would not
/// reach the menu from the grid, and would take letters typed in search.
struct MacImageCommands: Commands {
    @FocusedValue(\.macLibrary) private var library
    @FocusedValue(\.macHidden) private var hidden

    var body: some Commands {
        CommandMenu(String(localized: "Image", comment: "Mac menu bar: Image menu")) {
            Button(String(localized: "Quick Look", comment: "Mac menu: Image › Quick Look")) { library?.quickLook() }
                .keyboardShortcut("y", modifiers: .command)
                .disabled(library?.hasSelection != true)
            Button(String(localized: "Get Info", comment: "Mac menu: Image › Get Info")) {
                NotificationCenter.default.post(name: .macGetInfo, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)
            Divider()
            Button(String(localized: "Favorite", comment: "Mac menu: Image › Favorite")) { library?.toggleFavorite() }
                .disabled(library?.hasSelection != true)
            Menu(String(localized: "Rating", comment: "Mac menu: Image › Rating")) {
                ForEach(0...5, id: \.self) { stars in
                    Button(PhotoMarkMenuTitles.rating(stars)) { library?.rate(stars) }
                }
            }
            .disabled(library?.hasSelection != true)
            Button(MarkCopy.pick) { library?.flag(.pick) }
                .disabled(library?.hasSelection != true)
            Button(MarkCopy.reject) { library?.flag(.reject) }
                .disabled(library?.hasSelection != true)
            Button(MarkCopy.clearFlag) { library?.flag(nil) }
                .disabled(library?.hasSelection != true)
            Divider()
            // ⌘L hides; in Collections › Hidden it unhides (board `MAC_Hidden`).
            if let hidden {
                Button(hidden.count == 0 ? String(localized: "Unhide", comment: "Mac Hidden: the Unhide button with nothing selected")
                       : hidden.count == 1 ? String(localized: "Unhide 1 Photo", comment: "Mac Hidden: unhide the selected photo")
                                         : String(localized: "Unhide \(hidden.count) Photos", comment: "Mac Hidden: unhide the selected photos (0 or more than 1)"),
                       action: hidden.unhide)
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(hidden.count == 0)
            } else {
                Button(String(localized: "Hide…", comment: "Mac menu: Image › Hide… (asks how)")) { library?.hide() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(library?.hasSelection != true)
            }
            Button(String(localized: "Move to Trash", comment: "Mac menu: Image › Move to Trash")) {
                // ⌘⌫ in a text field is its own: delete to the line's start.
                if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
                    text.deleteToBeginningOfLine(nil)
                } else if library?.hasSelection == true {
                    library?.moveToTrash()
                } else {
                    NSSound.beep()
                }
            }
                .keyboardShortcut(.delete, modifiers: .command)
                // Never off: a disabled item still claims ⌘⌫ from a text field.
        }
    }
}

/// Go: every sidebar place, ⌥⌘1…⌥⌘6 on the first six (FS-18.01b §2).
struct MacGoCommands: Commands {
    @FocusedValue(\.macGo) private var target

    private static let places: [MacSidebarItem] = MacSidebarItem.library + [.statistics]
    private static let more: [MacSidebarItem] = [.onThisDay, .albums, .duplicates, .collages, .videoProjects, .onServer]

    var body: some Commands {
        CommandMenu(String(localized: "Go", comment: "Mac menu bar: Go menu")) {
            ForEach(Array(Self.places.enumerated()), id: \.offset) { index, item in
                Button(item.title) { target?.go(item) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.option, .command])
                    .disabled(target == nil)
            }
            Divider()
            Button(String(localized: "Backup", comment: "Mac menu: Go › Backup")) {
                NotificationCenter.default.post(name: .macShowBackup, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.option, .command])
            ForEach(Self.more, id: \.id) { item in
                Button(item.title) { target?.go(item) }
                    .disabled(target == nil)
            }
            Divider()
            // The keyboard's way to another day (no shortcut: ⌥⌘D is the Dock's).
            Button(String(localized: "Choose Date…", comment: "Mac menu: Go › Choose Date… (On This Day)")) { target?.chooseDate?() }
                .disabled(target?.chooseDate == nil)
        }
    }
}
