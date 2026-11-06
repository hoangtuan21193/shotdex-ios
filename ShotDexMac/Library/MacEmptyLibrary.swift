import SwiftUI
import UniformTypeIdentifiers

/// The first run (board `MAC_EmptyLibrary`, FS-18.01 §7, D13): no source yet,
/// so the window says what ShotDex reads and offers the three ways in. There
/// is no onboarding window; the Photos permission is asked only once Add
/// Photos Library… is clicked. The whole content area takes a dropped folder.
struct MacEmptyLibrary: View {
    let addPhotosLibrary: () -> Void
    let addFolder: () -> Void
    let connectToServer: () -> Void
    /// Whatever was dropped from Finder; non-folders are refused there with a reason.
    let addFolders: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            MacEmptyLibraryTile(systemImage: "photo.on.rectangle", side: 64, glyph: 34, radius: 16)
            Text("Welcome to ShotDex", comment: "Mac first run: title")
                .font(.system(size: 22, weight: .bold))
                .frame(minHeight: 28)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 16)
            Text("ShotDex indexes the photos you already have, in Photos, in folders and drives, and on your NAS, so you can find any shot by camera, lens and exposure.",
                 comment: "Mac first run: what ShotDex does")
                .font(.system(size: 13))
                .lineSpacing(4.5)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
                .padding(.top, 8)
            HStack(spacing: 12) {
                card(systemImage: "photo.on.rectangle",
                     title: String(localized: "Photos Library", comment: "Mac first run: card title"),
                     text: String(localized: "Your Photos library, iCloud Photos included. macOS asks you to allow access.",
                                  comment: "Mac first run: Photos Library card"),
                     button: String(localized: "Add Photos Library…", comment: "Mac first run: add the Photos library"),
                     isDefault: true, action: addPhotosLibrary)
                card(systemImage: "folder",
                     title: String(localized: "Folder or Drive", comment: "Mac first run: card title"),
                     text: String(localized: "Any folder on this Mac or on an external drive, read in place.",
                                  comment: "Mac first run: Folder or Drive card"),
                     button: String(localized: "Add Folder or Drive…", comment: "Mac first run: add a folder or drive"),
                     isDefault: false, action: addFolder)
                card(systemImage: "server.rack",
                     title: String(localized: "Server", comment: "Mac first run: card title"),
                     text: String(localized: "An SMB, SFTP or WebDAV share on a NAS, indexed like a folder.",
                                  comment: "Mac first run: Server card"),
                     button: String(localized: "Connect to Server…", comment: "Mac first run: add a server"),
                     isDefault: false, action: connectToServer)
            }
            .padding(.top, 28)
            dropZone.padding(.top, 16)
            Label {
                Text("Photos stay on your Mac. ShotDex never edits file contents.", comment: "Mac first run: privacy line")
            } icon: {
                Image(systemName: "lock")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.top, 24)
        }
        .frame(width: 672)
        .padding(.top, 40)
        // Centred in the whole window, toolbar strip included, as the board.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.container, edges: .top)
        .contentShape(Rectangle())
        // Anything dropped goes through: a file is refused with a reason.
        .dropDestination(for: URL.self) { urls, _ in
            addFolders(urls)
            return !urls.filter(Self.isFolder).isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    /// A folder, drive or card — not a package such as a `.photoslibrary`,
    /// which only Add Photos Library… reads.
    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    private func card(systemImage: String, title: String, text: String, button: String, isDefault: Bool,
                      action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MacEmptyLibraryTile(systemImage: systemImage, side: 36, glyph: 20, radius: 10)
            Text(title).font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(text)
                .font(.system(size: 12))
                .lineSpacing(1)
                .foregroundStyle(.secondary)
                // At least the board's three lines; a longer translation grows the card.
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 48, alignment: .topLeading)
            Button(action: action) {
                Text(button).frame(maxWidth: .infinity)
            }
            .buttonStyle(MacEmptyLibraryButtonStyle(isDefault: isDefault))
            .keyboardShortcut(isDefault ? .defaultAction : nil)
        }
        // 16 inside a 1pt border, as the board's border-box draws it.
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var dropZone: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.arrow.down").font(.system(size: 22))
            VStack(alignment: .leading, spacing: 2) {
                Text("or drop a folder here", comment: "Mac first run: drop zone").font(.system(size: 13)).foregroundStyle(.primary)
                Text("A folder, a drive or a memory card from Finder · or onto Sources in the sidebar",
                     comment: "Mac first run: what the drop zone takes")
                    .font(.system(size: 11))
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(RoundedRectangle(cornerRadius: 12).fill(isTargeted ? MacTheme.accentSoft : .clear))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isTargeted ? MacTheme.accent : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Drop a folder here", comment: "Mac first run: drop zone, VoiceOver"))
        .accessibilityHint(String(localized: "A folder, a drive or a memory card from Finder, or use Add Folder or Drive.",
                                  comment: "Mac first run: drop zone, VoiceOver hint"))
    }
}

/// The amber-tinted square behind a first-run glyph.
private struct MacEmptyLibraryTile: View {
    let systemImage: String
    let side: CGFloat
    let glyph: CGFloat
    let radius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(MacTheme.accentSoft)
            .frame(width: side, height: side)
            .overlay(Image(systemName: systemImage).font(.system(size: glyph)).foregroundStyle(MacTheme.accent))
            .accessibilityHidden(true)
    }
}

/// Push button 28, radius 8 (DESIGN.md §10b): `accentFill` for the default,
/// `fill` for the others — whatever the system accent.
private struct MacEmptyLibraryButtonStyle: ButtonStyle {
    let isDefault: Bool

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isDefault: isDefault)
    }

    /// A view, so it can read focus and enabled state: keyboard navigation
    /// gets a ring, a disabled button looks it.
    private struct StyledLabel: View {
        let configuration: Configuration
        let isDefault: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MacTheme.accent, lineWidth: isFocused ? 2 : 0))
                .opacity(isEnabled ? 1 : 0.4)
        }

        private var label: some View {
        configuration.label
            .font(.system(size: 13, weight: isDefault ? .semibold : .regular))
            .foregroundStyle(isDefault ? MacTheme.onAccentFill : Color.primary)
            .frame(height: 28)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(isDefault ? MacTheme.accentFill : MacTheme.fill))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
