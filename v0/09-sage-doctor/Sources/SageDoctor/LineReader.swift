import Darwin
import Foundation

/// Drains a worker's stdout file descriptor on a background thread, parsing
/// JSONL into a thread-safe queue, and records EOF when the pipe closes.
///
/// This is the Swift analogue of controller.py's reader thread. The load-bearing
/// design: the control thread (the caller of `WorkerProcess.request`) is the
/// SOLE consumer of the queue; this reader is the SOLE producer. Nothing else
/// reads the queue, so an interrupt/kill can never steal a response from the
/// waiter (controller.py's "two threads draining one queue" trap). Each
/// `WorkerProcess` owns exactly one `LineReader`, so a stale reader from a killed
/// generation can never disturb a fresh worker (the restart-race lesson).
final class LineReader: @unchecked Sendable {
  private let lock = NSCondition()
  private var queue: [[String: Any]] = []
  private var eof = false

  /// True once the worker's stdout has closed (the worker died or shut down).
  var isAtEOF: Bool {
    lock.lock()
    defer { lock.unlock() }
    return eof
  }

  /// Reads `fileDescriptor` until EOF, splitting on newlines and enqueueing each
  /// JSON object. Runs on its own thread; returns when the pipe closes.
  func drain(fileDescriptor: Int32) {
    var pending = Data()
    let bufferSize = 1 << 16
    var buffer = [UInt8](repeating: 0, count: bufferSize)

    while true {
      let count = read(fileDescriptor, &buffer, bufferSize)
      if count <= 0 { break }  // 0 == EOF, <0 == error
      pending.append(contentsOf: buffer[0..<count])
      flushCompleteLines(from: &pending)
    }
    close(fileDescriptor)
    lock.lock()
    eof = true
    lock.signal()
    lock.unlock()
  }

  /// Waits up to `timeout` seconds for a queued object satisfying `predicate`,
  /// discarding non-matching objects ahead of it. Returns `nil` on timeout or if
  /// EOF is reached with no match.
  func waitForObject(
    timeout: Double,
    where predicate: ([String: Any]) -> Bool
  ) -> [String: Any]? {
    let deadline = Date().addingTimeInterval(timeout)
    lock.lock()
    defer { lock.unlock() }
    while true {
      while !queue.isEmpty {
        let object = queue.removeFirst()
        if predicate(object) { return object }
        // Non-matching object: drop it and keep looking (stray protocol line).
      }
      if eof { return nil }
      let remaining = deadline.timeIntervalSinceNow
      if remaining <= 0 { return nil }
      _ = lock.wait(until: Date().addingTimeInterval(min(remaining, 0.2)))
    }
  }

  // MARK: - Private

  private func flushCompleteLines(from pending: inout Data) {
    while let newlineIndex = pending.firstIndex(of: 0x0A) {
      let lineData = pending.subdata(in: pending.startIndex..<newlineIndex)
      pending.removeSubrange(pending.startIndex...newlineIndex)
      guard !lineData.isEmpty else { continue }
      guard
        let object = try? JSONSerialization.jsonObject(with: lineData),
        let dictionary = object as? [String: Any]
      else { continue }  // Non-JSON shouldn't happen (private protocol fd); skip.
      lock.lock()
      queue.append(dictionary)
      lock.signal()
      lock.unlock()
    }
  }
}
