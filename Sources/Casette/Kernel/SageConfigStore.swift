// LIFTED VERBATIM from v0/09-sage-doctor/Sources/SageDoctor/SageConfigStore.swift
// (the V0.9 config store: JSON at ~/Library/Application Support/Casette/,
// CASETTE_CONFIG_DIR override for hermetic tests). DO NOT refactor v0/09 — it
// is frozen evidence. V1.10 (in-app Sage Doctor) reuses this exact store.

import Foundation

/// The persisted Sage-Doctor configuration. Currently just the selected Sage
/// binary path; a struct so V1.10 can add fields (e.g. last-known version,
/// last-verified date) without breaking the file format.
public struct SageConfig: Codable, Sendable, Equatable {
  /// The Sage binary the user selected / the doctor stored.
  public var sagePath: String?

  public init(sagePath: String? = nil) {
    self.sagePath = sagePath
  }
}

/// Reads and writes the doctor's configuration.
///
/// **Storage decision (documented in plans/SAGE-DOCTOR.md):** a JSON file at
/// `~/Library/Application Support/Casette/sage-doctor.json`. Application Support
/// — not `UserDefaults` — because the selected Sage path is app-managed state
/// that benefits from being an inspectable, portable, hand-editable file (a
/// power user can point Casette at a custom Sage by editing one line; support
/// can ask "what's in your sage-doctor.json?"). It is the natural macOS home for
/// non-document app data per Apple's File System Programming Guide. V1.10 reuses
/// this exact store; the env override below keeps the V0.9 proof hermetic.
///
/// The location is overridable via the `CASETTE_CONFIG_DIR` environment
/// variable so tests (and the broken-config proofs) never touch the real
/// user-level file.
public struct SageConfigStore: Sendable {
  /// The environment variable that relocates the config directory for tests.
  public static let directoryOverrideKey = "CASETTE_CONFIG_DIR"
  public static let fileName = "sage-doctor.json"

  public let directory: URL
  public let fileURL: URL

  /// Builds a store, honoring `CASETTE_CONFIG_DIR` if set, else the real
  /// Application Support location.
  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    if let override = environment[Self.directoryOverrideKey], !override.isEmpty {
      directory = URL(fileURLWithPath: override, isDirectory: true)
    } else {
      let base = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSHomeDirectory())
          .appendingPathComponent("Library/Application Support")
      directory = base.appendingPathComponent("Casette", isDirectory: true)
    }
    fileURL = directory.appendingPathComponent(Self.fileName)
  }

  /// Loads the config, or an empty config if the file is absent. A corrupt file
  /// is treated as empty (the doctor re-discovers) rather than fatal.
  public func load() -> SageConfig {
    guard let data = try? Data(contentsOf: fileURL) else { return SageConfig() }
    return (try? JSONDecoder().decode(SageConfig.self, from: data)) ?? SageConfig()
  }

  /// The stored path, if any.
  public func storedPath() -> String? {
    load().sagePath
  }

  /// Stores `path` as the selected Sage binary, creating the directory if needed.
  public func store(sagePath: String) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true)
    var config = load()
    config.sagePath = sagePath
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: fileURL, options: .atomic)
  }

  /// Clears the stored path (`--forget`). Removing the file entirely is the
  /// cleanest reset; absent file == empty config.
  public func forget() throws {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: fileURL.path) {
      try fileManager.removeItem(at: fileURL)
    }
  }
}
