import Foundation
import Testing
@testable import SessionStore

// MARK: - Pure-logic tests (no Sage). The worker-dependent replay proof lives in
// the casette-tape CLI harness; these cover the codec, robustness, provenance,
// supersede policy, and artifact-liveness logic.

private func scratchStore() -> SessionStore {
  let dir = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("casette-test-\(UUID().uuidString)", isDirectory: true)
    .appendingPathComponent("sessions")
  return SessionStore(directory: dir)
}

private func sampleSession() -> Session {
  let now = Date(timeIntervalSince1970: 1_700_000_000)
  let env = PersistedEnvelope(
    kind: "rational", plain: "8/15", latex: "\\frac{8}{15}", repr: "8/15",
    approx: "0.5333333333", approxDigits: 10, exact: true,
    primaryIsApprox: false, actions: ["numerator", "denominator", "approx"])
  let row = SessionRow(
    input: "1/3 + 1/5", sage: "1/3 + 1/5", result: env, status: .ok,
    timestamp: now, durationSeconds: 0.01,
    provenance: Provenance(kind: .cached, cachedAt: now))
  return Session(
    created: now, updated: now, sageVersion: "9.5",
    precisionDigits: 10, rows: [row])
}

// MARK: Codec round-trip

@Test func codecRoundTripPreservesEverything() throws {
  let session = sampleSession()
  let data = try SessionStore.makeEncoder().encode(session)
  let decoded = try SessionStore.makeDecoder().decode(Session.self, from: data)
  #expect(decoded == session)
}

@Test func encodedFileIsPrettyPrintedAndInspectable() throws {
  let data = try SessionStore.makeEncoder().encode(sampleSession())
  let text = String(decoding: data, as: UTF8.self)
  // Pretty-printed → newlines + indentation; human-inspectable keys present.
  #expect(text.contains("\n"))
  #expect(text.contains("\"schemaVersion\""))
  #expect(text.contains("\"8/15\""))
  // Slashes are not escaped (\/), so paths/LaTeX stay readable.
  #expect(!text.contains("\\/"))
}

@Test func saveThenLoadRestoresSession() throws {
  let store = scratchStore()
  let session = sampleSession()
  try store.save(session)
  guard case let .restored(restored) = store.load() else {
    Issue.record("expected .restored")
    return
  }
  // `updated` is bumped on save, so compare the load-bearing parts.
  #expect(restored.rows == session.rows)
  #expect(restored.schemaVersion == currentSchemaVersion)
  #expect(restored.precisionDigits == 10)
}

// MARK: Robustness

@Test func missingFileIsFresh() {
  #expect(scratchStore().load() == .fresh)
}

@Test func emptyFileIsFresh() throws {
  let store = scratchStore()
  try FileManager.default.createDirectory(
    at: store.directory, withIntermediateDirectories: true)
  try Data().write(to: store.sessionFileURL)
  #expect(store.load() == .fresh)
}

@Test func corruptJSONIsQuarantinedAndFreshStart() throws {
  let store = scratchStore()
  try FileManager.default.createDirectory(
    at: store.directory, withIntermediateDirectories: true)
  try Data("{ not json ]".utf8).write(to: store.sessionFileURL)
  let outcome = store.load()
  guard case let .corruptQuarantined(quarantinePath, _) = outcome else {
    Issue.record("expected .corruptQuarantined, got \(outcome)")
    return
  }
  #expect(FileManager.default.fileExists(atPath: quarantinePath))
  // Original bad file is moved aside, not left in place.
  #expect(!FileManager.default.fileExists(atPath: store.sessionFileURL.path))
}

@Test func unknownSchemaVersionIsRefusedPolitely() throws {
  let store = scratchStore()
  try FileManager.default.createDirectory(
    at: store.directory, withIntermediateDirectories: true)
  let future = """
    { "schemaVersion": 9999, "created": "2026-06-11T00:00:00Z",
      "updated": "2026-06-11T00:00:00Z", "precisionDigits": 10, "rows": [] }
    """
  try Data(future.utf8).write(to: store.sessionFileURL)
  let outcome = store.load()
  #expect(outcome == .refusedSchema(found: 9999, supported: currentSchemaVersion))
  // A refused (future) file is LEFT intact — a newer app must still read it.
  #expect(FileManager.default.fileExists(atPath: store.sessionFileURL.path))
}

// MARK: Incremental / atomic save

@Test func incrementalSaveRewritesInPlace() throws {
  let store = scratchStore()
  var session = sampleSession()
  try store.save(session)
  // Append a second row and save again — same single file, two rows.
  session.rows.append(SessionRow(
    input: "2+2", sage: "2+2",
    result: PersistedEnvelope(kind: "integer", plain: "4"),
    status: .ok, timestamp: Date()))
  try store.save(session)
  guard case let .restored(restored) = store.load() else {
    Issue.record("expected .restored")
    return
  }
  #expect(restored.rows.count == 2)
  // No stray .tmp files left behind.
  let contents = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
  #expect(!contents.contains { $0.hasSuffix(".tmp") })
}

// MARK: Artifact liveness

@Test func artifactLivenessFlipsToMissingWhenFileGone() throws {
  // A path that does not exist → resolves to .missing.
  let artifact = PersistedArtifact(
    type: "image", format: "png",
    path: "/tmp/casette-no-such-\(UUID().uuidString).png", bytes: 100)
  #expect(artifact.resolvingLiveness().status == .missing)

  // A path that DOES exist → resolves to .present.
  let real = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("casette-live-\(UUID().uuidString).png")
  try Data("png".utf8).write(to: real)
  defer { try? FileManager.default.removeItem(at: real) }
  let present = PersistedArtifact(type: "image", format: "png", path: real.path)
  #expect(present.resolvingLiveness().status == .present)
}

@Test func nilArtifactPathResolvesMissing() {
  let artifact = PersistedArtifact(type: "image", format: "svg", path: nil)
  #expect(artifact.resolvingLiveness().status == .missing)
}

@Test func loadReResolvesArtifactLiveness() throws {
  let store = scratchStore()
  let now = Date()
  // Persist a plot row pointing at a file we then delete.
  let goneURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("casette-gone-\(UUID().uuidString).png")
  try Data("png".utf8).write(to: goneURL)
  let env = PersistedEnvelope(
    kind: "plot", plain: "Graphics object",
    artifacts: [PersistedArtifact(
      type: "image", format: "png", path: goneURL.path, status: .present)])
  let session = Session(
    created: now, updated: now,
    rows: [SessionRow(input: "plot", sage: "plot(sin(x),(x,0,1))",
      result: env, status: .ok, timestamp: now)])
  try store.save(session)
  try FileManager.default.removeItem(at: goneURL)  // /tmp cleanup simulation

  guard case let .restored(restored) = store.load() else {
    Issue.record("expected .restored")
    return
  }
  let status = restored.rows[0].result?.artifacts.first?.status
  #expect(status == .missing)
  // The row still has plain text — it restores, it doesn't fail.
  #expect(restored.rows[0].result?.plain == "Graphics object")
}

// MARK: Provenance & supersede policy

@Test func difference_identicalEnvelopesAreEquivalent() {
  let a = PersistedEnvelope(kind: "integer", plain: "2", latex: "2")
  let b = PersistedEnvelope(kind: "integer", plain: "2", latex: "2")
  #expect(WorkerDriver.difference(cached: a, replayed: b) == nil)
}

@Test func difference_changedPlainIsReported() {
  let a = PersistedEnvelope(kind: "integer", plain: "999")
  let b = PersistedEnvelope(kind: "integer", plain: "2")
  #expect(WorkerDriver.difference(cached: a, replayed: b) == "plain changed")
}

@Test func difference_ignoresArtifactPathsButCatchesFormatSetChange() {
  // Same formats, different paths → NOT a meaningful difference (fresh worker
  // writes new /tmp paths every run).
  let cached = PersistedEnvelope(kind: "plot", plain: "Graphics",
    artifacts: [PersistedArtifact(type: "image", format: "png", path: "/tmp/a.png")])
  let replayedSamePaths = PersistedEnvelope(kind: "plot", plain: "Graphics",
    artifacts: [PersistedArtifact(type: "image", format: "png", path: "/tmp/b.png")])
  #expect(WorkerDriver.difference(cached: cached, replayed: replayedSamePaths) == nil)

  // Different FORMAT set → reported.
  let replayedDifferentFormats = PersistedEnvelope(kind: "plot", plain: "Graphics",
    artifacts: [
      PersistedArtifact(type: "image", format: "png", path: "/tmp/b.png"),
      PersistedArtifact(type: "image", format: "svg", path: "/tmp/b.svg"),
    ])
  #expect(
    WorkerDriver.difference(cached: cached, replayed: replayedDifferentFormats)
      == "artifact set changed")
}

@Test func provenanceCachedHelper() {
  #expect(Provenance.cached.kind == .cached)
  #expect(Provenance.cached.replayedAt == nil)
}

// MARK: Worker-response mapping (pure — no worker, just the JSON shape)

@Test func mapsWorkerValueEnvelope() {
  let response: [String: Any] = [
    "id": "r", "ok": true, "value": true, "kind": "rational",
    "plain": "8/15", "latex": "\\frac{8}{15}", "repr": "8/15",
    "approx": "0.5333333333", "approx_digits": 10, "exact": true,
    "primary_is_approx": false,
    "actions": ["numerator", "denominator", "approx"],
    "artifacts": [], "truncated": false, "stdout": "", "stderr": "",
  ]
  let env = PersistedEnvelope(workerResponse: response)
  #expect(env.kind == "rational")
  #expect(env.plain == "8/15")
  #expect(env.approx == "0.5333333333")
  #expect(env.approxDigits == 10)
  #expect(env.exact == true)
  #expect(env.actions == ["numerator", "denominator", "approx"])
  #expect(env.stdout == nil)  // empty string folds to nil
}

@Test func mapsWorkerErrorEnvelope() {
  let response: [String: Any] = [
    "id": "e", "ok": false, "kind": "error",
    "plain": "rational division by zero", "latex": NSNull(),
    "repr": "rational division by zero",
    "actions": ["copy_traceback"],
    "error": [
      "type": "ZeroDivisionError",
      "message": "rational division by zero",
      "traceback": "Traceback ...",
    ],
    "artifacts": [], "stdout": "", "stderr": "",
  ]
  let env = PersistedEnvelope(workerResponse: response)
  #expect(env.kind == "error")
  #expect(env.error?.type == "ZeroDivisionError")
  #expect(RowStatus(workerResponse: response) == .error)
}

@Test func mapsWorkerArtifactEntries() {
  let response: [String: Any] = [
    "ok": true, "kind": "plot", "plain": "Graphics object", "value": true,
    "artifacts": [
      ["type": "image", "format": "svg", "path": "/tmp/x.svg", "bytes": 100],
      ["type": "image", "format": "png", "path": "/tmp/x.png", "bytes": 200],
    ],
  ]
  let env = PersistedEnvelope(workerResponse: response)
  #expect(env.artifacts.count == 2)
  #expect(env.artifacts[0].format == "svg")
  // Files don't exist → liveness resolves to .missing immediately.
  #expect(env.artifacts.allSatisfy { $0.status == .missing })
}

@Test func rowStatusFromInterrupted() {
  let response: [String: Any] = ["ok": false, "kind": "interrupted"]
  #expect(RowStatus(workerResponse: response) == .interrupted)
}

// MARK: Storage location policy

@Test func defaultDirectoryHonorsConfigOverride() {
  let override = "/tmp/casette-cfg-\(UUID().uuidString)"
  setenv("CASETTE_CONFIG_DIR", override, 1)
  defer { unsetenv("CASETTE_CONFIG_DIR") }
  let dir = SessionStore.defaultSessionsDirectory()
  #expect(dir.path == override + "/sessions")
}

@Test func defaultDirectoryUsesApplicationSupportWhenNoOverride() {
  unsetenv("CASETTE_CONFIG_DIR")
  let dir = SessionStore.defaultSessionsDirectory()
  #expect(dir.path.contains("Casette/sessions"))
  #expect(dir.path.contains("Application Support"))
}
