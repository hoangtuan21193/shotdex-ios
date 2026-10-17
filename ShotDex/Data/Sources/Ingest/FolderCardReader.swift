import Foundation

/// A card that shows up as a folder: a card reader or a camera in USB mass
/// storage mode, picked once in Files (FS-20 §4), or a `DCIM` folder in a
/// test. Reads straight from the card, one chunk at a time.
struct FolderCardReader: CardReader {
    let root: URL
    let name: String

    init(root: URL, name: String? = nil) {
        self.root = root
        self.name = name ?? root.lastPathComponent
    }

    func list() async throws -> [CardFile] {
        guard isConnected else { throw IngestFailure.cardDisconnected }
        return Self.files(under: root)
    }

    private static func files(under root: URL) -> [CardFile] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        let rootPath = root.standardizedFileURL.path
        var files: [CardFile] = []
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory != true else { continue }
            var path = url.standardizedFileURL.path
            if path.hasPrefix(rootPath) { path.removeFirst(rootPath.count) }
            if path.hasPrefix("/") { path.removeFirst() }
            files.append(CardFile(path: path, size: Int64(values?.fileSize ?? 0), modified: values?.contentModificationDate))
        }
        return files
    }

    var isConnected: Bool { (try? root.checkResourceIsReachable()) == true }

    func read(_ path: String, chunkSize: Int, _ body: (Data) throws -> Void) async throws {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: root.appendingPathComponent(path))
        } catch {
            throw isConnected ? IngestFailure.unreadable : IngestFailure.cardDisconnected
        }
        defer { try? handle.close() }
        while true {
            try Task.checkCancellation()
            let data: Data?
            do {
                data = try handle.read(upToCount: chunkSize)
            } catch {
                throw isConnected ? IngestFailure.unreadable : IngestFailure.cardDisconnected
            }
            guard let data, !data.isEmpty else { return }
            try body(data)
        }
    }
}
