import SwiftUI

/// Collections → Network: one folder on a server (FS-17.04).
struct ServerShortcutRoute: Hashable {
    let id: String
}

/// A Network tile: the album tile's shape and title band, the cover kept on
/// this device, and a server glyph top-right that says "folder on a
/// server", not "album" (FS-17.04 §2).
struct NetworkShortcutTile: View {
    let shortcut: ServerShortcut
    let connectionName: String

    var body: some View {
        AlbumCoverTile(
            title: shortcut.name,
            accessibilityLabel: String(localized: "\(shortcut.name), folder on \(connectionName)", comment: "VoiceOver label for a Network tile in Collections"),
            needsScrim: shortcut.coverJPEG != nil
        ) {
            AlbumCoverWell(image: shortcut.coverJPEG.flatMap(UIImage.init(data:)), systemImage: "folder")
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "externaldrive.connected.to.line.below")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
        }
    }
}
