import Foundation

// MARK: - SessionStore: atomic, incremental, robust persistence
//
// The surviving V1.9 artifact. Owns the on-disk "last session" file:
//   * pretty-printed, human-inspectable JSON (the spec demands "simple and
//     inspectable");
//   * ATOMIC writes (write temp + rename) so a crash mid-write never corrupts
//     the file — crash-safety is the whole point of persistence;
//   * INCREMENTAL save (rewrite after every appended row);
//   * robust LOAD: corrupted JSON → quarantine the bad file + start fresh;
//     unknown schema version → polite refusal; empty/missing → fresh session.

/// The outcome of trying to load the last session.
public enum LoadOutcome: Equatable, Sendable {
  /// A valid session was restored.
  case restored(Session)
  /// No file existed (first launch) — caller starts a fresh session.
  case fresh
  /// The file's schema version is newer/unknown — refuse politely, don't guess.
  /// The bad file is left in place (not quarantined) so a newer app can read it.
  case refusedSchema(found: Int, supported: Int)
  /// The file was unreadable JSON — it was quarantined and a fresh session
  /// should be started. `quarantinePath` is where the bad file was moved.
  case corruptQuarantined(quarantinePath: String, detail: String)
}

public struct SessionStore {
  /// Directory holding the session file. Defaults to the V1 storage location
  /// (`~/Library/Application Support/Casette/sessions/`), overridable via
  /// `CASETTE_CONFIG_DIR` to keep the proof hermetic (consistent with v0/09).
  public let directory: URL

  /// The single "last session" file inside `directory`.
  public var sessionFileURL: URL {
    directory.appendingPathComponent("last-session.json")
  }

  private let fileManager: FileManager

  /// Builds a store. If `directory` is nil, resolves the storage-location policy:
  /// `CASETTE_CONFIG_DIR` if set, else `~/Library/Application Support/Casette/`,
  /// with a `sessions/` subdirectory.
  public init(directory: URL? = nil, fileManager: FileManager = .default) {
    self.fileManager = fileManager
    if let directory {
      self.directory = directory
    } else {
      self.directory = Self.defaultSessionsDirectory(fileManager: fileManager)
    }
  }

  /// Resolves the default sessions directory per the V1 storage policy.
  public static func defaultSessionsDirectory(
    fileManager: FileManager = .default
  ) -> URL {
    let base: URL
    if let override = ProcessInfo.processInfo.environment["CASETTE_CONFIG_DIR"] {
      base = URL(fileURLWithPath: override, isDirectory: true)
    } else {
      let appSupport = fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
      base = appSupport.appendingPathComponent("Casette", isDirectory: true)
    }
    return base.appendingPathComponent("sessions", isDirectory: true)
  }

  // MARK: Codec

  /// The shared encoder: pretty-printed, sorted keys, ISO-8601 dates — so the
  /// file is human-inspectable and stable across writes (no spurious diffs).
  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }

  // MARK: Save (atomic, incremental)

  /// Persists the session atomically. Bumps `updated`, ensures the directory
  /// exists, writes to a temp file, then renames over the target — so a crash
  /// mid-write leaves either the old file or the new one, never a torn file.
  public func save(_ session: Session) throws {
    var session = session
    session.updated = Date()
    try fileManager.createDirectory(
      at: directory, withIntermediateDirectories: true)

    let data = try Self.makeEncoder().encode(session)
    let tempURL = directory.appendingPathComponent(
      "last-session.\(UUID().uuidString).tmp")
    try data.write(to: tempURL, options: .atomic)
    // Rename over the target (atomic on the same filesystem). Replace if present.
    if fileManager.fileExists(atPath: sessionFileURL.path) {
      _ = try fileManager.replaceItemAt(sessionFileURL, withItemAt: tempURL)
    } else {
      try fileManager.moveItem(at: tempURL, to: sessionFileURL)
    }
  }

  // MARK: Load (robust)

  /// Loads the last session, handling every failure mode the spec lists:
  /// missing/empty → fresh; corrupt JSON → quarantine + fresh; unknown schema →
  /// polite refusal. On a clean restore, artifact liveness is re-resolved (the
  /// /tmp dir may be gone), so the returned session reflects reality on disk.
  public func load() -> LoadOutcome {
    let path = sessionFileURL.path
    guard fileManager.fileExists(atPath: path) else {
      return .fresh
    }
    guard let data = fileManager.contents(atPath: path), !data.isEmpty else {
      // Empty file is treated as "no session yet" (don't quarantine an empty).
      return .fresh
    }

    // Peek the schema version BEFORE a full decode, so an unknown future shape
    // (which would fail strict decoding) is refused politely, not quarantined.
    if let version = peekSchemaVersion(data), version != currentSchemaVersion {
      return .refusedSchema(found: version, supported: currentSchemaVersion)
    }

    do {
      var session = try Self.makeDecoder().decode(Session.self, from: data)
      // Belt-and-suspenders: a decode can succeed while version is wrong only if
      // peek failed; re-check.
      guard session.schemaVersion == currentSchemaVersion else {
        return .refusedSchema(
          found: session.schemaVersion, supported: currentSchemaVersion)
      }
      session = withResolvedArtifactLiveness(session)
      return .restored(session)
    } catch {
      let quarantine = quarantineBadFile()
      return .corruptQuarantined(
        quarantinePath: quarantine ?? "(quarantine failed)",
        detail: "\(error)")
    }
  }

  /// Re-resolves every artifact's liveness against the current filesystem. On a
  /// real restart the worker's /tmp session dir is gone, so plots flip to
  /// `.missing` here — the EXPECTED case the row still renders through.
  public func withResolvedArtifactLiveness(_ session: Session) -> Session {
    var session = session
    session.rows = session.rows.map { row in
      var row = row
      if var result = row.result {
        result.artifacts = result.artifacts.map {
          $0.resolvingLiveness(fileManager: fileManager)
        }
        row.result = result
      }
      return row
    }
    return session
  }

  // MARK: - Private

  /// Reads only the top-level `schemaVersion` without a full strict decode.
  private func peekSchemaVersion(_ data: Data) -> Int? {
    guard
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object["schemaVersion"] as? Int
  }

  /// Moves the unreadable file aside with a timestamped name and returns the new
  /// path, so the bad file is kept (for forensics) but out of the way.
  private func quarantineBadFile() -> String? {
    let stamp = ISO8601DateFormatter().string(from: Date())
      .replacingOccurrences(of: ":", with: "-")
    let target = directory.appendingPathComponent("last-session.corrupt-\(stamp).json")
    do {
      if fileManager.fileExists(atPath: target.path) {
        try fileManager.removeItem(at: target)
      }
      try fileManager.moveItem(at: sessionFileURL, to: target)
      return target.path
    } catch {
      return nil
    }
  }
}
