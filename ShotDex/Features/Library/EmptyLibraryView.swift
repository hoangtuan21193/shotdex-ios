import SwiftUI
import UniformTypeIdentifiers

/// The library before any source exists (FS-21 §3, boards `PH_EmptyLibrary`,
/// `DI_EmptyLibrary`, `DC_EmptyLibrary`, `IP_EmptyLibrary`): Welcome to
/// ShotDex and three ways in — Photos Library, Folder or Drive, Server.
///
/// Onboarding's Continue lands here without asking for Photos access; the
/// system prompt opens only from Add Photos Library (AC-42).
///
/// Three shapes, picked by the room the view gets:
/// - wide (iPad, the Duo's inner display): three cards side by side with a
///   button each, and a drop zone for a folder dragged from Files;
/// - tall and narrow (iPhone): the same cards stacked, the action a link;
/// - short and narrow (the Duo's cover, 678pt behind its rail): one row per
///   source, the whole row the action, so all three fit above the fold.
struct EmptyLibraryView: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.appAccent) private var accent

    @State private var isAddingFolder = false
    @State private var isConnectingServer = false
    @State private var isDropTargeted = false

    /// Wider than this the cards sit side by side (DI board: 3 × 258 + 2 × 14).
    static let wideMinimumWidth: CGFloat = 700
    /// Shorter than this a stacked card column would not fit; rows instead.
    static let tallMinimumHeight: CGFloat = 760

    enum Shape: Equatable { case wide, stacked, rows }

    static func shape(for size: CGSize) -> Shape {
        if size.width >= wideMinimumWidth { return .wide }
        return size.height >= tallMinimumHeight ? .stacked : .rows
    }

    @State private var size: CGSize = .zero

    var body: some View {
        let shape = Self.shape(for: size)
        ScrollView {
            Group {
                switch shape {
                case .wide: wide
                case .stacked: stacked
                case .rows: rows
                }
            }
            .padding(.horizontal, AppTheme.Size.screenMargin)
            .padding(.bottom, AppTheme.Spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGSize.self) { proxy in
            // The whole window, not the safe area: the cover's short height is
            // what decides rows, and its bars eat into it.
            CGSize(width: proxy.size.width,
                   height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
        } action: { size = $0 }
        .sheet(isPresented: $isAddingFolder) {
            AddSourceSheet()
        }
        .sheet(isPresented: $isConnectingServer) {
            NavigationStack {
                FileServerListScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "Done", comment: "Connect to Server sheet from the empty library: close")) {
                                isConnectingServer = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: Sources

    private struct Source: Identifiable {
        let id: String
        let title: String
        let detail: String
        let action: String
        let systemImage: String
        let isPrimary: Bool
    }

    private func sources(shortPhotosDetail: Bool) -> [Source] {
        [
            Source(id: "photos",
                   title: String(localized: "Photos Library", comment: "Empty library: the Photos card title"),
                   detail: UIDevice.current.userInterfaceIdiom == .pad
                       ? String(localized: "Your Photos library, iCloud Photos included. iPadOS asks you to allow access.", comment: "Empty library: Photos card, iPad")
                       : shortPhotosDetail
                       ? String(localized: "Your Photos library, iCloud Photos included. iOS asks for access.", comment: "Empty library: Photos card, short")
                       : String(localized: "Your Photos library, iCloud Photos included. iOS asks for access next — choose Allow Full Access.", comment: "Empty library: Photos card"),
                   action: String(localized: "Add Photos Library…", comment: "Empty library: asks for Photos access"),
                   systemImage: "photo.on.rectangle", isPrimary: true),
            Source(id: "folder",
                   title: String(localized: "Folder or Drive", comment: "Empty library: the folder card title"),
                   detail: String(localized: "A folder in Files, or an external drive or SSD over USB-C, read in place.", comment: "Empty library: folder card"),
                   action: String(localized: "Add Folder or Drive…", comment: "Empty library: opens Add a Source"),
                   systemImage: "folder", isPrimary: false),
            Source(id: "server",
                   title: String(localized: "Server", comment: "Empty library: the server card title"),
                   detail: String(localized: "An SMB, SFTP or WebDAV share on a NAS, indexed like a folder.", comment: "Empty library: server card"),
                   action: String(localized: "Connect to Server…", comment: "Empty library: opens the server list"),
                   systemImage: "server.rack", isPrimary: false),
        ]
    }

    private func perform(_ source: Source) {
        switch source.id {
        case "photos": Task { await photoLibrary.requestAuthorization() }
        case "folder": isAddingFolder = true
        default: isConnectingServer = true
        }
    }

    // MARK: Text

    private var welcome: some View {
        Text("Welcome to ShotDex", comment: "Empty library: title")
            .font(.title.bold())
    }

    private var pitch: String {
        String(localized: "ShotDex indexes the photos you already have, in Photos, in folders and drives, and on your NAS, so you can find any shot by camera, lens and exposure.",
               comment: "Empty library: what ShotDex does")
    }

    private var memoryCardLine: some View {
        Label {
            Text("Have a memory card? Connect a card reader or the camera over USB-C to import from it.",
                 comment: "Empty library: memory card hint")
        } icon: {
            Image(systemName: "sdcard")
        }
        .font(.footnote)
        .foregroundStyle(Color(.secondaryLabel))
    }

    private var promiseLine: some View {
        Label {
            Text("Photos stay where they are. ShotDex never edits file contents.", comment: "Empty library: the promise at the bottom")
        } icon: {
            Image(systemName: "lock")
        }
        .font(.caption)
        .foregroundStyle(Color(.secondaryLabel))
    }

    private func glyph(_ systemImage: String, size: CGFloat) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5))
            .foregroundStyle(accent)
            .frame(width: size, height: size)
            .background(accent.opacity(0.14), in: RoundedRectangle.app(size * 0.25))
            .accessibilityHidden(true)
    }

    // MARK: Wide — iPad, Duo inner

    private var wide: some View {
        VStack(spacing: 0) {
            glyph("photo", size: 64)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, AppTheme.Spacing.md)
            welcome
            Text(pitch)
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
                .padding(.top, AppTheme.Spacing.xs)
                .padding(.bottom, AppTheme.Spacing.md)
            HStack(alignment: .top, spacing: 14) {
                ForEach(sources(shortPhotosDetail: true)) { wideCard($0) }
            }
            .fixedSize(horizontal: false, vertical: true)
            dropZone
                .padding(.top, 14)
            memoryCardLine
                .padding(.top, AppTheme.Spacing.md)
            promiseLine
                .padding(.top, AppTheme.Spacing.sm)
        }
        .frame(maxWidth: 802)
        .frame(maxWidth: .infinity)
    }

    private func wideCard(_ source: Source) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            glyph(source.systemImage, size: 40)
            Text(source.title)
                .font(.headline)
                .padding(.top, 10)
            Text(source.detail)
                .font(.footnote)
                .foregroundStyle(Color(.secondaryLabel))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 18)
            Button { perform(source) } label: {
                Text(source.action)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .foregroundStyle(source.isPrimary ? Color.white : Color(.label))
                    .background(source.isPrimary ? AnyShapeStyle(accent) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .minimumHitTarget(drawnHeight: 40)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.xl))
        .overlay(RoundedRectangle.app(AppTheme.Radius.xl).strokeBorder(Color(.separator), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    /// A folder dragged from Files open beside ShotDex is added like Add
    /// Folder or Drive, subfolders and RAW+JPEG pairing on.
    private var dropZone: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "arrow.down.to.line")
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("or drag a folder here", comment: "Empty library: drop zone")
                    .font(.subheadline)
                    .foregroundStyle(Color(.label))
                Text("From Files open beside ShotDex", comment: "Empty library: drop zone detail")
                    .font(.caption)
            }
        }
        .foregroundStyle(Color(.secondaryLabel))
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(isDropTargeted ? accent.opacity(0.1) : .clear, in: RoundedRectangle.app(AppTheme.Radius.xl))
        .overlay(
            RoundedRectangle.app(AppTheme.Radius.xl)
                .strokeBorder(isDropTargeted ? accent : Color(.tertiaryLabel), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .onDrop(of: [.folder], isTargeted: $isDropTargeted) { providers in
            guard let provider = providers.first else { return false }
            let sources = dependencies.sources
            _ = provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.folder.identifier) { url, _, _ in
                guard let url else { return }
                Task { @MainActor in
                    await sources.addFolder(url, includesSubfolders: true, pairsRawAndJpeg: true)
                }
            }
            return true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Drop a folder here", comment: "Empty library: drop zone, VoiceOver"))
    }

    // MARK: Stacked — iPhone

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            welcome
                .padding(.top, AppTheme.Spacing.md)
            Text(pitch)
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.top, AppTheme.Spacing.xs)
                .padding(.bottom, AppTheme.Spacing.lg)
            VStack(spacing: 12) {
                ForEach(sources(shortPhotosDetail: false)) { stackedCard($0) }
            }
            memoryCardLine
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.lg)
            promiseLine
                .labelStyle(.titleOnly)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, AppTheme.Spacing.md)
        }
    }

    private func stackedCard(_ source: Source) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.lg) {
            Image(systemName: source.systemImage)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.headline)
                Text(source.detail)
                    .font(.footnote)
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
                Button(source.action) { perform(source) }
                    .font(.subheadline.weight(.semibold))
                    .tint(accent)
                    .frame(minHeight: 36)
                    .minimumHitTarget(drawnHeight: 36)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle.app(AppTheme.Radius.xl))
        .accessibilityElement(children: .contain)
    }

    // MARK: Rows — Duo cover

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            glyph("photo", size: 52)
                .padding(.top, AppTheme.Spacing.sm)
            welcome
                .padding(.top, AppTheme.Spacing.md)
            Text("Index the photos you already have, in Photos, in folders and drives, and on your NAS.",
                 comment: "Empty library: what ShotDex does, short")
                .font(.subheadline)
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.top, AppTheme.Spacing.xs)
                .padding(.bottom, 14)
            VStack(spacing: 10) {
                ForEach(sources(shortPhotosDetail: true)) { row($0) }
            }
            memoryCardLine
                .padding(.top, AppTheme.Spacing.lg)
            promiseLine
                .padding(.top, AppTheme.Spacing.md)
        }
    }

    private func row(_ source: Source) -> some View {
        Button { perform(source) } label: {
            HStack(spacing: 14) {
                glyph(source.systemImage, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.action)
                        .font(.headline)
                        .foregroundStyle(Color(.label))
                    Text(source.detail)
                        .font(.footnote)
                        .foregroundStyle(Color(.secondaryLabel))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(Color(.systemBackground), in: RoundedRectangle.app(AppTheme.Radius.xl))
            .overlay(
                RoundedRectangle.app(AppTheme.Radius.xl)
                    .strokeBorder(source.isPrimary ? accent : Color(.separator), lineWidth: 1)
            )
            .contentShape(RoundedRectangle.app(AppTheme.Radius.xl))
        }
        .buttonStyle(.plain)
    }
}
