import Foundation

/// The worker's stderr log: Sage boot noise, crash output, and anything the
/// worker writes to fd 2 lands here (the protocol JSON is unaffected — the
/// worker writes it to a private dup'd fd). One append-only file under the
/// app's config directory, with a session header per spawn, so "why did Sage
/// die?" has an inspectable answer:
///
///     ~/Library/Application Support/Casette/logs/sage-worker.log
///
/// (`CASETTE_CONFIG_DIR` relocates it, same as `SageConfigStore`.)
enum KernelLog {
    /// Creates the log directory if needed, appends a session header, and
    /// returns the log URL. Returns nil (worker stderr → /dev/null) if the
    /// log can't be prepared — logging must never block the kernel.
    static func prepareWorkerLog(
        configDirectory: URL = SageConfigStore().directory,
        now: Date = .now
    ) -> URL? {
        let directory = configDirectory.appending(path: "logs")
        let url = directory.appending(path: "sage-worker.log")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let header = Data("\n=== Casette worker session \(now.formatted(.iso8601)) ===\n".utf8)
            if let handle = FileHandle(forWritingAtPath: url.path) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: header)
            } else {
                try header.write(to: url)
            }
            return url
        } catch {
            return nil
        }
    }
}
