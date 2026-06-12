import Foundation
@testable import Casette

/// A scripted `KernelTransport` for driving the `SessionController` state
/// machine without Sage: tests script the banner, per-request responses, the
/// interrupt reaction, and EOF, and assert on the signals the controller
/// sent (interrupt/hard-kill counts).
final class FakeKernelTransport: KernelTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let wire = WireQueue()

    // Scripted behavior (set before the controller uses the fake).
    /// Enqueued on spawn; nil simulates a worker that never sends its banner.
    var bannerOnSpawn: [String: Any]? = ["op": "ready", "ok": true, "pid": 4242]
    /// Simulates a worker that exits immediately at boot.
    var eofOnSpawn = false
    /// Maps each sent request to the wire objects to enqueue in response.
    var respondToSend: (@Sendable ([String: Any]) -> [[String: Any]])?
    /// Runs when the controller sends SIGINT (e.g. enqueue an interrupted
    /// envelope to simulate cysignals honoring it). nil = SIGINT swallowed.
    var respondToInterrupt: (@Sendable (FakeKernelTransport) -> Void)?

    // Recorded signals.
    private var _sentIDs: [String] = []
    private var _sentObjects: [[String: Any]] = []
    private var _interruptCount = 0
    private var _hardKillCount = 0
    private var _realPID: Int32?

    var sentIDs: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _sentIDs
    }

    var lastSentID: String? { sentIDs.last }

    /// Every request object as sent, in order — for asserting the exact
    /// wire shape (the V1.8 `numeric`/`precision_digits`/`config` fields).
    var sentObjects: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return _sentObjects
    }

    var interruptCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _interruptCount
    }

    var hardKillCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _hardKillCount
    }

    var realPID: Int32? {
        lock.lock()
        defer { lock.unlock() }
        return _realPID
    }

    // MARK: - Test controls

    /// Enqueues a wire object directly (e.g. a late response).
    func enqueue(_ object: [String: Any]) {
        wire.enqueue(object)
    }

    /// Simulates the worker dying (pipe EOF).
    func triggerEOF() {
        wire.markEOF()
    }

    // MARK: - KernelTransport

    func setEOFHandler(_ handler: @escaping @Sendable () -> Void) {
        wire.setEOFHandler(handler)
    }

    var isAtEOF: Bool { wire.isAtEOF }

    func spawn() throws {
        if let bannerOnSpawn {
            wire.enqueue(bannerOnSpawn)
        }
        if eofOnSpawn {
            wire.markEOF()
        }
    }

    func noteRealPID(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        _realPID = pid
    }

    func send(_ object: [String: Any]) throws {
        lock.lock()
        if let id = object["id"] as? String {
            _sentIDs.append(id)
        }
        _sentObjects.append(object)
        lock.unlock()
        if let respondToSend {
            for response in respondToSend(object) {
                wire.enqueue(response)
            }
        }
    }

    func dequeue(where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        wire.dequeue(where: predicate)
    }

    func interrupt() {
        lock.lock()
        _interruptCount += 1
        lock.unlock()
        respondToInterrupt?(self)
    }

    func hardKill() {
        lock.lock()
        _hardKillCount += 1
        lock.unlock()
        wire.markEOF()
    }

    func isAlive() -> Bool { !wire.isAtEOF }
}

// MARK: - Wire fixtures (the frozen WORKER-PROTOCOL.md shapes)

enum WireFixtures {
    static func okEnvelope(
        id: String,
        plain: String,
        kind: String = "integer",
        approx: String? = nil
    ) -> [String: Any] {
        var envelope: [String: Any] = [
            "id": id, "ok": true, "value": true, "kind": kind,
            "plain": plain, "latex": plain, "repr": plain,
            "actions": [], "artifacts": [], "truncated": false,
            "stdout": "", "stderr": "",
        ]
        if let approx { envelope["approx"] = approx }
        return envelope
    }

    static func errorEnvelope(id: String, type: String, message: String) -> [String: Any] {
        [
            "id": id, "ok": false, "kind": "error",
            "plain": message, "repr": message,
            "actions": ["copy_traceback"], "artifacts": [],
            "error": ["type": type, "message": message, "traceback": "Traceback..."],
            "stdout": "", "stderr": "",
        ]
    }

    static func interruptedEnvelope(id: String) -> [String: Any] {
        [
            "id": id, "ok": false, "kind": "interrupted",
            "plain": "", "repr": "", "actions": [], "artifacts": [],
            "error": ["type": "KeyboardInterrupt", "message": "eval interrupted", "traceback": ""],
            "stdout": "", "stderr": "",
        ]
    }

    static func configResponse(id: String, precisionDigits: Int, ok: Bool = true) -> [String: Any] {
        ["id": id, "ok": ok, "op": "config", "precision_digits": precisionDigits]
    }

    /// A force-numeric value envelope (V0.8): decimal primary, `≈` on the
    /// primary, the exact form preserved in `exact_value`, secondary null.
    static func numericEnvelope(
        id: String,
        decimal: String,
        exactValue: String,
        kind: String = "rational"
    ) -> [String: Any] {
        [
            "id": id, "ok": true, "value": true, "kind": kind,
            "plain": decimal, "latex": exactValue, "repr": decimal,
            "approx": NSNull(), "approx_digits": NSNull(),
            "exact": true, "primary_is_approx": true, "exact_value": exactValue,
            "actions": [], "artifacts": [], "truncated": false,
            "stdout": "", "stderr": "",
        ]
    }

    static func symbolsResponse(
        id: String,
        entries: [(name: String, kind: String, summary: String)]
    ) -> [String: Any] {
        [
            "id": id, "ok": true, "op": "symbols",
            "symbols": entries.map { ["name": $0.name, "kind": $0.kind, "summary": $0.summary] },
        ]
    }
}

// MARK: - Async polling helper

/// Polls `condition` until it holds or `timeout` elapses. Returns the final
/// outcome (so `#expect(await eventually { ... })` reads naturally).
func eventually(
    timeout: Duration = .seconds(5),
    _ condition: @escaping () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}
