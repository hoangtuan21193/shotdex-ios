import Foundation

/// How much of a photo's metadata goes with it when it leaves the app
/// (FS-08.06 §3). One value in Settings is the default for every way out —
/// Share, Save Copy, Paste Edits, Resize, drag — and Share can change it for
/// one share.
///
/// In the kit because the renderer's `write` takes it; nothing here touches
/// SwiftUI or GRDB.
public enum MetadataLevel: String, CaseIterable, Codable, Sendable {
    /// Everything, and the original file's bytes untouched.
    case all
    /// Everything except where the photo was taken: the GPS group, the
    /// subject's position and the IPTC/XMP place names.
    case noLocation
    /// Nothing but what the picture needs to look right — orientation and
    /// colour profile — and the author's Artist and Copyright.
    case noMetadata

    /// Whether this level removes the location.
    public var removesLocation: Bool { self != .all }
}
