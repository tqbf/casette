import Foundation

/// One doctor-run worker lifecycle over a `KernelTransport`: spawn, await the
/// ready banner, request/response with deadlines, interrupt, group hard-kill.
/// The async, transport-seam port of v0/09's blocking `WorkerProcess` driver —
/// the doctor's checks consume the SAME process machinery the calculator's
/// kernel uses (`SageKernel`), so there is exactly one spawn/kill code path in
/// the app.
///
/// Failure modes are one-line actionable messages (never stack traces), and
/// every failure path hard-kills the process group before throwing — the V0.9
/// hang-at-boot lesson ("boot-failure must hard-kill before returning, or a
/// hung wrapper leaks").
final class DoctorWorker: @unchecked Sendable {
    enum Failure: Error, CustomStringConvertible {
        case spawnFailed(String)
        case exitedBeforeReady
        case bootTimeout(Duration)
        case requestFailed(String)
        case workerDied(id: String)
        case responseTimeout(id: String, Duration)
        case cancelled

        var description: String {
            switch self {
            case .spawnFailed(let detail):
                "couldn't start the worker: \(detail)"
            case .exitedBeforeReady:
                "the worker exited before it became ready — not a Sage binary, or "
                    + "Sage is broken. Check the worker log in "
                    + "~/Library/Application Support/Casette/logs/"
            case .bootTimeout(let timeout):
                "the worker didn't become ready within \(timeout) — is this binary "
                    + "really Sage? It was stopped (no processes left behind)"
            case .requestFailed(let detail):
                "couldn't send a request to the worker: \(detail)"
            case .workerDied(let id):
                "the worker died while evaluating `\(id)` — check the worker log in "
                    + "~/Library/Application Support/Casette/logs/"
            case .responseTimeout(let id, let timeout):
                "the worker didn't answer `\(id)` within \(timeout)"
            case .cancelled:
                "stopped by the user"
            }
        }
    }

    private let transport: any KernelTransport
    private let pollInterval: Duration

    init(transport: any KernelTransport, pollInterval: Duration = .milliseconds(25)) {
        self.transport = transport
        self.pollInterval = pollInterval
    }

    /// Spawns the worker and awaits its ready banner. On ANY failure —
    /// spawn error, early exit, hang past `readyTimeout`, cancellation —
    /// the process group is hard-killed before the error is thrown.
    @discardableResult
    func boot(readyTimeout: Duration) async throws -> [String: Any] {
        do {
            try transport.spawn()
        } catch {
            transport.hardKill()
            throw Failure.spawnFailed("\(error)")
        }
        let clock = ContinuousClock()
        let deadline = clock.now + readyTimeout
        while clock.now < deadline {
            if Task.isCancelled {
                transport.hardKill()
                throw Failure.cancelled
            }
            if let banner = transport.dequeue(where: { ($0["op"] as? String) == "ready" }) {
                if let pid = banner["pid"] as? Int {
                    transport.noteRealPID(Int32(pid))
                }
                return banner
            }
            if transport.isAtEOF {
                transport.hardKill()
                throw Failure.exitedBeforeReady
            }
            try? await Task.sleep(for: pollInterval)
        }
        // Hung at boot: kill BEFORE reporting (the V0.9 orphan lesson).
        transport.hardKill()
        throw Failure.bootTimeout(readyTimeout)
    }

    /// Sends an eval request without waiting (the interrupt check's spin).
    func send(id: String, code: String) throws {
        do {
            try transport.send(["id": id, "code": code])
        } catch {
            throw Failure.requestFailed("\(error)")
        }
    }

    /// Sends an eval request and awaits its response within `timeout`.
    func request(id: String, code: String, timeout: Duration) async throws -> [String: Any] {
        try send(id: id, code: code)
        guard let response = try await awaitResponse(id: id, timeout: timeout) else {
            throw Failure.responseTimeout(id: id, timeout)
        }
        return response
    }

    /// Awaits the response for `id`. Returns nil on timeout (the interrupt
    /// check escalates on nil rather than failing); throws on worker death
    /// or cancellation.
    func awaitResponse(id: String, timeout: Duration) async throws -> [String: Any]? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if Task.isCancelled {
                transport.hardKill()
                throw Failure.cancelled
            }
            if let response = transport.dequeue(where: { ($0["id"] as? String) == id }) {
                return response
            }
            if transport.isAtEOF {
                transport.hardKill()
                throw Failure.workerDied(id: id)
            }
            try? await Task.sleep(for: pollInterval)
        }
        return nil
    }

    /// SIGINT to the worker's real banner pid (cysignals → KeyboardInterrupt).
    func interrupt() {
        transport.interrupt()
    }

    /// SIGKILL to the whole process group — wrapper + worker (idempotent).
    func hardKill() {
        transport.hardKill()
    }
}
