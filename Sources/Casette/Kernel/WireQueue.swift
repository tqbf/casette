import Foundation

/// Thread-safe queue of parsed JSONL wire objects — the framing half of
/// v0/09's `LineReader`, extracted so both `SageKernel` (fed raw bytes by its
/// reader thread) and the test fake (fed objects directly) share one proven
/// implementation, and so framing/dequeue semantics are unit-testable without
/// a process.
///
/// Producer/consumer contract (PROBLEMS.md): exactly one producer (the reader
/// thread) and one consumer (the `SessionController` actor). `dequeue` is
/// non-blocking; waiting is the consumer's job.
final class WireQueue: @unchecked Sendable {
    private let lock = NSLock()
    // Guarded by `lock`:
    private var objects: [[String: Any]] = []
    private var pending = Data()
    private var eof = false
    private var eofHandlerFired = false
    private var eofHandler: (@Sendable () -> Void)?

    /// True once `markEOF()` has been called (the pipe closed).
    var isAtEOF: Bool {
        lock.lock()
        defer { lock.unlock() }
        return eof
    }

    /// Registers the EOF callback. If EOF already happened, fires immediately
    /// (exactly once overall), so a fast-failing boot is never missed.
    func setEOFHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        eofHandler = handler
        let fireNow = eof && !eofHandlerFired
        if fireNow { eofHandlerFired = true }
        lock.unlock()
        if fireNow { handler() }
    }

    /// Ingests a raw chunk from the worker's stdout, buffering partial lines
    /// and enqueueing each complete JSON object. Non-JSON lines are skipped
    /// (shouldn't happen — the worker owns a private protocol fd).
    func ingest(_ data: some Sequence<UInt8>) {
        lock.lock()
        defer { lock.unlock() }
        pending.append(contentsOf: data)
        while let newlineIndex = pending.firstIndex(of: 0x0A) {
            let lineData = pending.subdata(in: pending.startIndex..<newlineIndex)
            pending.removeSubrange(pending.startIndex...newlineIndex)
            guard !lineData.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: lineData),
                  let dictionary = object as? [String: Any]
            else { continue }
            objects.append(dictionary)
        }
    }

    /// Enqueues an already-parsed object (test fakes).
    func enqueue(_ object: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        objects.append(object)
    }

    /// Marks the stream closed and fires the EOF handler exactly once.
    func markEOF() {
        lock.lock()
        eof = true
        let handler = eofHandlerFired ? nil : eofHandler
        if handler != nil { eofHandlerFired = true }
        lock.unlock()
        handler?()
    }

    /// Removes and returns the first object matching `predicate`, discarding
    /// non-matching objects ahead of it (the v0/09 `waitForObject` semantics,
    /// non-blocking). Safe because the controller serializes requests: only
    /// one response can ever be pending.
    func dequeue(where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        while !objects.isEmpty {
            let object = objects.removeFirst()
            if predicate(object) { return object }
            // Non-matching: drop it and keep looking (stray protocol line).
        }
        return nil
    }
}
