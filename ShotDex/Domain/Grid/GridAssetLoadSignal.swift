import Foundation

/// "Assets for some rows have been fetched" from a grid's model straight to
/// its collection view (see `registerAssetLoadSignal`).
@MainActor
final class GridAssetLoadSignal {
    var handler: (() -> Void)?

    func fire() { handler?() }
}
