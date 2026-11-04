import Foundation
import Testing
@testable import ShotDex

/// FS-19.07 §5: one server call at a time per connection, Backup first, and
/// the lock free between calls so a long backup does not starve the index.
@Suite struct ConnectionLockTests {
    private actor Log {
        private(set) var entries: [String] = []
        private var inside = 0
        private(set) var maxInside = 0
        func add(_ entry: String) { entries.append(entry) }
        func enter() { inside += 1; maxInside = max(maxInside, inside) }
        func leave() { inside -= 1 }
    }

    private static func waitUntil(_ lock: ConnectionLock, _ id: String, waiting count: Int) async {
        while await lock.waitingCount(id) < count { await Task.yield() }
    }

    /// An index call and a backup call both wait behind the holder: the
    /// backup call goes first even though it queued second.
    @Test func backupFirst() async {
        let lock = ConnectionLock()
        let log = Log()
        await lock.acquire("nas", priority: .normal)
        let index = Task { await lock.acquire("nas", priority: .normal); await log.add("index"); await lock.release("nas") }
        await Self.waitUntil(lock, "nas", waiting: 1)
        let backup = Task { await lock.acquire("nas", priority: .backup); await log.add("backup"); await lock.release("nas") }
        await Self.waitUntil(lock, "nas", waiting: 2)
        await lock.release("nas")
        await index.value
        await backup.value
        #expect(await log.entries == ["backup", "index"])
    }

    /// AC-184: Compare queued first, a scan's call second — the scan's goes
    /// first; Compare only runs when nothing else waits.
    @Test func compareWaitsForEveryone() async {
        let lock = ConnectionLock()
        let log = Log()
        await lock.acquire("nas", priority: .normal)
        let compare = Task { await lock.acquire("nas", priority: .compare); await log.add("compare"); await lock.release("nas") }
        await Self.waitUntil(lock, "nas", waiting: 1)
        let scan = Task { await lock.acquire("nas", priority: .normal); await log.add("scan"); await lock.release("nas") }
        await Self.waitUntil(lock, "nas", waiting: 2)
        await lock.release("nas")
        await compare.value
        await scan.value
        #expect(await log.entries == ["scan", "compare"])
    }

    /// Backup finishes one file and asks again: the index call that was
    /// already waiting gets the connection in between.
    @Test func yieldsBetweenFiles() async {
        let lock = ConnectionLock()
        let log = Log()
        await lock.acquire("nas", priority: .backup)
        let index = Task { await lock.acquire("nas", priority: .normal); await log.add("index"); await lock.release("nas") }
        await Self.waitUntil(lock, "nas", waiting: 1)
        await lock.release("nas")
        await lock.acquire("nas", priority: .backup)
        await log.add("backup file 2")
        await lock.release("nas")
        await index.value
        #expect(await log.entries == ["index", "backup file 2"])
    }

    /// Twenty callers on one connection never overlap; calls on another
    /// connection are not held up.
    @Test func oneCallAtATimePerConnection() async throws {
        let lock = ConnectionLock()
        let log = Log()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for n in 0..<20 {
                group.addTask {
                    try await lock.run("nas", priority: n.isMultiple(of: 3) ? .backup : .normal) {
                        await log.enter()
                        await Task.yield()
                        await log.leave()
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(await log.maxInside == 1)
        #expect(await lock.isHeld("nas") == false)

        await lock.acquire("nas", priority: .normal)
        await lock.acquire("other-nas", priority: .normal)
        #expect(await lock.isHeld("other-nas"))
        await lock.release("other-nas")
        await lock.release("nas")
    }

    /// A call cancelled while it waits takes its turn without touching the
    /// server, and the connection is free afterwards.
    @Test func cancelledWaiterSkipsWork() async {
        let lock = ConnectionLock()
        let log = Log()
        await lock.acquire("nas", priority: .normal)
        let waiter = Task { try await lock.run("nas", priority: .normal) { await log.add("worked") } }
        await Self.waitUntil(lock, "nas", waiting: 1)
        waiter.cancel()
        await lock.release("nas")
        let result = await waiter.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await log.entries.isEmpty)
        #expect(await lock.isHeld("nas") == false)
    }
}
