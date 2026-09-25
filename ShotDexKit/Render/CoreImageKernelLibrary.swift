import CoreImage
import Foundation

/// The Core Image kernels a bundle ships, compiled from Metal at build time
/// (FS-16).
///
/// A kernel with a syntax error fails the build, so the only way left to lose
/// one at run time is to ask for it by the wrong name or ship without the
/// metallib. Debug builds stop on that; release builds get `nil`, and every
/// call site already treats a missing kernel as "leave the image as it came
/// in". A test loads every kernel by name, so neither case reaches a release.
public struct CoreImageKernelLibrary: Sendable {
    /// The kit's own kernels, from the framework's bundle — not the app's,
    /// which has a metallib of its own. Internal: outside the kit, only the
    /// type is reused, for the app's own bundle.
    static let kit = CoreImageKernelLibrary(bundle: Bundle(for: KitBundleToken.self))

    /// The whole metallib, read once. Core Image compiles each function out
    /// of it on first use.
    private let data: Data?

    public init(bundle: Bundle) {
        data = bundle.url(forResource: "default", withExtension: "metallib")
            .flatMap { try? Data(contentsOf: $0) }
    }

    public func colorKernel(named name: String) -> CIColorKernel? {
        load(name) { try CIColorKernel(functionName: name, fromMetalLibraryData: $0) }
    }

    public func warpKernel(named name: String) -> CIWarpKernel? {
        load(name) { try CIWarpKernel(functionName: name, fromMetalLibraryData: $0) }
    }

    public func kernel(named name: String) -> CIKernel? {
        load(name) { try CIKernel(functionName: name, fromMetalLibraryData: $0) }
    }

    /// `onMissing` is the debug stop; a test swaps it for a no-op to see the
    /// release behaviour.
    func load<Kernel>(
        _ name: String,
        onMissing: (String) -> Void = { assertionFailure($0) },
        _ make: (Data) throws -> Kernel
    ) -> Kernel? {
        guard let data else {
            onMissing("No default.metallib: Core Image kernel \(name) is unavailable")
            return nil
        }
        do {
            return try make(data)
        } catch {
            onMissing("Core Image kernel \(name) did not load: \(error)")
            return nil
        }
    }
}

private final class KitBundleToken {}
