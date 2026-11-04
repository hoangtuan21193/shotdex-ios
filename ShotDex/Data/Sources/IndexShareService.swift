import CloudKit
import Foundation
import Photos
import os

/// Shares index results between the devices of one iCloud account through the
/// user's CloudKit private database (intent 2026-11-02-icloud-shared-index).
///
/// Three record types live in one custom zone:
/// - `PhotoExif`, named by the photo's iCloud identifier: the raw EXIF one
///   device read, with the modification date it was read at.
/// - `PlaceCell`, named by cell key: a resolved address, so no other device
///   asks the geocoder about the same ~100 m square again.
/// - `IndexSettings`, one record: whether the Mac indexes for every device.
///
/// Every call is a no-op when sharing is off or there is no iCloud account;
/// indexing then runs exactly as it does without this.
actor IndexShareService: SharedIndexSource {
    static let containerIdentifier = "iCloud.com.hoangtuan.shotdex"
    static let zoneName = "SharedIndex"
    static let settingsRecordName = "IndexSettings"
    /// CloudKit refuses more than 400 records in one modify operation.
    static let pushBatchSize = 400
    /// The photo's modification date on a `PhotoExif` record. Not
    /// `modificationDate`: that name is CloudKit's own system field, and
    /// setting it throws an Objective-C exception that kills the app.
    static let exifModifiedKey = "assetModified"

    private static let logger = Logger(subsystem: "com.hoangtuan.shotdex", category: "IndexShare")

    let store: SharedIndexStore
    private let isEnabled: @Sendable () -> Bool
    private var container: CKContainer?
    private var hasZone = UserDefaults.standard.bool(forKey: SettingsKeys.sharedIndexZoneCreated)

    init(store: SharedIndexStore, isEnabled: @escaping @Sendable () -> Bool = { IndexShareService.sharesIndex }) {
        self.store = store
        self.isEnabled = isEnabled
    }

    /// Defaults to on; read through `object(forKey:)` because `bool(forKey:)`
    /// answers false for a key nobody has written.
    nonisolated static var sharesIndex: Bool {
        UserDefaults.standard.object(forKey: SettingsKeys.sharesIndex) as? Bool ?? true
    }

    /// A Mac build signed without the iCloud capability (no provisioning
    /// profile for it yet, or an unsigned local build) would trap on
    /// `CKContainer(identifier:)`; it shares nothing instead. iOS builds are
    /// always signed with their entitlements, simulator included.
    private static let isEntitled: Bool = {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil) != nil
        #else
        true
        #endif
    }()

    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// The private database, or nil when sharing is off or iCloud is not
    /// signed in. The container is made on first use: making one the app is
    /// not entitled to traps, and tests never get this far.
    private func database(evenWhenOff: Bool = false) async -> CKDatabase? {
        guard evenWhenOff || isEnabled(), Self.isEntitled else { return nil }
        let container = self.container ?? CKContainer(identifier: Self.containerIdentifier)
        self.container = container
        do {
            guard try await container.accountStatus() == .available else { return nil }
        } catch {
            Self.logger.error("account status: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return container.privateCloudDatabase
    }

    private func ensureZone(in database: CKDatabase) async throws {
        guard !hasZone else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        hasZone = true
        UserDefaults.standard.set(true, forKey: SettingsKeys.sharedIndexZoneCreated)
    }

    // MARK: SharedIndexSource

    func sharedExif(for keys: [SharedIndexKey]) async -> [String: RawExif] {
        guard isEnabled(), !keys.isEmpty else { return [:] }
        let cloudIds = Self.cloudIdentifiers(for: keys.map(\.assetId))
        guard !cloudIds.isEmpty,
              let stored = try? store.exif(cloudIdentifiers: Array(Set(cloudIds.values)))
        else { return [:] }
        var result: [String: RawExif] = [:]
        for key in keys {
            guard let cloudId = cloudIds[key.assetId],
                  let record = stored[cloudId],
                  record.modificationDate == key.modificationDate
            else { continue }
            result[key.assetId] = record.exif
        }
        return result
    }

    func share(_ reads: [SharedIndexRead]) async {
        guard isEnabled(), !reads.isEmpty else { return }
        let cloudIds = Self.cloudIdentifiers(for: reads.map(\.key.assetId))
        let records = reads.compactMap { read in
            cloudIds[read.key.assetId].map {
                SharedExifRecord(cloudIdentifier: $0, modificationDate: read.key.modificationDate, exif: read.exif)
            }
        }
        do {
            try store.saveLocal(records)
        } catch {
            Self.logger.error("save local reads: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Local id → iCloud identifier. Photos not yet uploaded to iCloud have
    /// none and are left out: there is nothing another device could match.
    nonisolated static func cloudIdentifiers(for assetIds: [String]) -> [String: String] {
        let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: assetIds)
        var result: [String: String] = [:]
        for (localId, mapping) in mappings {
            if let cloud = try? mapping.get() { result[localId] = cloud.stringValue }
        }
        return result
    }

    // MARK: Pull

    /// Fetches what changed in the zone since the last pull and stores it.
    /// Returns how many photo rows arrived, so the caller knows whether rows
    /// stuck waiting for another device can now be filled.
    @discardableResult
    func pull() async -> Int {
        guard let database = await database() else { return 0 }
        var received = 0
        do {
            try await ensureZone(in: database)
            var token = Self.loadChangeToken()
            var moreComing = true
            while moreComing {
                let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, any Error>],
                              deletions: [CKDatabase.RecordZoneChange.Deletion],
                              changeToken: CKServerChangeToken,
                              moreComing: Bool)
                do {
                    changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                } catch let error as CKError where error.code == .changeTokenExpired {
                    token = nil
                    continue
                }
                var exifRecords: [SharedExifRecord] = []
                var cells: [SharedPlaceCell] = []
                var photoHashes: [SharedPhotoHash] = []
                var serverHashes: [SharedServerHash] = []
                // The newest record's name per device, whatever order the
                // batch comes in.
                var deviceNames: [String: (name: String, at: Date)] = [:]
                func noteName(_ device: String, _ record: CKRecord) {
                    guard let name = record["deviceName"] as? String else { return }
                    let at = record.modificationDate ?? .distantPast
                    if let known = deviceNames[device], known.at > at { return }
                    deviceNames[device] = (name, at)
                }
                for result in changes.modificationResultsByID.values {
                    guard let record = try? result.get().record else { continue }
                    switch record.recordType {
                    case SharedIndexStore.photoExifType:
                        if let exif = Self.exifRecord(from: record) { exifRecords.append(exif) }
                    case SharedIndexStore.placeCellType:
                        if let cell = Self.placeCell(from: record) { cells.append(cell) }
                    case SharedIndexStore.photoHashType:
                        if let hash = Self.photoHash(from: record) {
                            photoHashes.append(hash)
                            noteName(hash.device, record)
                        }
                    case SharedIndexStore.serverHashType:
                        if let hash = Self.serverHash(from: record) {
                            serverHashes.append(hash)
                            noteName(hash.device, record)
                        }
                    case Self.settingsRecordName:
                        Self.applySettings(from: record)
                    default:
                        break
                    }
                }
                received += try store.saveRemote(exifRecords)
                try store.saveRemote(cells)
                try store.saveRemote(photoHashes: photoHashes, serverHashes: serverHashes)
                try store.saveDeviceNames(deviceNames.mapValues(\.name))
                token = changes.changeToken
                Self.saveChangeToken(changes.changeToken)
                moreComing = changes.moreComing
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SettingsKeys.sharedIndexLastSync)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Zone gone (another device reset it, or the user cleared iCloud
            // data): start over on the next pull.
            hasZone = false
            UserDefaults.standard.set(false, forKey: SettingsKeys.sharedIndexZoneCreated)
            Self.saveChangeToken(nil)
        } catch {
            Self.logger.error("pull: \(error.localizedDescription, privacy: .public)")
        }
        if received > 0 { Self.logger.log("pull: \(received) photo rows from other devices") }
        return received
    }

    /// `pull()` bounded by a wait: the launch run waits at most this long for
    /// other devices' results before reading files itself. The pull keeps
    /// going in the background past the deadline; what lands later is adopted
    /// by the caller's next `adoptSharedResults`.
    @discardableResult
    func pull(waitingAtMost limit: Duration) async -> Int {
        let pull = Task { await self.pull() }
        return await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Int) -> Void = { value in
                let isFirst = resumed.withLock { wasResumed in
                    defer { wasResumed = true }
                    return !wasResumed
                }
                if isFirst { continuation.resume(returning: value) }
            }
            Task { finish(await pull.value) }
            Task {
                try? await Task.sleep(for: limit)
                finish(0)
            }
        }
    }

    // MARK: Push

    /// Uploads what is queued in the outbox, 400 records at a time, at most
    /// `batches` of them; stops between batches when cancelled.
    func push(batches: Int = .max) async {
        guard let database = await database() else { return }
        let deviceName = await DeviceDisplayName.current()
        do {
            try await ensureZone(in: database)
            for _ in 0..<batches {
                try Task.checkCancellation()
                let items = try store.outbox(limit: Self.pushBatchSize)
                guard !items.isEmpty else { break }
                let records = try makeRecords(for: items, deviceName: deviceName)
                // `.allKeys` overwrites without a fetch first: each record is
                // one device's answer for one photo, and the newest answer is
                // the one to keep.
                let (saveResults, _) = try await database.modifyRecords(
                    saving: records, deleting: [], savePolicy: .allKeys, atomically: false
                )
                let saved = Set(saveResults.compactMap { id, result in (try? result.get()) != nil ? id.recordName : nil })
                // Rows that vanished locally (no record built) leave the queue too.
                let built = Set(records.map(\.recordID.recordName))
                try store.removeFromOutbox(items.filter { saved.contains($0.recordName) || !built.contains($0.recordName) })
                if saved.isEmpty && !built.isEmpty { break }
            }
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SettingsKeys.sharedIndexLastSync)
        } catch {
            Self.logger.error("push: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeRecords(for items: [SharedIndexStore.OutboxItem], deviceName: String?) throws -> [CKRecord] {
        let exifIds = items.filter { $0.recordType == SharedIndexStore.photoExifType }.map(\.recordName)
        let cellKeys = items.filter { $0.recordType == SharedIndexStore.placeCellType }.map(\.recordName)
        var records: [CKRecord] = []
        let encoder = JSONEncoder()
        for row in try store.exif(cloudIdentifiers: exifIds).values {
            let record = CKRecord(recordType: SharedIndexStore.photoExifType,
                                  recordID: CKRecord.ID(recordName: row.cloudIdentifier, zoneID: zoneID))
            record[Self.exifModifiedKey] = row.modificationDate.map { Int64($0) }
            record["exif"] = try encoder.encode(row.exif)
            records.append(record)
        }
        for cell in try store.placeCells(keys: cellKeys) {
            let record = CKRecord(recordType: SharedIndexStore.placeCellType,
                                  recordID: CKRecord.ID(recordName: cell.cellKey, zoneID: zoneID))
            record["cell"] = try encoder.encode(PlaceCellWire(cell))
            records.append(record)
        }
        // FS-19.07 §12.3: file hashes, one record per device and file.
        let hashNames = items.filter { $0.recordType == SharedIndexStore.photoHashType || $0.recordType == SharedIndexStore.serverHashType }
            .map(\.recordName)
        let hashes = try store.localHashes(recordNames: hashNames)
        for hash in hashes.photos {
            let record = CKRecord(recordType: SharedIndexStore.photoHashType, recordID: CKRecord.ID(recordName: hash.recordName, zoneID: zoneID))
            record["cloudId"] = hash.cloudId
            record["fileKey"] = hash.fileKey
            record["assetModified"] = hash.assetModified.map { Int64($0) }
            record["size"] = hash.size
            record["sha256"] = hash.sha256
            record["device"] = hash.device
            // Whose hashes a random check found wrong, in words (§12.4).
            record["deviceName"] = deviceName
            record["hashedAt"] = Int64(hash.hashedAt)
            records.append(record)
        }
        for hash in hashes.servers {
            let record = CKRecord(recordType: SharedIndexStore.serverHashType, recordID: CKRecord.ID(recordName: hash.recordName, zoneID: zoneID))
            record["serverKey"] = hash.serverKey
            record["pathKey"] = hash.pathKey
            record["size"] = hash.size
            record["modifiedAt"] = hash.modifiedAt.map { Int64($0) }
            record["sha256"] = hash.sha256
            record["device"] = hash.device
            record["deviceName"] = deviceName
            record["hashedAt"] = Int64(hash.hashedAt)
            records.append(record)
        }
        return records
    }

    // MARK: Mac indexes for every device

    /// Mac only: tells the other devices whether to leave iCloud reads to the
    /// Mac. Written to the zone, so it reaches them with their next pull —
    /// even when sharing was just turned off, which is when "off" matters.
    func publishMacIndexesForAll(_ isOn: Bool, deviceName: String) async {
        guard let database = await database(evenWhenOff: true) else { return }
        do {
            try await ensureZone(in: database)
            let record = CKRecord(recordType: Self.settingsRecordName,
                                  recordID: CKRecord.ID(recordName: Self.settingsRecordName, zoneID: zoneID))
            record["macIndexesForAll"] = isOn ? 1 : 0
            record["macName"] = deviceName
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
        } catch {
            Self.logger.error("publish settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func applySettings(from record: CKRecord) {
        let isOn = (record["macIndexesForAll"] as? Int64 ?? 0) != 0
        UserDefaults.standard.set(isOn, forKey: SettingsKeys.macIndexesForAll)
        UserDefaults.standard.set(record["macName"] as? String, forKey: SettingsKeys.macIndexesForAllName)
    }

    // MARK: Decoding

    private static func exifRecord(from record: CKRecord) -> SharedExifRecord? {
        guard let data = record["exif"] as? Data,
              let exif = try? JSONDecoder().decode(RawExif.self, from: data)
        else { return nil }
        return SharedExifRecord(
            cloudIdentifier: record.recordID.recordName,
            modificationDate: (record[exifModifiedKey] as? Int64).map { Int($0) },
            exif: exif
        )
    }

    private static func photoHash(from record: CKRecord) -> SharedPhotoHash? {
        guard let cloudId = record["cloudId"] as? String, let fileKey = record["fileKey"] as? String,
              let sha256 = record["sha256"] as? String, let device = record["device"] as? String,
              let hashedAt = record["hashedAt"] as? Int64 else { return nil }
        return SharedPhotoHash(cloudId: cloudId, fileKey: fileKey, assetModified: (record["assetModified"] as? Int64).map { Int($0) },
                               size: record["size"] as? Int64, sha256: sha256, device: device, hashedAt: Int(hashedAt))
    }

    private static func serverHash(from record: CKRecord) -> SharedServerHash? {
        guard let serverKey = record["serverKey"] as? String, let pathKey = record["pathKey"] as? String,
              let size = record["size"] as? Int64, let sha256 = record["sha256"] as? String,
              let device = record["device"] as? String, let hashedAt = record["hashedAt"] as? Int64 else { return nil }
        return SharedServerHash(serverKey: serverKey, pathKey: pathKey, size: size, modifiedAt: (record["modifiedAt"] as? Int64).map { Int($0) },
                                sha256: sha256, device: device, hashedAt: Int(hashedAt))
    }

    private static func placeCell(from record: CKRecord) -> SharedPlaceCell? {
        guard let data = record["cell"] as? Data,
              let wire = try? JSONDecoder().decode(PlaceCellWire.self, from: data)
        else { return nil }
        return wire.cell(key: record.recordID.recordName)
    }

    private static func loadChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.sharedIndexChangeToken) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func saveChangeToken(_ token: CKServerChangeToken?) {
        let data = token.flatMap { try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }
        UserDefaults.standard.set(data, forKey: SettingsKeys.sharedIndexChangeToken)
    }
}

/// `SharedPlaceCell` on the wire, minus the key (that is the record name).
private struct PlaceCellWire: Codable {
    var latitude: Double
    var longitude: Double
    var name: String?
    var subLocality: String?
    var locality: String?
    var adminArea: String?
    var country: String?
    var countryCode: String?
    var address: String?
    var searchText: String?
    var localeIdentifier: String
    var resolvedAt: Int

    init(_ cell: SharedPlaceCell) {
        latitude = cell.latitude
        longitude = cell.longitude
        name = cell.place.name
        subLocality = cell.place.subLocality
        locality = cell.place.locality
        adminArea = cell.place.adminArea
        country = cell.place.country
        countryCode = cell.place.countryCode
        address = cell.place.address
        searchText = cell.searchText
        localeIdentifier = cell.localeIdentifier
        resolvedAt = cell.resolvedAt
    }

    func cell(key: String) -> SharedPlaceCell {
        SharedPlaceCell(
            cellKey: key, latitude: latitude, longitude: longitude,
            place: ResolvedPlace(
                name: name, subLocality: subLocality, locality: locality, adminArea: adminArea,
                country: country, countryCode: countryCode, address: address
            ),
            searchText: searchText, localeIdentifier: localeIdentifier, resolvedAt: resolvedAt
        )
    }
}
