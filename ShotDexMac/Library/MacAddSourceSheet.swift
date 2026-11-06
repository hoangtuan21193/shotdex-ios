import SwiftUI

/// Add a Source (board `MAC_AddSource`, FS-19.01 §1): the sidebar's + under
/// Sources. Three kinds, one picked; the default button says what happens
/// next — Choose Folder… opens the open panel with the two folder options,
/// Connect to Server… the connection form, Add Photos Library… the Photos
/// permission. Photos already added is shown done and cannot be picked.
struct MacAddSourceSheet: View {
    enum Kind: Hashable { case photos, folder, server }

    /// Photos is a source already (its permission was given).
    let photosAdded: Bool
    let addPhotosLibrary: () -> Void
    /// A folder picked (open panel or dropped on the sheet), with its options.
    let addFolder: (_ folder: URL, _ includesSubfolders: Bool, _ pairsRawAndJpeg: Bool) -> Void
    let connectToServer: () -> Void

    @Environment(MacDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.folder
    /// FS-19.01 §1: both on by default.
    @State private var includesSubfolders = true
    @State private var pairsRawAndJpeg = true
    /// Photos Library's item count, read off the main actor.
    @State private var photosCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a Source", comment: "Mac Add Source sheet: title")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text("Photos stay where they are. Nothing is copied or moved, and ShotDex never edits file contents.",
                     comment: "Mac Add Source sheet: what adding a source does")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                option(.photos, systemImage: "photo.on.rectangle",
                       title: String(localized: "Photos Library", comment: "Mac Add Source: kind"),
                       text: String(localized: "The Photos library on this Mac, iCloud Photos included. Favorites, albums, hidden photos and edits stay in sync with Photos.",
                                    comment: "Mac Add Source: Photos Library"),
                       detail: String(localized: "Read through Photos · edits save as Photos edits · Delete and Hide go through Photos",
                                      comment: "Mac Add Source: Photos Library details"))
                option(.folder, systemImage: "folder",
                       title: String(localized: "Folder or Drive", comment: "Mac Add Source: kind"),
                       text: String(localized: "Any folder on this Mac or on an external drive. Files are indexed in place and watched for changes. When a drive is unplugged its photos stay in the library, marked offline.",
                                    comment: "Mac Add Source: Folder or Drive"),
                       detail: String(localized: "RAW (CR3, ARW, RAF, NEF, DNG) · HEIC · JPEG · TIFF · PNG · MOV and MP4 · ratings, keywords and captions are saved to the .xmp sidecar next to each file; the image file itself is never edited",
                                      comment: "Mac Add Source: Folder or Drive details"))
                option(.server, systemImage: "server.rack",
                       title: String(localized: "Server", comment: "Mac Add Source: kind"),
                       text: String(localized: "An SMB, SFTP or WebDAV share on a NAS or another computer, indexed like a folder. Thumbnails come from previews inside the files and are cached on this Mac; originals download when you open, edit or export.",
                                    comment: "Mac Add Source: Server"),
                       detail: String(localized: "Password saved in Keychain · ratings go to .xmp sidecars on the share · Dropbox, Google Drive and OneDrive folders synced by Finder are added as a Folder",
                                      comment: "Mac Add Source: Server details"))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(String(localized: "Source kind", comment: "Mac Add Source: the three kinds, VoiceOver"))
            // ↑↓ pick a kind from the keyboard, as in a radio group.
            .focusable()
            .onKeyPress(.upArrow) { step(-1); return .handled }
            .onKeyPress(.downArrow) { step(1); return .handled }
            HStack(spacing: 8) {
                Label {
                    Text("You can also drop a folder onto the sidebar.", comment: "Mac Add Source: drag and drop hint")
                } icon: {
                    Image(systemName: "square.and.arrow.down")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Cancel", comment: "Mac Add Source: close")) { dismiss() }
                    .buttonStyle(MacPushButtonStyle(isDefault: false))
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle, action: primary)
                    .buttonStyle(MacPushButtonStyle(isDefault: true, defaultWeight: .medium))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 640)
        .presentationBackground(MacTheme.sheet)
        // A folder dropped on the sheet is added with the options shown.
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: MacEmptyLibrary.isFolder) else { return false }
            addFolder(folder, includesSubfolders, pairsRawAndJpeg)
            dismiss()
            return true
        }
        .tint(MacTheme.accentFill)
        .task { await loadPhotosCount() }
    }

    /// The next kind up or down, skipping Photos once it is a source.
    private func step(_ delta: Int) {
        let kinds: [Kind] = photosAdded ? [.folder, .server] : [.photos, .folder, .server]
        guard let index = kinds.firstIndex(of: kind) else { kind = kinds[0]; return }
        kind = kinds[max(0, min(kinds.count - 1, index + delta))]
    }

    private var primaryTitle: String {
        switch kind {
        case .photos: String(localized: "Add Photos Library…", comment: "Mac Add Source: default button, Photos picked")
        case .folder: String(localized: "Choose Folder…", comment: "Mac Add Source: default button, Folder or Drive picked")
        case .server: String(localized: "Connect to Server…", comment: "Mac Add Source: default button, Server picked")
        }
    }

    /// Choose Folder… opens the open panel on this sheet and closes it only
    /// once a folder is picked — a cancelled panel leaves the sheet and its
    /// two options as they were. Photos and Server close it first: the window
    /// runs them once it is gone.
    private func primary() {
        switch kind {
        case .photos:
            addPhotosLibrary()
            dismiss()
        case .folder:
            let subfolders = includesSubfolders, pairs = pairsRawAndJpeg
            MacPhotoSourcesSection.chooseFolder { folder in
                addFolder(folder, subfolders, pairs)
                dismiss()
            }
        case .server:
            connectToServer()
            dismiss()
        }
    }

    private func loadPhotosCount() async {
        guard photosAdded else { return }
        let sources = dependencies.sources
        photosCount = await Task.detached(priority: .userInitiated) {
            (try? sources.photoCounts())?[PhotoLibrarySource.id]
        }.value
    }

    private func option(_ option: Kind, systemImage: String, title: String, text: String, detail: String) -> some View {
        let isDone = option == .photos && photosAdded
        let isSelected = kind == option && !isDone
        return VStack(alignment: .leading, spacing: 0) {
            // The part that picks the row: one element for VoiceOver, a
            // button unless Photos is already a source.
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(MacTheme.fill)
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: systemImage).font(.system(size: 22)).foregroundStyle(MacTheme.accent))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 13, weight: .semibold))
                        Spacer(minLength: 0)
                        if isDone {
                            Label {
                                Text(photosCount.map { String(localized: "Added · \($0.formatted()) items", comment: "Mac Add Source: Photos already a source, with its count") }
                                     ?? String(localized: "Added", comment: "Mac Add Source: Photos already a source"))
                            } icon: {
                                Image(systemName: "checkmark")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MacTheme.greenText)
                        }
                    }
                    // Line pitch 17 and 15 as the board: spacing between lines, half-leading around.
                    Text(text).font(.system(size: 12)).lineSpacing(2.7).padding(.vertical, 1.25)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail).font(.system(size: 11)).lineSpacing(1.9).padding(.vertical, 0.5).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // Title as the label, the state as the value, the text as the hint.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(isDone ? String(localized: "Added", comment: "Mac Add Source: Photos already a source, VoiceOver") : "")
            .accessibilityHint(text)
            .accessibilityIdentifier("addSource.\(option)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityActions {
                if !isDone {
                    Button(String(localized: "Choose", comment: "Mac Add Source: pick this kind, VoiceOver action")) { kind = option }
                }
            }
            if option == .folder {
                // Changing an option picks the row it belongs to.
                HStack(spacing: 20) {
                    Toggle(String(localized: "Include subfolders", comment: "Mac Add Source: folder option"), isOn: $includesSubfolders)
                    Toggle(String(localized: "Pair RAW + JPEG as one photo", comment: "Mac Add Source: folder option"), isOn: $pairsRawAndJpeg)
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .frame(height: 22)
                .padding(.top, 6)
                .padding(.leading, 52)
                .onChange(of: includesSubfolders) { kind = .folder }
                .onChange(of: pairsRawAndJpeg) { kind = .folder }
            }
        }
        // 16 / 12 inside the 1pt border, as the board's border-box (the
        // 2pt selected ring draws over the inset, so nothing moves).
        .padding(.horizontal, 17)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(MacTheme.content)
            .shadow(color: .black.opacity(isSelected ? 0.15 : 0), radius: 1.5, y: 1))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isSelected ? MacTheme.accent : MacTheme.separator, lineWidth: isSelected ? 2 : 1))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { if !isDone { kind = option } }
        .accessibilityElement(children: .contain)
    }
}
