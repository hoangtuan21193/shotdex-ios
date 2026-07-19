import Photos
import SwiftUI

/// Albums tab: 2-column grid of Recents, smart albums, and user albums.
struct AlbumsScreen: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var controller = AlbumsController()

    var body: some View {
        Group {
            if photoLibrary.authorizationState.canReadLibrary {
                albumGrid
            } else {
                ContentUnavailableView(
                    "No Access to Photos",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("Allow photo access in the Library tab to browse albums.")
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                SettingsDrawerButton()
            }
        }
        .task(id: photoLibrary.libraryChangeToken) {
            guard photoLibrary.authorizationState.canReadLibrary else { return }
            controller.load()
        }
        .navigationDestination(for: AlbumItem.ID.self) { albumId in
            if let album = controller.albums.first(where: { $0.id == albumId }) {
                AlbumDetailScreen(album: album)
            }
        }
        .navigationDestination(for: OnThisDayRoute.self) { _ in
            OnThisDayScreen()
        }
    }

    private var albumGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if photoLibrary.authorizationState == .limited {
                    LimitedAccessBanner {
                        photoLibrary.presentLimitedLibraryPicker()
                    }
                    .padding(.top, 4)
                }

                NavigationLink(value: OnThisDayRoute()) {
                    OnThisDayCard(
                        count: controller.onThisDayCount,
                        coverAsset: controller.onThisDayCover
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                if !controller.smartAlbums.isEmpty {
                    smartAlbumsRow
                }

                if !controller.userAlbums.isEmpty {
                    myAlbumsSection
                }

                if #unavailable(iOS 26.0) {
                    Color.clear.frame(height: 90)
                }
            }
        }
    }

    /// Horizontal carousel of system collections, like the pinned
    /// collections row in the iOS 26 Photos app.
    private var smartAlbumsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(controller.smartAlbums) { album in
                    NavigationLink(value: album.id) {
                        AlbumCard(album: album, side: 172)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .scrollClipDisabled()
    }

    /// "My Albums" header + 2-column grid, Photos-app style.
    private var myAlbumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Albums")
                .font(.title2.bold())
                .padding(.horizontal)

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 20
            ) {
                ForEach(controller.userAlbums) { album in
                    NavigationLink(value: album.id) {
                        AlbumCard(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }
}

/// Full-width hero card for the "On This Day" smart album: cover photo
/// with a gradient scrim, today's date, and the match count.
struct OnThisDayCard: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let count: Int
    let coverAsset: PHAsset?

    @State private var cover: UIImage?

    var body: some View {
        Color(.secondarySystemBackground)
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .overlay {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                }
            }
            .overlay {
                LinearGradient(
                    colors: [.clear, .black.opacity(cover == nil ? 0.25 : 0.55)],
                    startPoint: .center,
                    endPoint: .bottom
                )
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On This Day")
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .opacity(0.85)
                }
                .foregroundStyle(cover == nil ? Color(.label) : .white)
                .padding(14)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(cover == nil ? Color(.secondaryLabel) : .white)
                    .padding(14)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onAppear(perform: loadCover)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("On This Day, \(count) photos from previous years")
    }

    private var subtitle: String {
        let date = Date.now.formatted(.dateTime.month(.wide).day())
        return count == 0
            ? "\(date) · No photos in previous years"
            : "\(date) · \(count) photos from previous years"
    }

    private func loadCover() {
        guard cover == nil, let asset = coverAsset else { return }
        let scale = UIScreen.main.scale
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 500 * scale, height: 250 * scale)
        ) { image in
            if let image {
                cover = image
            }
        }
    }
}

/// Cover thumbnail + title + photo count, styled after the iOS 26
/// Photos app album cards: large continuous corner radius, semibold title.
struct AlbumCard: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary

    let album: AlbumItem
    /// Fixed square side for carousel use; nil fills the grid column.
    var side: CGFloat?

    @State private var cover: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color(.secondarySystemBackground)
                .aspectRatio(1, contentMode: .fit)
                .frame(width: side, height: side)
                .overlay {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(album.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)
                Text("\(album.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, alignment: .leading)
        .onAppear(perform: loadCover)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(album.title), \(album.count) photos")
    }

    private func loadCover() {
        guard cover == nil, let asset = album.coverAsset else { return }
        let scale = UIScreen.main.scale
        _ = photoLibrary.requestThumbnail(
            for: asset,
            targetSize: CGSize(width: 300 * scale, height: 300 * scale)
        ) { image in
            if let image {
                cover = image
            }
        }
    }
}
