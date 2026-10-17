import Photos
import SwiftUI

/// What the phone filmstrip's Sync menu does, handed in by the screen.
struct EditorFilmstripSync {
    let canSync: Bool
    let hasPrevious: Bool
    let syncLook: () -> Void
    let syncEverything: () -> Void
    let applyPrevious: () -> Void
    let isAutoSyncing: Binding<Bool>
}

/// A multi-photo edit's run on the phone (FS-03.13d §2): 56pt between the
/// photo and the panel, 44pt frames 8 apart, the one being edited ringed in
/// white, then the Sync pill with "2 / 7" under it. Sync lives only here.
struct EditorPhoneFilmstrip: View {
    let session: EditorSession
    let photoLibrary: PhotoLibraryService
    /// The photo open now carries the live recipe the session has not had yet.
    let currentHasEdits: Bool
    let sync: EditorFilmstripSync
    let select: (Int) -> Void

    static let height: CGFloat = 56
    static let frameSide: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(Array(session.photos.enumerated()), id: \.offset) { index, photo in
                            frame(photo, index: index).id(index)
                        }
                    }
                    .padding(.leading, AppTheme.Spacing.md)
                    .padding(.trailing, Self.fadeWidth)
                    .frame(maxHeight: .infinity)
                }
                .mask {
                    HStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: Self.fadeWidth)
                    }
                }
                .onAppear { proxy.scrollTo(session.index, anchor: .center) }
                .onChange(of: session.index) { _, new in
                    withAnimation(EditorTheme.animation) { proxy.scrollTo(new, anchor: .center) }
                }
            }
            syncPill
                .padding(.trailing, AppTheme.Spacing.md)
        }
        .frame(height: Self.height)
        .background(EditorTheme.panelSolid)
    }

    private static let fadeWidth: CGFloat = 28

    private func frame(_ photo: PhotoEditOrigin, index: Int) -> some View {
        let isCurrent = index == session.index
        let isSaved = session.isSaved(photo)
        let hasDraft = isCurrent ? currentHasEdits : session.hasDraft(photo)
        let shape = RoundedRectangle(cornerRadius: EditorLayoutMetrics.filmstripCellRadius, style: .continuous)
        return Button {
            select(index)
        } label: {
            EditorFilmstripThumbnail(photo: photo, photoLibrary: photoLibrary, original: session.originalStates[photo.id])
                .frame(width: Self.frameSide, height: Self.frameSide)
                .onAppear { session.probeOriginal(of: photo) }
                .clipShape(shape)
                .overlay(alignment: .bottomTrailing) {
                    // No accent: a dot is an unsaved draft, a check is saved.
                    if isSaved {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(Color.black.opacity(0.65), in: Circle())
                            .padding(2)
                    } else if hasDraft {
                        Circle().fill(.white).frame(width: 8, height: 8).padding(3)
                    }
                }
                .opacity(isCurrent ? 1 : 0.75)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: EditorLayoutMetrics.filmstripCellRadius + 3.5, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1.5)
                            .padding(-3.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Photo \(index + 1) of \(session.photos.count)")
        .accessibilityValue(isSaved ? "Saved" : hasDraft ? "Edited" : "")
        .accessibilityAddTraits(isCurrent ? [.isSelected, .isButton] : .isButton)
    }

    private var others: Int { session.photos.count - 1 }
    private var photosText: String { others == 1 ? "1 Photo" : "\(others) Photos" }

    /// Always four items (E5): Apply Previous dims when there is no previous.
    private var syncPill: some View {
        VStack(spacing: 2) {
            Menu {
                Button(action: sync.syncLook) {
                    Text("Sync Look to \(photosText)…")
                    Text("Tone, color, curve and look")
                }
                .disabled(!sync.canSync)
                Button("Sync Everything to \(photosText)…", action: sync.syncEverything)
                    .disabled(!sync.canSync)
                Button(action: sync.applyPrevious) {
                    Label("Apply Previous", systemImage: "arrow.uturn.left.square")
                }
                .disabled(!sync.hasPrevious)
                Toggle(isOn: sync.isAutoSyncing) {
                    Label("Auto Sync", systemImage: "arrow.triangle.2.circlepath")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Sync")
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, AppTheme.Spacing.md)
                .frame(height: 32)
                .background(Color.white.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Sync")
            Text("\(session.index + 1) / \(session.photos.count)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(EditorTheme.secondaryText)
        }
    }
}
