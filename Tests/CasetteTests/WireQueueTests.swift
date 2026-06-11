import Foundation
import Testing
@testable import Casette

@Suite("WireQueue (JSONL framing + single-consumer dequeue)")
struct WireQueueTests {
    @Test("complete lines parse into objects; partial frames buffer across chunks")
    func partialFrames() {
        let queue = WireQueue()
        queue.ingest(Data("{\"id\": \"a\", \"va".utf8))
        #expect(queue.dequeue(where: { _ in true }) == nil)  // incomplete line
        queue.ingest(Data("lue\": 1}\n{\"id\": \"b\"}\n".utf8))

        let first = queue.dequeue(where: { _ in true })
        #expect(first?["id"] as? String == "a")
        #expect(first?["value"] as? Int == 1)
        let second = queue.dequeue(where: { _ in true })
        #expect(second?["id"] as? String == "b")
    }

    @Test("non-JSON and empty lines are skipped without corrupting framing")
    func junkLinesSkipped() {
        let queue = WireQueue()
        queue.ingest(Data("not json at all\n\n{\"id\": \"ok\"}\n".utf8))
        let object = queue.dequeue(where: { _ in true })
        #expect(object?["id"] as? String == "ok")
        #expect(queue.dequeue(where: { _ in true }) == nil)
    }

    @Test("dequeue discards non-matching objects ahead of the match")
    func dequeueDiscardsStrays() {
        let queue = WireQueue()
        queue.enqueue(["id": "stray-1"])
        queue.enqueue(["id": "wanted"])
        queue.enqueue(["id": "later"])

        let match = queue.dequeue(where: { ($0["id"] as? String) == "wanted" })
        #expect(match?["id"] as? String == "wanted")
        // The stray ahead of the match is gone; the one behind survives.
        #expect(queue.dequeue(where: { ($0["id"] as? String) == "stray-1" }) == nil)
        queue.enqueue(["id": "later"])  // re-add: previous probe discarded it
        #expect(queue.dequeue(where: { ($0["id"] as? String) == "later" }) != nil)
    }

    @Test("EOF flag and handler: fires exactly once, even when set after EOF")
    func eofDelivery() {
        let queue = WireQueue()
        let fireCount = Counter()
        queue.setEOFHandler { fireCount.increment() }
        #expect(!queue.isAtEOF)
        queue.markEOF()
        queue.markEOF()  // idempotent
        #expect(queue.isAtEOF)
        #expect(fireCount.value == 1)

        // A handler registered after EOF (the fast-failing-boot case) still
        // fires — but the overall count stays once-per-queue.
        let lateQueue = WireQueue()
        let lateCount = Counter()
        lateQueue.markEOF()
        lateQueue.setEOFHandler { lateCount.increment() }
        #expect(lateCount.value == 1)
    }
}

/// Tiny thread-safe counter for handler-fire assertions.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
