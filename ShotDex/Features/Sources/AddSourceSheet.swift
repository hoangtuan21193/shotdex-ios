import SwiftUI
import UniformTypeIdentifiers

/// Add a Source (board `PH_AddSource`): pick what kind, then Files opens on
/// Choose Folder…. Photos stay where they are; nothing is copied or moved.
struct AddSourceSheet: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isDuoInner) private var isDuoInner
    @State private var includesSubfolders = true
    @State private var pairsRawAndJpeg = true
    /// The folder picked is a source already, or inside or around one (FS-19 AC-45).
    @State private var overlapRefusal: String?
    @State private var isPickingFolder = false
    @State private var kind: Kind = .folder
    @State private var isShowingServers = false
    @State private var isPickingCard = false

    enum Kind { case folder, server }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    Text("Photos stay where they are. Nothing is copied or moved, and ShotDex never edits file contents.",
                         comment: "Add a Source: the promise at the top")
                        .font(.subheadline)
                        .foregroundStyle(Color(.secondaryLabel))
                        .padding(.horizontal, AppTheme.Spacing.xs)
                    card {
                        option(title: String(localized: "Photos Library", comment: "Add a Source: the Photos library"),
                               detail: String(localized: "The Photos library on this iPhone, iCloud Photos included.", comment: "Add a Source: Photos Library option"),
                               systemImage: "photo.on.rectangle") {
                            // Before Photos access is asked (FS-21 §3) it is
                            // not a source yet: Add asks, here as on the
                            // empty library's card.
                            if photoLibrary.authorizationState == .notDetermined {
                                Button(String(localized: "Add", comment: "Add a Source: asks for Photos access")) {
                                    Task {
                                        await photoLibrary.requestAuthorization()
                                        dismiss()
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                                .controlSize(.small)
                            } else {
                                Text("Added", comment: "Add a Source: the Photos library is already a source")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.secondaryLabel))
                                    .padding(.horizontal, AppTheme.Spacing.sm)
                                    .padding(.vertical, 3)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                        }
                    }
                    // The Duo's inner display gives a 661pt sheet: one card
                    // above the other, the memory-card row ended under the
                    // footer. Side by side the two kinds fit (FS-19.01 §1).
                    if isDuoInner {
                        HStack(alignment: .top, spacing: AppTheme.Spacing.md) { kindCards }
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        kindCards
                    }
                    // Cards arrive by themselves (FS-20): nothing to pick here.
                    HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                        Image(systemName: "sdcard")
                            .font(.title3)
                            .frame(width: 28)
                            .foregroundStyle(Color(.secondaryLabel))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Have a memory card?", comment: "Add a Source: memory card hint title")
                                .font(.subheadline.weight(.semibold))
                            Text("Connect a card reader or the camera over USB-C; the card shows under Sources.", comment: "Add a Source: memory card hint")
                                .font(.footnote)
                                .foregroundStyle(Color(.secondaryLabel))
                            // A card in Files is chosen once; plugged in again
                            // it is known by its volume (FS-20 AC-20).
                            Button(String(localized: "Choose Card…", comment: "Add a Source: pick a memory card in Files once")) {
                                isPickingCard = true
                            }
                            .font(.footnote.weight(.semibold))
                            .padding(.top, AppTheme.Spacing.xs)
                        }
                    }
                    .padding(AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle.app(AppTheme.Radius.xl).strokeBorder(Color(.separator), lineWidth: 1))
                    .accessibilityElement(children: .contain)
                }
                .padding(AppTheme.Size.screenMargin)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                // On the Duo the caption stands beside the button, as on the
                // board: one row instead of two.
                Group {
                    if isDuoInner {
                        HStack(spacing: AppTheme.Spacing.md) {
                            footerCaption
                                .frame(maxWidth: .infinity, alignment: .leading)
                            footerButton
                                .fixedSize()
                        }
                    } else {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            footerCaption
                            footerButton
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Size.screenMargin)
                .padding(.bottom, AppTheme.Spacing.sm)
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle(Text("Add a Source", comment: "Add a Source: sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
            .alert(String(localized: "Can’t Add This Folder", comment: "Add a Source: the folder overlaps a source"),
                   isPresented: Binding(get: { overlapRefusal != nil }, set: { if !$0 { overlapRefusal = nil } })) {
                Button(String(localized: "OK", comment: "Add a Source: dismiss the refusal")) {}
            } message: {
                Text(overlapRefusal ?? "")
            }
            .navigationDestination(isPresented: $isShowingServers) {
                FileServerListScreen()
            }
            .fileImporter(isPresented: $isPickingCard, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                _ = try? dependencies.cards.remember(url)
                dismiss()
            }
            .fileImporter(isPresented: $isPickingFolder, allowedContentTypes: [.folder]) { result in
                guard case .success(let url) = result else { return }
                let sources = dependencies.sources
                // Said here, before the sheet goes: nothing would show it after.
                if let refusal = sources.overlap(url) {
                    overlapRefusal = refusal
                    return
                }
                let (subfolders, pairs) = (includesSubfolders, pairsRawAndJpeg)
                dismiss()
                Task { await sources.addFolder(url, includesSubfolders: subfolders, pairsRawAndJpeg: pairs) }
            }
        }
    }

    /// Folder or Drive, then Server — stacked, or in a row on the Duo.
    @ViewBuilder private var kindCards: some View {
        card(selected: kind == .folder) {
            Button { kind = .folder } label: {
                option(title: String(localized: "Folder or Drive", comment: "Add a Source: a folder in Files or a USB-C drive"),
                       detail: String(localized: "A folder in Files, or a drive or SSD over USB-C, read in place. An unplugged drive’s photos stay, marked offline.", comment: "Add a Source: Folder or Drive option"),
                       systemImage: "folder") { radio(kind == .folder) }
            }
            .buttonStyle(.plain)
            if kind == .folder {
                Divider()
                Toggle(String(localized: "Include Subfolders", comment: "Add a Source: read folders inside the chosen folder"), isOn: $includesSubfolders)
                Toggle(String(localized: "Pair RAW + JPEG as One Photo", comment: "Add a Source: a RAW and its JPEG twin are one photo"), isOn: $pairsRawAndJpeg)
            }
        }
        card(selected: kind == .server) {
            Button { kind = .server } label: {
                option(title: String(localized: "Server", comment: "Add a Source: a NAS share"),
                       detail: String(localized: "An SMB, SFTP or WebDAV share on a NAS, indexed like a folder. Originals download when you open them.", comment: "Add a Source: Server option"),
                       systemImage: "server.rack") { radio(kind == .server) }
            }
            .buttonStyle(.plain)
        }
    }

    private var footerCaption: some View {
        Text(kind == .folder
             ? String(localized: "Files opens next; a USB-C drive shows under Locations.", comment: "Add a Source: above Choose Folder")
             : String(localized: "Turn on Add as Source in the connection’s form.", comment: "Add a Source: above Connect to Server"))
            .font(.footnote)
            .foregroundStyle(Color(.secondaryLabel))
    }

    private var footerButton: some View {
        Button {
            if kind == .folder { isPickingFolder = true } else { isShowingServers = true }
        } label: {
            Group {
                if kind == .folder {
                    Text("Choose Folder…", comment: "Add a Source: opens Files to pick the folder")
                } else {
                    Text("Connect to Server…", comment: "Add a Source: opens the server list")
                }
            }
            .font(.headline)
            .frame(maxWidth: isDuoInner ? nil : .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private func radio(_ isOn: Bool) -> some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiaryLabel)))
            .accessibilityHidden(true)
    }

    private func card(selected: Bool = false, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) { content() }
            .padding(AppTheme.Spacing.md)
            // Full height too, so two cards in a row end level.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle.app(AppTheme.Radius.xl))
            .overlay {
                if selected {
                    RoundedRectangle.app(AppTheme.Radius.xl).strokeBorder(.tint, lineWidth: 1.5)
                }
            }
    }

    private func option(title: String, detail: String, systemImage: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)
                .foregroundStyle(Color(.label))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            trailing()
        }
        .accessibilityElement(children: .combine)
    }
}
