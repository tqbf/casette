import Darwin
import Foundation

/// Errors raised while spawning or driving the worker.
public enum WorkerError: Error, CustomStringConvertible {
  case spawnFailed(String)
  case readyTimedOut(seconds: Double)
  case workerDied(detail: String)
  case requestFailed(String)
  case responseTimedOut(seconds: Double)

  public var description: String {
    switch self {
    case .spawnFailed(let detail): "could not spawn worker: \(detail)"
    case .readyTimedOut(let seconds):
      "worker never sent its ready banner within \(seconds)s"
    case .workerDied(let detail): "worker died: \(detail)"
    case .requestFailed(let detail): "could not send request: \(detail)"
    case .responseTimedOut(let seconds):
      "worker did not respond within \(seconds)s"
    }
  }
}

/// Spawns and drives `sage -python worker.py` from Swift, applying the
/// PROBLEMS.md process-control lessons:
///
///   * **New session / process group.** The child is spawned with
///     `POSIX_SPAWN_SETSID` (the Swift equivalent of Python's
///     `start_new_session=True`), so `sage`'s bash wrapper AND the real Python
///     worker it fork-execs share one process group we can kill atomically.
///   * **Hard-kill the GROUP.** `killpg(pgid, SIGKILL)` takes down the wrapper
///     and the worker together. Killing only the spawned pid (the wrapper)
///     would orphan the worker — the exact V0.1 orphan trap.
///   * **SIGINT the REAL worker pid.** The interrupt target is the pid in the
///     ready banner (the Python worker), NOT the wrapper. cysignals turns it
///     into a prompt `KeyboardInterrupt`. We never reinstall a SIGINT handler in
///     the worker, so cysignals stays in charge.
///   * **Dedicated reader.** A background thread drains stdout into a queue, so
///     the caller never blocks on a busy worker — it can interrupt or kill an
///     in-flight eval. (Mirrors controller.py's reader thread.)
///
/// This is a deliberate prototype of V1.3's `SageKernel`.
public final class WorkerProcess: @unchecked Sendable {
  /// The spawned (wrapper) pid — the process-group leader.
  public private(set) var wrapperPID: pid_t = -1
  /// The worker's real pid, from the ready banner (the SIGINT target).
  public private(set) var realPID: pid_t?

  private let sagePath: String
  private let workerPath: String

  private var stdinFD: Int32 = -1
  private let reader = LineReader()
  private var readerThread: Thread?

  public init(sagePath: String, workerPath: String) {
    self.sagePath = sagePath
    self.workerPath = workerPath
  }

  // MARK: - Lifecycle

  /// Spawns the worker and blocks until the ready banner (or fails). Returns the
  /// parsed banner.
  @discardableResult
  public func start(readyTimeout: Double = 120) throws -> [String: Any] {
    var stdinPipe: [Int32] = [-1, -1]
    var stdoutPipe: [Int32] = [-1, -1]
    guard pipe(&stdinPipe) == 0, pipe(&stdoutPipe) == 0 else {
      throw WorkerError.spawnFailed("pipe() failed: \(String(cString: strerror(errno)))")
    }
    let stdinRead = stdinPipe[0]
    let stdinWrite = stdinPipe[1]
    let stdoutRead = stdoutPipe[0]
    let stdoutWrite = stdoutPipe[1]

    var fileActions = posix_spawn_file_actions_t(nil as OpaquePointer?)
    posix_spawn_file_actions_init(&fileActions)
    // Child: stdin <- pipe read end, stdout -> pipe write end, stderr -> /dev/null
    // (the worker logs to a private dup'd fd; we ignore its stderr).
    posix_spawn_file_actions_adddup2(&fileActions, stdinRead, 0)
    posix_spawn_file_actions_adddup2(&fileActions, stdoutWrite, 1)
    posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)
    // Close the parent ends in the child.
    posix_spawn_file_actions_addclose(&fileActions, stdinWrite)
    posix_spawn_file_actions_addclose(&fileActions, stdoutRead)

    // POSIX_SPAWN_SETSID: the child leads a new session/process group — the
    // Swift equivalent of Python's start_new_session=True. This is what lets us
    // killpg() the wrapper + real worker as one unit (PROBLEMS.md).
    var attributes = posix_spawnattr_t(nil as OpaquePointer?)
    posix_spawnattr_init(&attributes)
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

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
      throw WorkerError.spawnFailed(
        "posix_spawn failed for \(sagePath): \(String(cString: strerror(status)))")
    }

    wrapperPID = spawnedPID
    stdinFD = stdinWrite

    // Start the reader thread draining the worker's stdout into the queue.
    let readEnd = stdoutRead
    let thread = Thread { [reader] in
      reader.drain(fileDescriptor: readEnd)
    }
    thread.stackSize = 1 << 20
    thread.start()
    readerThread = thread

    guard let banner = reader.waitForObject(timeout: readyTimeout, where: {
      ($0["op"] as? String) == "ready"
    }) else {
      // Boot failed or hung — clean up so we never leak the wrapper/worker.
      hardKill()
      if reader.isAtEOF {
        throw WorkerError.workerDied(detail: "exited before sending ready banner")
      }
      throw WorkerError.readyTimedOut(seconds: readyTimeout)
    }
    realPID = (banner["pid"] as? Int).map { pid_t($0) }
    return banner
  }

  /// Sends a request object and waits for the response with matching `id`.
  /// Drains/ignores unrelated lines. Throws on timeout or worker death.
  public func request(
    _ object: [String: Any],
    timeout: Double = 30
  ) throws -> [String: Any] {
    try send(object)
    let requestID = object["id"] as? String
    guard let response = reader.waitForObject(timeout: timeout, where: { line in
      requestID == nil || (line["id"] as? String) == requestID
    }) else {
      if reader.isAtEOF {
        throw WorkerError.workerDied(detail: "EOF while awaiting response")
      }
      throw WorkerError.responseTimedOut(seconds: timeout)
    }
    return response
  }

  /// Sends a request WITHOUT waiting (used to start a long eval we then
  /// interrupt). The caller awaits the response via `awaitResponse`.
  public func sendAsync(_ object: [String: Any]) throws {
    try send(object)
  }

  /// Awaits a response for `requestID`, returning `nil` on timeout (so the
  /// caller can escalate to a kill). Throws only on worker death.
  public func awaitResponse(
    id requestID: String,
    timeout: Double
  ) throws -> [String: Any]? {
    let response = reader.waitForObject(timeout: timeout, where: {
      ($0["id"] as? String) == requestID
    })
    if response == nil, reader.isAtEOF {
      throw WorkerError.workerDied(detail: "EOF while awaiting response")
    }
    return response
  }

  /// Sends SIGINT to the REAL worker pid (cysignals -> KeyboardInterrupt).
  public func interrupt() {
    guard let realPID else { return }
    kill(realPID, SIGINT)
  }

  /// Hard-kills the whole process group (wrapper + worker), then reaps. This is
  /// the orphan-proof teardown: `killpg` takes down the bash wrapper and the
  /// Python worker it spawned together.
  public func hardKill() {
    guard wrapperPID > 0 else { return }
    let groupID = getpgid(wrapperPID)
    if groupID > 0 {
      killpg(groupID, SIGKILL)
    } else {
      kill(wrapperPID, SIGKILL)
    }
    reap()
  }

  /// Clean shutdown: ask the worker to exit, give it a moment, then ensure it's
  /// gone. Closes stdin so the reader sees EOF.
  public func shutdown() {
    if wrapperPID > 0, !reader.isAtEOF {
      _ = try? request(["op": "shutdown"], timeout: 5)
    }
    if stdinFD >= 0 {
      close(stdinFD)
      stdinFD = -1
    }
    // Make sure nothing is left, even if the clean path didn't fully take.
    if wrapperPID > 0, isAlive() {
      hardKill()
    } else {
      reap()
    }
  }

  /// True iff the wrapper process is still alive (best-effort).
  public func isAlive() -> Bool {
    guard wrapperPID > 0 else { return false }
    return kill(wrapperPID, 0) == 0
  }

  // MARK: - Private

  private func send(_ object: [String: Any]) throws {
    guard stdinFD >= 0 else {
      throw WorkerError.requestFailed("stdin is closed")
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    var line = data
    line.append(0x0A)  // newline frames the JSONL request
    try line.withUnsafeBytes { raw in
      var offset = 0
      let base = raw.bindMemory(to: UInt8.self).baseAddress!
      while offset < raw.count {
        let written = write(stdinFD, base + offset, raw.count - offset)
        if written < 0 {
          throw WorkerError.requestFailed(
            "write() failed: \(String(cString: strerror(errno)))")
        }
        offset += written
      }
    }
  }

  private func reap() {
    guard wrapperPID > 0 else { return }
    var status: Int32 = 0
    // Non-blocking, with a brief bounded wait so the zombie is collected.
    for _ in 0..<50 {
      let result = waitpid(wrapperPID, &status, WNOHANG)
      if result == wrapperPID || result < 0 { break }
      usleep(20_000)
    }
    wrapperPID = -1
  }
}

// MARK: - Helpers

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
