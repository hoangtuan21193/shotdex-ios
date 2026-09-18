import CoreLocation
import Photos
import SwiftUI
import UIKit

/// The library mutations that every photo surface offers — favorite, hide,
/// capture-date and location correction, copy to the pasteboard — in one place,
/// together with the sheets two of them need.
///
/// Library, Album Detail, Smart Album Detail, On This Day and the detail viewer
/// all trigger the same actions on the same kind of payload (a set of asset
/// ids), so they share one coordinator instead of each re-implementing the
/// PhotoKit call, the progress flag and the error alert. Presentation state
/// lives here; a host attaches the actual sheets with `.assetActionHost(_:)`.
///
/// Two hosts exist because the detail viewer is a `fullScreenCover` and cannot
/// be reached by a sheet presented from the root — `RootTabView` covers every
/// grid, `PhotoDetailScreen` covers itself.
@MainActor
@Observable
final class AssetActionsCoordinator {
    /// Asks the host to show the capture-date editor.
    struct DateRequest: Identifiable {
        let id = UUID()
        let assets: [PHAsset]
        /// Seed for the picker: the earliest capture date in the selection, or
        /// now when none of them carry one.
        var seed: Date {
            assets.compactMap(\.creationDate).min() ?? Date()
        }
    }

    /// Asks the host to show the location editor.
    struct LocationRequest: Identifiable {
        let id = UUID()
        let assets: [PHAsset]
        /// Seed for the map pin: the first coordinate in the selection.
        var seed: CLLocationCoordinate2D? {
            assets.compactMap(\.location).first?.coordinate
        }
    }

    private let photoLibrary: PhotoLibraryService

    var dateRequest: DateRequest?
    var locationRequest: LocationRequest?
    var errorMessage: String?
    /// Short confirmation for actions with no visible result of their own
    /// (Copy, Hide). Cleared by the host after it fades.
    var toastMessage: String?
    private(set) var isWorking = false

    init(photoLibrary: PhotoLibraryService) {
        self.photoLibrary = photoLibrary
    }

    // MARK: Favorite

    /// Whether every asset in `ids` is already a favorite — drives the menu
    /// label ("Favorite" vs "Unfavorite") the way Photos flips it.
    func areAllFavorites(ids: [String]) -> Bool {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        return !assets.isEmpty && assets.allSatisfy(\.isFavorite)
    }

    /// Favorites the whole selection, or un-favorites it when every asset is
    /// already a favorite.
    func toggleFavorite(ids: [String]) {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        guard !assets.isEmpty else { return }
        let makeFavorite = !assets.allSatisfy(\.isFavorite)
        perform {
            try await self.photoLibrary.setFavorite(makeFavorite, for: assets)
        }
    }

    func setFavorite(_ isFavorite: Bool, ids: [String]) {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        guard !assets.isEmpty else { return }
        perform {
            try await self.photoLibrary.setFavorite(isFavorite, for: assets)
        }
    }

    // MARK: Hide

    func areAllHidden(ids: [String]) -> Bool {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        return !assets.isEmpty && assets.allSatisfy(\.isHidden)
    }

    /// Hides the selection, or unhides it when everything is already hidden.
    func toggleHidden(ids: [String]) {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        guard !assets.isEmpty else { return }
        let hide = !assets.allSatisfy(\.isHidden)
        perform {
            try await self.photoLibrary.setHidden(hide, for: assets)
            self.toastMessage = hide
                ? (assets.count == 1 ? "Photo Hidden" : "\(assets.count) Photos Hidden")
                : (assets.count == 1 ? "Photo Unhidden" : "\(assets.count) Photos Unhidden")
        }
    }

    // MARK: Capture date / location

    func presentAdjustDate(ids: [String]) {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        guard !assets.isEmpty else { return }
        dateRequest = DateRequest(assets: assets)
    }

    func presentAdjustLocation(ids: [String]) {
        let assets = PhotoLibraryService.fetchAssets(ids: ids)
        guard !assets.isEmpty else { return }
        locationRequest = LocationRequest(assets: assets)
    }

    /// Applies the date picked in the sheet.
    ///
    /// One photo takes the value as-is. A selection keeps its internal spacing
    /// and shifts as a block by the delta from its earliest photo, which is what
    /// Photos does when several are adjusted at once.
    func applyDate(_ date: Date, to request: DateRequest) {
        let assets = request.assets
        perform {
            if assets.count == 1 {
                try await self.photoLibrary.setCreationDate(date, for: assets)
            } else {
                let delta = date.timeIntervalSince(request.seed)
                try await self.photoLibrary.shiftCreationDates(by: delta, for: assets)
            }
        }
    }

    func applyLocation(_ coordinate: CLLocationCoordinate2D?, to request: LocationRequest) {
        let assets = request.assets
        let location = coordinate.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        perform {
            try await self.photoLibrary.setLocation(location, for: assets)
        }
    }

    // MARK: Pasteboard

    /// Puts the asset's full-size image on the general pasteboard, the way the
    /// Photos context menu's "Copy" does. iCloud originals are downloaded.
    func copyToPasteboard(id: String) {
        guard let asset = PhotoLibraryService.fetchAssets(ids: [id]).first else { return }
        perform {
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            options.deliveryMode = .highQualityFormat
            let data: Data? = await withCheckedContinuation { continuation in
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, _, _, _ in continuation.resume(returning: data) }
            }
            guard let data, let image = UIImage(data: data) else {
                throw AssetActionError.copyFailed
            }
            UIPasteboard.general.image = image
            self.toastMessage = "Copied"
        }
    }

    // MARK: Plumbing

    private func perform(_ work: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await work()
            } catch {
                // PhotoKit raises this when the user declines its own
                // confirmation sheet; that is a cancel, not a failure.
                let nsError = error as NSError
                let cancelled = nsError.domain == PHPhotosErrorDomain
                    && nsError.code == PHPhotosError.userCancelled.rawValue
                if !cancelled {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

enum AssetActionError: LocalizedError {
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .copyFailed: "Couldn't copy this photo."
        }
    }
}

// MARK: - Host

extension View {
    /// Attaches the sheets, error alert and confirmation toast the coordinator
    /// drives. Applied by every surface that can present over the user's current
    /// context: the root tab view for the grids, the detail viewer for itself.
    func assetActionHost(_ coordinator: AssetActionsCoordinator) -> some View {
        modifier(AssetActionHost(coordinator: coordinator))
    }
}

private struct AssetActionHost: ViewModifier {
    @Bindable var coordinator: AssetActionsCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(item: $coordinator.dateRequest) { request in
                AdjustDateTimeSheet(request: request) { date in
                    coordinator.applyDate(date, to: request)
                }
            }
            .sheet(item: $coordinator.locationRequest) { request in
                AdjustLocationSheet(request: request) { coordinate in
                    coordinator.applyLocation(coordinate, to: request)
                }
            }
            .alert(
                "Couldn't Update Photos",
                isPresented: Binding(
                    get: { coordinator.errorMessage != nil },
                    set: { if !$0 { coordinator.errorMessage = nil } }
                ),
                presenting: coordinator.errorMessage
            ) { _ in
                Button("OK", role: .cancel) { coordinator.errorMessage = nil }
            } message: { message in
                Text(message)
            }
            .overlay(alignment: .bottom) {
                if let toast = coordinator.toastMessage {
                    ActionToast(text: toast)
                        .padding(.bottom, 120)
                        .transition(.opacity)
                        .task(id: toast) {
                            try? await Task.sleep(for: .seconds(1.6))
                            withAnimation { coordinator.toastMessage = nil }
                        }
                }
            }
            .animation(.snappy(duration: 0.2), value: coordinator.toastMessage)
    }
}

/// A brief glass capsule confirming an action that leaves no visible trace.
private struct ActionToast: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 20)
            .frame(height: 44)
            .glassBackground(Capsule())
            .allowsHitTesting(false)
    }
}
