import Foundation

/// Where a Sage candidate came from — used to explain the selection to the user
/// and to record provenance in the JSON report.
public enum SageCandidateSource: String, Codable, Sendable {
  /// An explicit `--sage PATH` override (highest priority).
  case override
  /// A path previously stored via `--use PATH` (the app's configured path).
  case stored
  /// A well-known absolute install location.
  case knownPath
  /// Resolved from `PATH` via `which sage`.
  case pathLookup
}

/// One Sage binary the discovery search found (or was told about).
public struct SageCandidate: Codable, Sendable, Equatable {
  public let path: String
  public let source: SageCandidateSource
  /// True iff the file exists and is executable. Non-existent candidates are
  /// still reported (so the user sees what was searched), but never selected.
  public let exists: Bool

  public init(path: String, source: SageCandidateSource, exists: Bool) {
    self.path = path
    self.source = source
    self.exists = exists
  }
}

/// The outcome of a discovery run: every candidate considered (in priority
/// order) and which one — if any — was selected.
public struct DiscoveryResult: Sendable {
  /// All candidates considered, highest priority first. Includes non-existent
  /// ones so the report can show the full searched set.
  public let candidates: [SageCandidate]
  /// The first existing candidate in priority order, or `nil` if none exists.
  public let selected: SageCandidate?

  public init(candidates: [SageCandidate], selected: SageCandidate?) {
    self.candidates = candidates
    self.selected = selected
  }
}

/// Discovers a user-installed Sage without bundling it.
///
/// Priority order (documented in plans/SAGE-DOCTOR.md), highest first:
///   1. explicit `--sage PATH` override         (the user picked a binary)
///   2. the stored/configured path              (`--use PATH` from a prior run)
///   3. well-known absolute install locations   (Homebrew, /usr/local, the
///      macOS SageMath app bundles, common conda prefixes)
///   4. `which sage` via the inherited PATH
///
/// The search is pure with respect to its inputs: filesystem existence and the
/// `which` lookup are injected, so the ordering logic is unit-testable without a
/// real Sage on the machine.
public struct SageDiscovery: Sendable {
  /// Returns true iff `path` is an existing, executable regular file/symlink.
  public typealias ExistenceCheck = @Sendable (String) -> Bool
  /// Resolves `sage` on PATH (e.g. via `which`), or `nil`.
  public typealias PathLookup = @Sendable () -> String?

  /// The well-known absolute locations, highest priority first. Documented and
  /// frozen so a future agent can see exactly what is searched and why.
  public static let knownPaths: [String] = [
    // Homebrew (Apple Silicon, then Intel) — the V1 happy path.
    "/opt/homebrew/bin/sage",
    "/usr/local/bin/sage",
    // The official macOS SageMath app bundles. The real binary lives at
    // Contents/Resources/sage/sage; the app also exposes a top-level `sage`
    // symlink. We search both; the glob is expanded by the caller.
    "/Applications/SageMath.app/Contents/Resources/sage/sage",
    "/Applications/SageMath.app/sage",
    // Common conda/mamba prefixes.
    "\(NSHomeDirectory())/anaconda3/bin/sage",
    "\(NSHomeDirectory())/miniconda3/bin/sage",
    "\(NSHomeDirectory())/miniforge3/bin/sage",
    "/opt/anaconda3/bin/sage",
    "/opt/miniconda3/bin/sage",
  ]

  private let existenceCheck: ExistenceCheck
  private let pathLookup: PathLookup
  private let appBundleGlob: @Sendable () -> [String]

  public init(
    existenceCheck: @escaping ExistenceCheck = SageDiscovery.defaultExistenceCheck,
    pathLookup: @escaping PathLookup = SageDiscovery.defaultPathLookup,
    appBundleGlob: @escaping @Sendable () -> [String] = SageDiscovery.defaultAppBundleGlob
  ) {
    self.existenceCheck = existenceCheck
    self.pathLookup = pathLookup
    self.appBundleGlob = appBundleGlob
  }

  /// Runs the full priority search.
  ///
  /// - Parameters:
  ///   - override: an explicit `--sage PATH`, if the user gave one.
  ///   - storedPath: the previously configured path, if any.
  public func discover(override: String? = nil, storedPath: String? = nil) -> DiscoveryResult {
    var candidates: [SageCandidate] = []
    var seen = Set<String>()

    func append(_ rawPath: String, _ source: SageCandidateSource) {
      let path = (rawPath as NSString).expandingTildeInPath
      guard !seen.contains(path) else { return }
      seen.insert(path)
      candidates.append(
        SageCandidate(path: path, source: source, exists: existenceCheck(path)))
    }

    if let override {
      append(override, .override)
    }
    if let storedPath {
      append(storedPath, .stored)
    }
    // Well-known locations, including any SageMath*.app bundles found by glob.
    for path in Self.knownPaths {
      append(path, .knownPath)
    }
    for path in appBundleGlob() {
      append(path, .knownPath)
    }
    if let onPath = pathLookup() {
      append(onPath, .pathLookup)
    }

    let selected = candidates.first(where: { $0.exists })
    return DiscoveryResult(candidates: candidates, selected: selected)
  }

  // MARK: - Default real-world probes

  public static let defaultExistenceCheck: ExistenceCheck = { path in
    var isDirectory: ObjCBool = false
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
    guard !isDirectory.boolValue else { return false }
    return fileManager.isExecutableFile(atPath: path)
  }

  public static let defaultPathLookup: PathLookup = {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = ["sage"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      return nil
    }
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let path = String(decoding: data, as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return path.isEmpty ? nil : path
  }

  /// Expands `/Applications/SageMath*.app/...` to the concrete `sage` binaries.
  /// The macOS installer names bundles `SageMath-9-5.app`, `SageMath-9.2.app`,
  /// etc., so we glob rather than hard-code a version.
  public static let defaultAppBundleGlob: @Sendable () -> [String] = {
    let applications = "/Applications"
    let fileManager = FileManager.default
    guard
      let entries = try? fileManager.contentsOfDirectory(atPath: applications)
    else { return [] }
    var results: [String] = []
    for entry in entries.sorted() where entry.hasPrefix("SageMath") && entry.hasSuffix(".app") {
      let bundle = "\(applications)/\(entry)"
      results.append("\(bundle)/Contents/Resources/sage/sage")
      results.append("\(bundle)/sage")
    }
    return results
  }
}
