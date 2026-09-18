import CoreLocation
import MapKit
import Photos
import SwiftUI

/// Location editor for one photo or a whole selection.
///
/// Two ways to set the pin, matching Photos: search for a place by name, or tap
/// the map. A photo that already carries a coordinate can also have it removed,
/// which is the only way to strip GPS from a shot without re-exporting it.
struct AdjustLocationSheet: View {
    let request: AssetActionsCoordinator.LocationRequest
    /// `nil` clears the location.
    let onApply: (CLLocationCoordinate2D?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var picked: CLLocationCoordinate2D?
    @State private var searchText = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private let hadLocation: Bool

    init(
        request: AssetActionsCoordinator.LocationRequest,
        onApply: @escaping (CLLocationCoordinate2D?) -> Void
    ) {
        self.request = request
        self.onApply = onApply
        let seed = request.seed
        hadLocation = seed != nil
        _picked = State(initialValue: seed)
        // A photo with no coordinate opens on a world view rather than a random
        // point, so the first tap is a deliberate choice.
        let center = seed ?? CLLocationCoordinate2D(latitude: 20, longitude: 0)
        let span = seed == nil
            ? MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 120)
            : MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        _camera = State(
            initialValue: .region(MKCoordinateRegion(center: center, span: span))
        )
    }

    private var isBatch: Bool { request.assets.count > 1 }

    private var isChanged: Bool {
        switch (request.seed, picked) {
        case (nil, nil): false
        case let (seed?, picked?):
            abs(seed.latitude - picked.latitude) > 0.000_001
                || abs(seed.longitude - picked.longitude) > 0.000_001
        default: true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                if !results.isEmpty {
                    resultList
                }
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search for a place"
            )
            .onChange(of: searchText) { _, text in scheduleSearch(text) }
            .navigationTitle(isBatch ? "Adjust \(request.assets.count) Photos" : "Adjust Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adjust") {
                        onApply(picked)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isChanged)
                }
                if hadLocation {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Remove Location", role: .destructive) {
                            onApply(nil)
                            dismiss()
                        }
                        .tint(.red)
                    }
                }
            }
        }
    }

    // MARK: Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if let picked {
                    Marker("Location", coordinate: picked)
                        .tint(.red)
                }
            }
            .mapStyle(.standard)
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                withAnimation { picked = coordinate }
            }
            .overlay(alignment: .top) {
                Text(picked == nil
                     ? "Tap the map or search to place this photo."
                     : "Tap the map to move the pin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
    }

    // MARK: Search

    private var resultList: some View {
        List(results, id: \.self) { item in
            Button {
                select(item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Unnamed Place")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle = Self.address(of: item) {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
        .frame(height: 220)
        .overlay(alignment: .top) {
            if isSearching { ProgressView().padding(.top, 8) }
        }
    }

    /// iOS 26 replaced `MKMapItem.placemark` with `location` + `address`; both
    /// paths are kept because the app still ships to iOS 17.
    private static func address(of item: MKMapItem) -> String? {
        if #available(iOS 26.0, *) {
            return item.address?.shortAddress ?? item.address?.fullAddress
        }
        let placemark = item.placemark
        let parts = [placemark.locality, placemark.administrativeArea, placemark.country]
        let joined = parts.compactMap { $0 }.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(iOS 26.0, *) {
            return item.location.coordinate
        }
        return item.placemark.coordinate
    }

    private func select(_ item: MKMapItem) {
        let coordinate = Self.coordinate(of: item)
        picked = coordinate
        camera = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        )
        results = []
        searchText = ""
    }

    /// Debounced place lookup — `MKLocalSearch` is rate-limited, so a request
    /// per keystroke gets throttled and returns nothing.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }
            let plainRequest = MKLocalSearch.Request()
            plainRequest.naturalLanguageQuery = trimmed
            let response = try? await MKLocalSearch(request: plainRequest).start()
            guard !Task.isCancelled else { return }
            results = Array((response?.mapItems ?? []).prefix(12))
        }
    }
}
