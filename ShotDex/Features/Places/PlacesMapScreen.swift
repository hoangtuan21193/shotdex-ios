import CoreLocation
import MapKit
import Photos
import SwiftUI
import UIKit

/// Route to the Places map, pushed from the Collections tab.
struct PlacesDestination: Hashable {}

/// Browse the library by where the photos were taken — the map Photos keeps
/// under Places.
///
/// Clustering is done here rather than by MapKit's own annotation clustering:
/// the grid-cell size is derived from the visible span, so zooming out merges
/// neighbours predictably and each cluster can carry its own cover thumbnail
/// and count. MapKit's clustering gives no control over either.
struct PlacesMapScreen: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(PhotoLibraryService.self) private var photoLibrary

    @State private var photos: [LocatedPhoto] = []
    @State private var isLoading = true
    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleSpan: CGFloat = 60
    @State private var selectedCluster: PlaceCluster?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if photos.isEmpty {
                emptyState
            } else {
                map
            }
        }
        .navigationTitle("Places")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .navigationDestination(item: $selectedCluster) { cluster in
            PhotoListScreen(
                title: cluster.title,
                subtitle: cluster.subtitle,
                assetIds: cluster.assetIds
            )
        }
    }

    // MARK: Map

    private var clusters: [PlaceCluster] {
        PlaceClustering.clusters(for: photos, spanDegrees: Double(visibleSpan))
    }

    private var map: some View {
        MapReader { _ in
            Map(position: $camera) {
                ForEach(clusters) { cluster in
                    Annotation(
                        cluster.title,
                        coordinate: cluster.coordinate,
                        anchor: .bottom
                    ) {
                        PlaceClusterPin(cluster: cluster) {
                            selectedCluster = cluster
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .onMapCameraChange(frequency: .onEnd) { context in
                // Re-cluster at the zoom the user settled on, so pins merge and
                // split with the map instead of staying at one fixed grain.
                visibleSpan = CGFloat(
                    max(
                        context.region.span.latitudeDelta,
                        context.region.span.longitudeDelta
                    )
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("None of your indexed photos carry a location yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        photos = (try? await dependencies.libraryQueries.locatedPhotos()) ?? []
    }
}

/// One pin: the cluster's cover thumbnail, with its count when it stands for
/// more than one photo.
private struct PlaceClusterPin: View {
    let cluster: PlaceCluster
    let action: () -> Void

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var cover: UIImage?

    private static let side: CGFloat = 52

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let cover {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.secondarySystemBackground)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .frame(width: Self.side, height: Self.side)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        .strokeBorder(.white, lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

                if cluster.assetIds.count > 1 {
                    Text(cluster.assetIds.count, format: .number)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(.black.opacity(0.75), in: Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cluster.title), \(cluster.assetIds.count) photos")
        .task(id: cluster.coverAssetId) { await loadCover() }
    }

    private func loadCover() async {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [cluster.coverAssetId]).first
        else { return }
        let scale = ActiveDisplay.scale
        let size = CGSize(width: Self.side * scale, height: Self.side * scale)
        cover = await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestThumbnail(for: asset, targetSize: size) { image in
                guard !hasResumed, let image else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
