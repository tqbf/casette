import Foundation
import Testing
@testable import Casette

// MARK: - Fixtures

/// A scratch store in a unique temp directory (hermetic per test — no
/// `setenv`, per PROBLEMS.md "Parallel swift-testing + setenv").
func makeScratchStore() -> SessionStore {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "casette-store-tests-\(UUID().uuidString)")
    return SessionStore(directory: directory)
}

func removeScratch(_ store: SessionStore) {
    try? FileManager.default.removeItem(at: store.directory)
}

/// A representative session exercising every persisted surface: a friendly
/// row, an exact scalar with the V1.5 `truncation`-shaped fields absent, a
/// plot row with artifacts (incl. a V1.7 save `error`), an error row, and a
/// V1.8 numeric row.
func fixtureSession(precisionDigits: Int = 10) -> Session {
    let created = Date(timeIntervalSince1970: 1_700_000_000)
    let cachedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let rows = [
        SessionRow(
            input: "factor x^4 - 1",
            sage: "factor(x^4 - 1)",
            result: PersistedEnvelope(
                kind: "symbolic",
                plain: "(x^2 + 1)*(x + 1)*(x - 1)",
                latex: "{\\left(x^{2} + 1\\right)}",
                repr: "(x^2 + 1)*(x + 1)*(x - 1)",
                exact: true,
                actions: ["factor", "expand"]),
            status: .ok,
            timestamp: cachedAt,
            durationSeconds: 0.012,
            provenance: Provenance(kind: .cached, cachedAt: cachedAt)),
        SessionRow(
            input: "plot sin(x), x=-pi..pi",
            sage: "plot(sin(x), (x, -pi, pi))",
            result: PersistedEnvelope(
                kind: "plot",
                plain: "Graphics object consisting of 1 graphics primitive",
                artifacts: [
                    PersistedArtifact(
                        type: "image", format: "svg",
                        path: "/tmp/sagecalc/session-gone/plot-00001.svg",
                        bytes: 20587, status: .present),
                    PersistedArtifact(
                        type: "image", format: "png",
                        path: nil, status: .missing,
                        error: "OSError: disk full"),
                ]),
            status: .ok,
            timestamp: cachedAt,
            durationSeconds: 0.4,
            provenance: Provenance(kind: .cached, cachedAt: cachedAt),
            expanded: true),
        SessionRow(
            input: "1/0",
            sage: "1/0",
            result: PersistedEnvelope(
                kind: "error",
                plain: "division by zero",
                truncated: true,
                truncation: PersistedTruncation(plainLength: 99, plainCap: 50),
                error: PersistedError(
                    type: "ZeroDivisionError", message: "division by zero",
                    traceback: "Traceback...")),
            status: .error,
            timestamp: cachedAt,
            provenance: Provenance(kind: .cached, cachedAt: cachedAt)),
        SessionRow(
            input: "1/3",
            sage: "1/3",
            result: PersistedEnvelope(
                kind: "rational",
                plain: "0.3333333333",
                latex: "\\frac{1}{3}",
                exact: true,
                primaryIsApprox: true,
                exactValue: "1/3"),
            status: .ok,
            timestamp: cachedAt,
            provenance: Provenance(kind: .cached, cachedAt: cachedAt),
            numeric: true),
    ]
    return Session(
        created: created, updated: created, sageVersion: "9.5",
        precisionDigits: precisionDigits, rows: rows)
}

// MARK: - Store behavior (the v0/10 equivalents, against the APP's store)

@Suite("SessionStore (V1.9 persistence)")
struct SessionStoreTests {
    @Test("save → load restores the session, all three additive fields included")
    func saveThenLoadRestoresSession() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        let session = fixtureSession(precisionDigits: 20)
        try store.save(session)

        guard case let .restored(loaded) = store.load() else {
            Issue.record("expected .restored, got \(store.load())")
            return
        }
        #expect(loaded.schemaVersion == 1)
        #expect(loaded.precisionDigits == 20)
        #expect(loaded.sageVersion == "9.5")
        #expect(loaded.rows.count == 4)
        #expect(loaded.rows.map(\.id) == session.rows.map(\.id))
        #expect(loaded.rows[0].result == session.rows[0].result)
        // The three POST-LIFT additive fields survive the round trip:
        #expect(loaded.rows[2].result?.truncation?.plainLength == 99)  // V1.5
        #expect(loaded.rows[1].result?.artifacts[1].error == "OSError: disk full")  // V1.7
        #expect(loaded.rows[3].numeric == true)  // V1.8
        #expect(loaded.rows[0].numeric == nil)
        // Persisted UI state and the input/sage split survive too.
        #expect(loaded.rows[1].expanded == true)
        #expect(loaded.rows[0].input == "factor x^4 - 1")
        #expect(loaded.rows[0].sage == "factor(x^4 - 1)")
    }

    @Test("the file is pretty-printed, sorted-keys, human-inspectable JSON")
    func fileIsHumanInspectable() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try store.save(fixtureSession())
        let text = try String(contentsOf: store.sessionFileURL, encoding: .utf8)
        // Pretty-printed (newlines + indentation), keys present in sorted
        // order, slashes unescaped (paths must read as paths).
        #expect(text.contains("\n"))
        #expect(text.contains("\"schemaVersion\""))
        #expect(text.contains("/tmp/sagecalc/session-gone/plot-00001.svg"))
        #expect(!text.contains("\\/"))
        if let created = text.range(of: "\"created\""),
           let rows = text.range(of: "\"rows\"") {
            #expect(created.lowerBound < rows.lowerBound)  // sorted keys
        } else {
            Issue.record("expected created/rows keys in the file")
        }
        // A row evaluated normally carries NO numeric key (omitted-when-nil).
        #expect(text.components(separatedBy: "\"numeric\"").count == 2)
    }

    @Test("missing file → .fresh")
    func missingFileIsFresh() {
        let store = makeScratchStore()
        #expect(store.load() == .fresh)
    }

    @Test("empty file → .fresh (an empty isn't corrupt)")
    func emptyFileIsFresh() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try FileManager.default.createDirectory(
            at: store.directory, withIntermediateDirectories: true)
        try Data().write(to: store.sessionFileURL)
        #expect(store.load() == .fresh)
    }

    @Test("corrupt JSON → quarantined aside + fresh start, never a crash")
    func corruptJSONIsQuarantined() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try FileManager.default.createDirectory(
            at: store.directory, withIntermediateDirectories: true)
        try Data("{not json!".utf8).write(to: store.sessionFileURL)

        guard case let .corruptQuarantined(quarantinePath, _) = store.load() else {
            Issue.record("expected .corruptQuarantined")
            return
        }
        // The bad file moved aside (kept for forensics), the slot is free.
        #expect(FileManager.default.fileExists(atPath: quarantinePath))
        #expect(!FileManager.default.fileExists(atPath: store.sessionFileURL.path))
        #expect(store.load() == .fresh)
        // And saving works again.
        try store.save(fixtureSession())
        if case .restored = store.load() {} else {
            Issue.record("expected a clean save after quarantine")
        }
    }

    @Test("unknown schema version → polite refusal, file left INTACT")
    func unknownSchemaIsRefusedAndFileIntact() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try FileManager.default.createDirectory(
            at: store.directory, withIntermediateDirectories: true)
        // A future shape strict decoding would ALSO fail on — the peek must
        // classify it as version-refused, not corrupt (PROBLEMS.md V0.10).
        let future = #"{"schemaVersion": 99, "tape": {"totally": "different"}}"#
        try Data(future.utf8).write(to: store.sessionFileURL)

        #expect(store.load() == .refusedSchema(found: 99, supported: 1))
        let after = try String(contentsOf: store.sessionFileURL, encoding: .utf8)
        #expect(after == future)  // don't quarantine the future
    }

    @Test("incremental save rewrites in place and leaves no temp files")
    func incrementalSaveLeavesNoTempFiles() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        var session = fixtureSession()
        try store.save(session)
        session.rows.append(SessionRow(
            input: "2 + 2", sage: "2 + 2",
            result: PersistedEnvelope(kind: "integer", plain: "4"),
            status: .ok, timestamp: .now))
        try store.save(session)

        let contents = try FileManager.default.contentsOfDirectory(
            atPath: store.directory.path)
        #expect(contents == ["last-session.json"])
        guard case let .restored(loaded) = store.load() else {
            Issue.record("expected .restored")
            return
        }
        #expect(loaded.rows.count == 5)
    }

    @Test("load re-resolves artifact liveness: gone files flip present → missing, the row still restores")
    func loadReResolvesArtifactLiveness() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        // One artifact that REALLY exists, one recorded present whose file is
        // gone (the normal restored-plot case), one that never saved.
        let liveFile = store.directory.appending(path: "live-plot.png")
        try FileManager.default.createDirectory(
            at: store.directory, withIntermediateDirectories: true)
        try Data([0x89, 0x50]).write(to: liveFile)

        var session = fixtureSession()
        session.rows[1].result?.artifacts.append(PersistedArtifact(
            type: "image", format: "png", path: liveFile.path,
            bytes: 2, status: .missing))
        try store.save(session)

        guard case let .restored(loaded) = store.load() else {
            Issue.record("expected .restored")
            return
        }
        let artifacts = loaded.rows[1].result?.artifacts
        #expect(artifacts?[0].status == .missing)  // recorded present, file gone
        #expect(artifacts?[1].status == .missing)  // nil path stays missing
        #expect(artifacts?[2].status == .present)  // the real file
        // The plot row itself restored intact (missing is NOT an error).
        #expect(loaded.rows[1].result?.kind == "plot")
        #expect(loaded.rows[1].status == .ok)
    }

    @Test("default directory honors an injected CASETTE_CONFIG_DIR (no setenv)")
    func defaultDirectoryHonorsInjectedOverride() {
        let url = SessionStore.defaultSessionsDirectory(
            environment: ["CASETTE_CONFIG_DIR": "/tmp/casette-cfg-test"])
        #expect(url.path == "/tmp/casette-cfg-test/sessions")
    }

    @Test("default directory is Application Support/Casette/sessions without an override")
    func defaultDirectoryUsesApplicationSupport() {
        let url = SessionStore.defaultSessionsDirectory(environment: [:])
        #expect(url.path.hasSuffix("Application Support/Casette/sessions"))
    }
}

// MARK: - Replay logic (pure)

@Suite("SessionReplay (difference + preludes)")
struct SessionReplayTests {
    private func envelope(
        kind: String = "integer", plain: String = "4", latex: String? = "4",
        approx: String? = nil, artifacts: [PersistedArtifact] = []
    ) -> PersistedEnvelope {
        PersistedEnvelope(
            kind: kind, plain: plain, latex: latex, approx: approx,
            artifacts: artifacts)
    }

    @Test("identical envelopes are equivalent (no spurious supersession)")
    func identicalEnvelopesAreEquivalent() {
        #expect(SessionReplay.difference(cached: envelope(), replayed: envelope()) == nil)
    }

    @Test("a changed plain / kind / approx is reported")
    func changedFieldsAreReported() {
        #expect(SessionReplay.difference(
            cached: envelope(plain: "999"), replayed: envelope(plain: "4")) == "plain changed")
        #expect(SessionReplay.difference(
            cached: envelope(kind: "rational"), replayed: envelope(kind: "integer"))
            == "kind changed (rational → integer)")
        #expect(SessionReplay.difference(
            cached: envelope(approx: "0.5"), replayed: envelope(approx: "0.6")) == "approx changed")
    }

    @Test("artifact PATHS are never identity — only the format set is compared")
    func artifactPathsAreIgnored() {
        let cached = envelope(artifacts: [
            PersistedArtifact(type: "image", format: "svg", path: "/tmp/old/plot-00001.svg"),
            PersistedArtifact(type: "image", format: "png", path: "/tmp/old/plot-00001.png"),
        ])
        let replayedSamePaths = envelope(artifacts: [
            PersistedArtifact(type: "image", format: "png", path: "/tmp/NEW/plot-00007.png"),
            PersistedArtifact(type: "image", format: "svg", path: "/tmp/NEW/plot-00007.svg"),
        ])
        // New paths, new order, same format set → equivalent.
        #expect(SessionReplay.difference(cached: cached, replayed: replayedSamePaths) == nil)
        // A genuinely different format SET is a supersession.
        let pngOnly = envelope(artifacts: [
            PersistedArtifact(type: "image", format: "png", path: "/tmp/NEW/plot-00008.png")
        ])
        #expect(SessionReplay.difference(cached: cached, replayed: pngOnly) == "artifact set changed")
    }

    @Test("preludes: friendly rows re-declare required variables; bypasses declare none")
    func preludesFollowTheCompilerPolicy() {
        let friendly = SessionRow(
            input: "integral t^2, t=0..2", sage: "integrate(t^2, (t, 0, 2))",
            status: .ok, timestamp: .now)
        #expect(SessionReplay.preludes(for: friendly) == ["var('t')"])

        let bypass = SessionRow(
            input: "A = matrix([[1,2],[3,4]])", sage: "A = matrix([[1,2],[3,4]])",
            status: .ok, timestamp: .now)
        #expect(SessionReplay.preludes(for: bypass) == [])
    }

    @Test("preludes: an ambiguous-compiling input uses its RECORDED resolution, never re-asks")
    func preludesForAmbiguousUseRecordedResolution() {
        // "solve x*y = 1" compiles ambiguous (solve for x? for y?); the row
        // recorded the user's choice. Replay derives variables from that.
        let row = SessionRow(
            input: "solve x*y = 1", sage: "solve(x*y == 1, y)",
            status: .ok, timestamp: .now)
        let preludes = SessionReplay.preludes(for: row)
        #expect(preludes.contains("var('x')"))
        #expect(preludes.contains("var('y')"))
    }
}
