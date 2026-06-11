import Darwin
import Foundation

/// Errors raised while spawning or driving the worker process.
enum SageKernelError: Error, CustomStringConvertible {
    case spawnFailed(String)
    case requestFailed(String)

    var description: String {
        switch self {
        case .spawnFailed(let detail): "Couldn't start Sage: \(detail)"
        case .requestFailed(let detail): "Couldn't talk to Sage: \(detail)"
        }
    }
}

/// The V1.3 `SageKernel`: spawns and drives `sage -python worker.py`,
/// unifying v0/09's proven `WorkerProcess` + `LineReader` into one type (the
/// framing/queue half lives in `WireQueue`). Every PROBLEMS.md process lesson
/// is applied:
///
///   * **New session / process group.** The child is spawned with
///     `POSIX_SPAWN_SETSID` (`Foundation.Process` exposes no such knob), so
///     `sage`'s bash wrapper AND the real Python worker it fork-execs share
///     one process group we can kill atomically.
///   * **Hard-kill the GROUP.** `killpg(pgid, SIGKILL)` takes down wrapper and
///     worker together. Killing only the spawned pid orphans the worker — the
///     V0.1 trap.
///   * **SIGINT the REAL worker pid** (from the ready banner), and never
///     reinstall a SIGINT handler in the worker — cysignals stays in charge.
///   * **Dedicated reader thread** drains stdout into `WireQueue`; the
///     `SessionController` actor is the sole consumer. Each `SageKernel` owns
///     its own queue, so a killed generation's reader can never disturb a
///     fresh worker (the restart-race lesson).
///   * **Worker stderr → a log file** (Sage boot noise, crashes) instead of
///     /dev/null, so failures are diagnosable. Protocol JSON is unaffected —
///     the worker writes it to a private dup'd fd.
final class SageKernel: KernelTransport, @unchecked Sendable {
    private let sagePath: String
    private let workerPath: String
    /// Where the child's stderr goes (append). nil → /dev/null.
    private let stderrLogURL: URL?

    private let wire = WireQueue()
    private let pidLock = NSLock()
    // Guarded by `pidLock`:
    private var wrapperPID: pid_t = -1
    private var realPID: pid_t?
    private var stdinFD: Int32 = -1

    init(sagePath: String, workerPath: String, stderrLogURL: URL?) {
        self.sagePath = sagePath
        self.workerPath = workerPath
        self.stderrLogURL = stderrLogURL
    }

    // MARK: - KernelTransport

    func setEOFHandler(_ handler: @escaping @Sendable () -> Void) {
        wire.setEOFHandler(handler)
    }

    var isAtEOF: Bool { wire.isAtEOF }

    func spawn() throws {
        var stdinPipe: [Int32] = [-1, -1]
        var stdoutPipe: [Int32] = [-1, -1]
        guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0 else {
            throw SageKernelError.spawnFailed("pipe() failed: \(String(cString: strerror(errno)))")
        }
        let stdinRead = stdinPipe[0]
        let stdinWrite = stdinPipe[1]
        let stdoutRead = stdoutPipe[0]
        let stdoutWrite = stdoutPipe[1]

        var fileActions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&fileActions)
        // Child: stdin <- pipe read end, stdout -> pipe write end,
        // stderr -> the worker log (or /dev/null).
        posix_spawn_file_actions_adddup2(&fileActions, stdinRead, 0)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutWrite, 1)
        if let stderrLogURL {
            posix_spawn_file_actions_addopen(
                &fileActions, 2, stderrLogURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        } else {
            posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)
        }
        // Close the parent ends in the child.
        posix_spawn_file_actions_addclose(&fileActions, stdinWrite)
        posix_spawn_file_actions_addclose(&fileActions, stdoutRead)

        // POSIX_SPAWN_SETSID: the child leads a new session/process group —
        // what lets us killpg() the wrapper + real worker as one unit.
        //
        // POSIX_SPAWN_SETSIGDEF + SETSIGMASK: reset every signal to its
        // default disposition and unblock everything in the child. A
        // posix_spawn child otherwise INHERITS the parent's ignored signals
        // and signal mask — and an app/test-runner parent that ignores
        // SIGINT silently breaks the whole interrupt story (the worker's
        // Python starts with SIGINT ignored, cysignals never fires, and
        // every interrupt escalates to a hard kill). Found the hard way
        // under the swift-testing runner; v0/09's CLI parent had default
        // dispositions, which is why it never saw this.
        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attributes)
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigmask(&attributes, &emptyMask)
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))

        defer {
            posix_spawn_file_actions_destroy(&fileActions)
            posix_spawnattr_destroy(&attributes)
            close(stdinRead)
            close(stdoutWrite)
        }

        let argv = [sagePath, "-python", workerPath]
        var spawnedPID: pid_t = 0
        let status = withCStringArray(argv) { cArgv in
            posix_spawn(&spawnedPID, sagePath, &fileActions, &attributes, cArgv, environ)
        }
        guard status == 0 else {
            close(stdinWrite)
            close(stdoutRead)
            throw SageKernelError.spawnFailed(
                "posix_spawn failed for \(sagePath): \(String(cString: strerror(status)))")
        }

        pidLock.lock()
        wrapperPID = spawnedPID
        stdinFD = stdinWrite
        pidLock.unlock()

        // Quit-time safety net: if the app terminates, the reaper group-kills
        // any kernel still registered so no Sage worker outlives Casette.
        KernelReaper.shared.register(self)

        // Reader thread: drains the worker's stdout into the wire queue until
        // EOF. Owned by this kernel instance (generation) alone.
        let readEnd = stdoutRead
        let queue = wire
        let thread = Thread {
            var buffer = [UInt8](repeating: 0, count: 1 << 16)
            while true {
                let count = read(readEnd, &buffer, buffer.count)
                if count <= 0 { break }  // 0 == EOF, <0 == error
                queue.ingest(buffer[0..<count])
            }
            close(readEnd)
            queue.markEOF()
        }
        thread.name = "SageKernel.reader"
        thread.stackSize = 1 << 20
        thread.start()
    }

    func noteRealPID(_ pid: Int32) {
        pidLock.lock()
        defer { pidLock.unlock() }
        realPID = pid
    }

    func send(_ object: [String: Any]) throws {
        pidLock.lock()
        let fd = stdinFD
        pidLock.unlock()
        guard fd >= 0 else {
            throw SageKernelError.requestFailed("stdin is closed")
        }
        var line = try JSONSerialization.data(withJSONObject: object)
        line.append(0x0A)  // newline frames the JSONL request
        try line.withUnsafeBytes { raw in
            var offset = 0
            let base = raw.bindMemory(to: UInt8.self).baseAddress!
            while offset < raw.count {
                let written = write(fd, base + offset, raw.count - offset)
                if written < 0 {
                    throw SageKernelError.requestFailed(
                        "write() failed: \(String(cString: strerror(errno)))")
                }
                offset += written
            }
        }
    }

    func dequeue(where predicate: ([String: Any]) -> Bool) -> [String: Any]? {
        wire.dequeue(where: predicate)
    }

    /// SIGINT to the REAL worker pid (cysignals → KeyboardInterrupt).
    func interrupt() {
        pidLock.lock()
        let pid = realPID
        pidLock.unlock()
        guard let pid else { return }
        kill(pid, SIGINT)
    }

    /// Hard-kills the whole process group (wrapper + worker), reaps the
    /// zombie, closes stdin, and unregisters from the reaper.
    func hardKill() {
        pidLock.lock()
        let pid = wrapperPID
        let fd = stdinFD
        wrapperPID = -1
        stdinFD = -1
        pidLock.unlock()

        if fd >= 0 { close(fd) }
        if pid > 0 {
            let groupID = getpgid(pid)
            if groupID > 0 {
                killpg(groupID, SIGKILL)
            } else {
                kill(pid, SIGKILL)
            }
            reap(pid)
        }
        KernelReaper.shared.unregister(self)
    }

    func isAlive() -> Bool {
        pidLock.lock()
        let pid = wrapperPID
        pidLock.unlock()
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    // MARK: - Private

    private func reap(_ pid: pid_t) {
        var status: Int32 = 0
        // Non-blocking, with a brief bounded wait so the zombie is collected.
        for _ in 0..<50 {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || result < 0 { break }
            usleep(20_000)
        }
    }
}

/// Calls `body` with a NULL-terminated C string array for `posix_spawn`.
private func withCStringArray<R>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> R
) -> R {
    var cStrings: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
    cStrings.append(nil)
    defer { cStrings.forEach { free($0) } }
    return cStrings.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
}
