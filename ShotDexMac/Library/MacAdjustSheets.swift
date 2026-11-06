import CoreLocation
import GRDB
import MapKit
import Photos
import SwiftUI

/// Get Info's Date › Adjust… and Location › Adjust… (FS-18.02 §8), for a
/// photo in Photos: the change goes to Photos, as Photos' own Adjust Date and
/// Time does — the original file's EXIF is left as it is — and the index
/// follows. A folder photo's date and place are its file's.
@MainActor
struct MacAdjustWriter {
    let dependencies: MacDependencies

    enum Outcome { case done, failed(String) }

    func setDate(_ date: Date, id: String) async -> Outcome {
        let metadataStore = dependencies.metadataStore
        return await write(id: id, change: { request in request.creationDate = date },
                           landed: { asset in asset.creationDate.map { abs($0.timeIntervalSince(date)) < 1 } ?? false }) {
            try? metadataStore.updateCreationDate(assetIds: [id], date: date)
        }
    }

    func setLocation(_ coordinate: CLLocationCoordinate2D?, id: String) async -> Outcome {
        let metadataStore = dependencies.metadataStore
        let latitude = coordinate?.latitude, longitude = coordinate?.longitude
        let location = latitude.flatMap { lat in longitude.map { CLLocation(latitude: lat, longitude: $0) } }
        return await write(id: id, change: { request in request.location = location },
                           landed: { asset in
                               switch (asset.location?.coordinate, coordinate) {
                               case (nil, nil): true
                               case let (a?, b?): abs(a.latitude - b.latitude) < 1e-6 && abs(a.longitude - b.longitude) < 1e-6
                               default: false
                               }
                           }) {
            try? metadataStore.updateLocation(assetIds: [id], latitude: latitude, longitude: longitude)
        }
    }

    /// Photos first, on the photo's own asset (a merged photo's id is not its
    /// PhotoKit id), and only where Photos allows a property edit; the change
    /// is read back before the index follows. The index is a mirror: a
    /// failure to write it is not the user's failure.
    private func write(id: String, change: @escaping @Sendable (PHAssetChangeRequest) -> Void,
                       landed: @escaping @Sendable (PHAsset) -> Bool,
                       mirror: @escaping @Sendable () -> Void) async -> Outcome {
        #if DEBUG
        // The demo has no Photos assets: only its rows change, and Photos is
        // never asked, even for an id that might exist there.
        if MacDemoLibrary.isOn {
            await Task.detached(priority: .userInitiated) { mirror() }.value
            return .done
        }
        #endif
        let database = dependencies.database
        let asset = await Task.detached(priority: .userInitiated) { () -> PHAsset? in
            let photoKitId = (try? database.reader.read { db in
                try String.fetchOne(db, sql: "SELECT photoKitId FROM photo_copies WHERE photoId = ? AND kind = 'photos' AND photoKitId IS NOT NULL",
                                    arguments: [id])
            }) ?? nil
            return PhotoLibraryService.fetchAssets(ids: [photoKitId ?? id]).first
        }.value
        guard let asset else {
            return .failed(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited
                ? String(localized: "This photo isn’t among the photos you’ve allowed ShotDex to use.", comment: "Mac adjust: limited access")
                : String(localized: "Photos no longer has this photo.", comment: "Mac adjust: the asset is gone"))
        }
        guard asset.canPerform(.properties) else {
            return .failed(String(localized: "Photos doesn’t allow changing this photo (it may be in a shared library).",
                                  comment: "Mac adjust: Photos refuses property edits"))
        }
        do {
            try await PHPhotoLibrary.shared().performChanges { change(PHAssetChangeRequest(for: asset)) }
        } catch {
            return .failed(error.localizedDescription)
        }
        let assetId = asset.localIdentifier
        let didLand = await Task.detached(priority: .userInitiated) {
            PhotoLibraryService.fetchAssets(ids: [assetId]).first.map(landed) ?? false
        }.value
        guard didLand else {
            return .failed(String(localized: "Photos didn’t take the change.", comment: "Mac adjust: the write did not land"))
        }
        await Task.detached(priority: .userInitiated) { mirror() }.value
        dependencies.photoLibrary.publishAppCreatedAsset()
        return .done
    }
}

/// Date › Adjust…: a calendar and a time, what the change moves by, and
/// what it does not touch.
struct MacAdjustDateSheet: View {
    /// Nil: the photo has no date yet; the sheet starts from now.
    let original: Date?
    let apply: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(original: Date?, apply: @escaping (Date) -> Void) {
        self.original = original
        self.apply = apply
        _date = State(initialValue: original ?? Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Adjust Date and Time", comment: "Mac adjust date: title").font(.headline)
            HStack(alignment: .top, spacing: 16) {
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time", comment: "Mac adjust date: time field").font(.system(size: 12)).foregroundStyle(.secondary)
                    DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                    // The Mac's own time zone, which may not be where the photo was taken.
                    Text(TimeZone.current.localizedName(for: .shortGeneric, locale: .current) ?? TimeZone.current.identifier)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    if let original {
                        Text(original.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .accessibilityLabel(String(localized: "Original: \(original.formatted(date: .abbreviated, time: .shortened))",
                                                       comment: "Mac adjust date: the date before"))
                        if let shift = MacAdjustText.shift(from: original, to: date) {
                            Text(shift).font(.system(size: 11, weight: .medium))
                        }
                    }
                }
            }
            Text("The date in the original file stays as it is, as in Photos.", comment: "Mac adjust date: what it does not change")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Mac adjust: close")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Adjust", comment: "Mac adjust date: apply")) {
                    apply(date)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(original.map { abs(date.timeIntervalSince($0)) < 1 } ?? false)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

/// Location › Adjust…: a map to click, a place to search, or no place.
struct MacAdjustLocationSheet: View {
    let original: CLLocationCoordinate2D?
    let apply: (CLLocationCoordinate2D?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searchTask: Task<Void, Never>?
    /// A picked result's name goes in the field without searching again.
    @State private var isPicking = false
    @State private var searchNote: String?

    init(original: CLLocationCoordinate2D?, apply: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.original = original
        self.apply = apply
        _pin = State(initialValue: original)
        let center = original ?? CLLocationCoordinate2D(latitude: 20, longitude: 0)
        let span = original == nil ? MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 160)
                                   : MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        _camera = State(initialValue: .region(MKCoordinateRegion(center: center, span: span)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Adjust Location", comment: "Mac adjust location: title").font(.headline)
            TextField(String(localized: "Search for a place", comment: "Mac adjust location: search field"), text: $query)
                .textFieldStyle(.roundedBorder)
                .onChange(of: query) { _, text in
                    if isPicking { isPicking = false; return }
                    search(text)
                }
                // Return takes the first place found.
                .onSubmit { if let first = results.first { pick(first) } }
            if let searchNote {
                Text(searchNote).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            MapReader { proxy in
                Map(position: $camera) {
                    if let pin {
                        Marker(String(localized: "Photo location", comment: "Mac adjust location: the pin"), coordinate: pin)
                            .tint(MacTheme.accent)
                    }
                }
                .onTapGesture { point in
                    if let coordinate = proxy.convert(point, from: .local) { pin = coordinate }
                }
            }
            .frame(height: 280)
            // Search results over the map, so the sheet keeps its height.
            .overlay(alignment: .top) {
                if !results.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { _, item in
                            Button {
                                pick(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.name ?? "").font(.system(size: 13))
                                    if let address = MacAdjustText.address(of: item) {
                                        Text(address).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel(String(localized: "Map — click to place the photo, or search for a place", comment: "Mac adjust location: map, VoiceOver"))
            HStack {
                Text(MacAdjustText.coordinates(pin) ?? String(localized: "No location", comment: "Mac adjust location: none"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                if original != nil {
                    Button(String(localized: "Remove Location", comment: "Mac adjust location: clear")) {
                        apply(nil)
                        dismiss()
                    }
                }
                // Escape closes the list of places first, the sheet after.
                Button(String(localized: "Cancel", comment: "Mac adjust: close")) {
                    if results.isEmpty { dismiss() } else { results = [] }
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "Adjust", comment: "Mac adjust location: apply")) {
                    apply(pin)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pin == nil || MacAdjustText.same(pin, original))
            }
        }
        .padding(20)
        // A sheet on the 420pt Get Info panel.
        .frame(width: 400)
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let text = text.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; searchNote = nil; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            do {
                let found = try await MKLocalSearch(request: request).start().mapItems
                guard !Task.isCancelled else { return }
                results = found
                searchNote = found.isEmpty ? String(localized: "No places found.", comment: "Mac adjust location: search found nothing") : nil
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchNote = (error as? MKError)?.code == .placemarkNotFound
                    ? String(localized: "No places found.", comment: "Mac adjust location: search found nothing")
                    : String(localized: "Places can’t be searched right now — check the connection, or click the map.",
                             comment: "Mac adjust location: search failed")
            }
        }
    }

    private func pick(_ item: MKMapItem) {
        let coordinate = MacAdjustText.coordinate(of: item)
        pin = coordinate
        camera = .region(MKCoordinateRegion(center: coordinate, span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)))
        results = []
        searchNote = nil
        isPicking = true
        query = item.name ?? query
    }
}

enum MacAdjustText {
    /// A search result's place and line, through the API of the running macOS.
    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(macOS 26, *) { return item.location.coordinate }
        return item.placemark.coordinate
    }

    static func address(of item: MKMapItem) -> String? {
        if #available(macOS 26, *) { return item.address?.shortAddress }
        return item.placemark.title
    }

    /// "Later by 2 hours, 5 minutes".
    static func shift(from original: Date, to date: Date) -> String? {
        let delta = date.timeIntervalSince(original)
        guard abs(delta) >= 60 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.year, .month, .day, .hour, .minute]
        formatter.maximumUnitCount = 2
        guard let amount = formatter.string(from: abs(delta)) else { return nil }
        return delta > 0 ? String(localized: "Later by \(amount)", comment: "Mac adjust date: the change, forward")
                         : String(localized: "Earlier by \(amount)", comment: "Mac adjust date: the change, back")
    }

    static func coordinates(_ coordinate: CLLocationCoordinate2D?) -> String? {
        coordinate.map { String(format: "%.4f°, %.4f°", $0.latitude, $0.longitude) }
    }

    static func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): abs(a.latitude - b.latitude) < 1e-6 && abs(a.longitude - b.longitude) < 1e-6
        default: false
        }
    }
}
