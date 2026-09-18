import Photos
import SwiftUI
import UIKit

/// Route to the Trips list, pushed from the Collections tab.
struct TripsDestination: Hashable {}

/// Every journey the app found in the library, newest first — the band Photos
/// calls Trips.
///
/// Each row is a wide cover with the place and the dates over it, so the list
/// reads like a set of postcards rather than a table.
struct TripsScreen: View {
    @Environment(AppDependencies.self) private var dependencies

    @State private var trips: [Trip] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if trips.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Trips")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(trips) { trip in
                    NavigationLink {
                        PhotoListScreen(
                            title: trip.title,
                            subtitle: trip.dateRangeLabel,
                            assetIds: trip.assetIds
                        )
                    } label: {
                        TripCard(trip: trip)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("No trips yet. A trip is several days of photos taken well away from where you usually shoot.")
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
        let photos = (try? await dependencies.libraryQueries.locatedPhotos()) ?? []
        trips = await Task.detached(priority: .userInitiated) {
            TripGrouping.trips(from: photos)
        }.value
    }
}

/// One trip as a wide cover with its name and dates burned into the bottom.
struct TripCard: View {
    let trip: Trip

    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var cover: UIImage?

    static let height: CGFloat = 160

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let cover {
                    Image(uiImage: cover)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(.secondarySystemBackground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(trip.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(trip.dateRangeLabel) · \(trip.assetIds.count) photos")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(12)
        }
        .frame(height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(trip.title), \(trip.dateRangeLabel), \(trip.assetIds.count) photos")
        .task(id: trip.coverAssetId) { await loadCover() }
    }

    private func loadCover() async {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [trip.coverAssetId]).first
        else { return }
        let scale = ActiveDisplay.scale
        let size = CGSize(
            width: ActiveDisplay.size.width * scale,
            height: Self.height * scale
        )
        cover = await withCheckedContinuation { continuation in
            var hasResumed = false
            _ = photoLibrary.requestAlbumCover(for: asset, targetSize: size, allowNetwork: true) { image in
                guard !hasResumed, let image else { return }
                hasResumed = true
                continuation.resume(returning: image)
            }
        }
    }
}
