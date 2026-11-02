import Foundation

/// Keeps an index run alive while the app is not frontmost: a background
/// task on iOS (`BackgroundIndexService`), an activity on the Mac.
@MainActor
protocol IndexRunAssertion: AnyObject {
    func beginRunAssertion(onExpiry: @escaping @MainActor () -> Void)
    func endRunAssertion()
}

/// What `LibraryModel` needs from the composition root — the iOS
/// `AppDependencies` and the Mac's `MacDependencies` both provide it, so one
/// model serves both apps (FS-18 K1).
@MainActor
protocol LibraryServices: AnyObject {
    var libraryQueries: LibraryQueries { get }
    var filterSuggestions: FilterSuggestionCache { get }
    var metadataStore: MetadataStore { get }
    var indexPipeline: IndexPipeline { get }
    var placeIndexPass: PlaceIndexPass { get }
    var keywordMirror: ExtendedMetadataMirrorPass? { get }
    var unsupportedRAWIndex: UnsupportedRAWIndex { get }
    var indexRunAssertion: any IndexRunAssertion { get }
    var photoLibrary: PhotoLibraryService { get }
    var networkStatus: NetworkMonitor { get }
    var powerStatus: PowerMonitor { get }
    var indexTraffic: IndexTrafficMonitor { get }
    /// Index results shared with the other devices on this iCloud account.
    var indexShare: IndexShareService? { get }
}
