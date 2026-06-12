import Foundation
import Testing
@testable import Casette

// MARK: - The lifted V0.10 model in the app (V1.2)
//
// These cover the V1.2 exit criteria at the type level (stable identity,
// result data independent of UI rendering) and pin the lift to the frozen
// SESSION-FORMAT.md schema so V1.9's SessionStore is a drop-in.

private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

private func sampleRow(expanded: Bool = false) -> SessionRow {
    let when = Date(timeIntervalSince1970: 1_700_000_000)
    return SessionRow(
        input: "1/3 + 1/5",
        sage: "1/3 + 1/5",
        result: PersistedEnvelope(
            kind: "rational", plain: "8/15", latex: "\\frac{8}{15}", repr: "8/15",
            approx: "0.5333333333", approxDigits: 10, exact: true,
            primaryIsApprox: false, actions: ["numerator", "denominator", "approx"]
        ),
        status: .ok,
        timestamp: when,
        durationSeconds: 0.01,
        provenance: Provenance(kind: .cached, cachedAt: when),
        expanded: expanded
    )
}

@Suite("Session model (lifted V0.10 types)")
struct SessionModelTests {
    // V1.2 exit criterion: rows have stable identity.
    @Test("row identity survives a Codable round trip")
    func identitySurvivesRoundTrip() throws {
        let row = sampleRow()
        let session = Session(created: .now, updated: .now, rows: [row])
        let data = try makeEncoder().encode(session)
        let decoded = try makeDecoder().decode(Session.self, from: data)
        #expect(decoded.rows.count == 1)
        #expect(decoded.rows[0].id == row.id)
        #expect(decoded.rows[0] == row)
    }

    @Test("the encoded file speaks the frozen SESSION-FORMAT.md vocabulary")
    func encodedFieldNamesMatchSessionFormat() throws {
        let session = Session(
            created: .now, updated: .now, sageVersion: "9.5",
            precisionDigits: 10, rows: [sampleRow()]
        )
        let text = String(decoding: try makeEncoder().encode(session), as: UTF8.self)
        // Header fields.
        for key in ["schemaVersion", "created", "updated", "sageVersion", "precisionDigits", "rows"] {
            #expect(text.contains("\"\(key)\""), "missing header field \(key)")
        }
        // Row fields (SESSION-FORMAT.md "Session row" table).
        for key in ["id", "input", "sage", "status", "timestamp", "durationSeconds", "provenance", "expanded", "result"] {
            #expect(text.contains("\"\(key)\""), "missing row field \(key)")
        }
        // Envelope fields.
        for key in ["kind", "plain", "latex", "repr", "approx", "approxDigits", "exact", "primaryIsApprox", "actions", "artifacts", "truncated"] {
            #expect(text.contains("\"\(key)\""), "missing envelope field \(key)")
        }
        #expect(text.contains("\"schemaVersion\" : 1"))
    }

    // V1.2 exit criterion: result data is independent of UI rendering.
    @Test("flipping UI state never changes what the result IS")
    func resultDataIndependentOfUIState() throws {
        let collapsed = sampleRow(expanded: false)
        var expanded = collapsed
        expanded.expanded = true

        // The result envelope is identical regardless of UI state…
        #expect(collapsed.result == expanded.result)
        // …and so are its encoded bytes (the envelope carries zero UI fields).
        let encoder = makeEncoder()
        let collapsedResult = try encoder.encode(collapsed.result)
        let expandedResult = try encoder.encode(expanded.result)
        #expect(collapsedResult == expandedResult)

        // The envelope's vocabulary contains no UI-state words at all.
        let text = String(decoding: collapsedResult, as: UTF8.self)
        #expect(!text.contains("expanded"))
        #expect(!text.contains("selected"))
        #expect(!text.contains("hovered"))
    }

    @Test("interrupted rows are representable")
    func interruptedRepresentable() {
        var row = sampleRow()
        row.apply(
            Evaluation(
                status: .interrupted,
                result: PersistedEnvelope(
                    kind: "interrupted", plain: "Interrupted",
                    error: PersistedError(type: "KeyboardInterrupt", message: "Interrupted")
                ),
                duration: 2.0
            )
        )
        #expect(row.status == .interrupted)
        #expect(row.errorType == "KeyboardInterrupt")
    }

    @Test("apply(_:) changes only the outcome fields")
    func applyPreservesIdentityAndInput() {
        let original = sampleRow()
        var row = original
        row.apply(Evaluation(status: .ok, result: PersistedEnvelope(kind: "integer", plain: "4"), duration: 0.5))
        #expect(row.id == original.id)
        #expect(row.input == original.input)
        #expect(row.sage == original.sage)
        #expect(row.timestamp == original.timestamp)
        #expect(row.result?.plain == "4")
        #expect(row.durationSeconds == 0.5)
    }

    // V1.2 exit criterion: rows can be copied — SessionRow is a value type,
    // so a copy is independent of the original (and the strings the Copy
    // menu reads are all carried by the model).
    @Test("a copied row is an independent value")
    func copiedRowIsIndependent() {
        let original = sampleRow()
        var copy = original
        copy.input = "changed"
        copy.result = nil
        #expect(original.input == "1/3 + 1/5")
        #expect(original.result != nil)
        // Everything the tape's Copy menu offers comes straight off the row.
        #expect(!original.input.isEmpty)
        #expect(!original.sage.isEmpty)
        #expect(original.result?.plain == "8/15")
        #expect(original.result?.latex == "\\frac{8}{15}")
    }

    @Test("derived presentation helpers")
    func derivedHelpers() {
        let statement = SessionRow(
            input: "x = var(\"x\")", sage: "x = var(\"x\")",
            result: PersistedEnvelope(kind: "none", plain: ""),
            status: .ok, timestamp: .now
        )
        #expect(statement.isStatement)
        #expect(!statement.isPlot)

        let pending = SessionRow(
            input: "2+2", sage: "2+2", result: nil, status: .running, timestamp: .now
        )
        #expect(pending.isPending)
        #expect(!pending.isStatement)

        let plot = SessionRow(
            input: "plot sin(x)", sage: "plot(sin(x))",
            result: PersistedEnvelope(kind: "plot", plain: "Graphics object"),
            status: .ok, timestamp: .now
        )
        #expect(plot.isPlot)
        #expect(!plot.isStatement)
    }

    @Test("artifact liveness resolves against the filesystem")
    func artifactLiveness() throws {
        // A gone path → missing; a nil path → missing.
        let gone = PersistedArtifact(
            type: "image", format: "png",
            path: "/tmp/casette-no-such-\(UUID().uuidString).png"
        )
        #expect(gone.resolvingLiveness().status == .missing)
        #expect(PersistedArtifact(type: "image", format: "svg", path: nil)
            .resolvingLiveness().status == .missing)

        // A real file → present.
        let real = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("casette-live-\(UUID().uuidString).png")
        try Data("png".utf8).write(to: real)
        defer { try? FileManager.default.removeItem(at: real) }
        let present = PersistedArtifact(type: "image", format: "png", path: real.path)
        #expect(present.resolvingLiveness().status == .present)
    }
}

// The V1.2 CompiledInput suite moved to CompiledInputTests.swift, where the
// V1.4 compile boundary (compiler outcomes, prelude policy) is tested too.

@Suite("KernelState")
struct KernelStateTests {
    @Test("only notConnected reads as disconnected")
    func connectivity() {
        #expect(!KernelState.notConnected.isConnected)
        let connected: [KernelState] = [
            .idle, .running, .completed, .error, .interrupted,
            .timedOut, .crashed, .restarting,
        ]
        #expect(connected.allSatisfy { $0.isConnected })
    }

    @Test("work is accepted only in the settled, alive states")
    func canAcceptWork() {
        let accepting: [KernelState] = [.idle, .completed, .error, .interrupted, .timedOut]
        let refusing: [KernelState] = [.notConnected, .running, .crashed, .restarting]
        #expect(accepting.allSatisfy { $0.canAcceptWork })
        #expect(refusing.allSatisfy { !$0.canAcceptWork })
    }

    @Test("the machine covers the V0.2 eight states plus notConnected")
    func mirrorsTheEightStateMachine() {
        let v02States: Set<String> = [
            "idle", "running", "completed", "error",
            "interrupted", "timed_out", "crashed", "restarting",
        ]
        let appStates: [KernelState] = [
            .idle, .running, .completed, .error,
            .interrupted, .timedOut, .crashed, .restarting,
        ]
        #expect(Set(appStates.map(\.rawValue)) == v02States)
        #expect(KernelState.notConnected.rawValue == "not_connected")
    }
}

@Suite("Worker envelope mapping (lifted V0.10 boundary)")
struct EnvelopeMappingTests {
    @Test("maps a worker value envelope")
    func mapsValueEnvelope() {
        let response: [String: Any] = [
            "id": "r", "ok": true, "value": true, "kind": "rational",
            "plain": "8/15", "latex": "\\frac{8}{15}", "repr": "8/15",
            "approx": "0.5333333333", "approx_digits": 10, "exact": true,
            "primary_is_approx": false,
            "actions": ["numerator", "denominator", "approx"],
            "artifacts": [], "truncated": false, "stdout": "", "stderr": "",
        ]
        let envelope = PersistedEnvelope(workerResponse: response)
        #expect(envelope.kind == "rational")
        #expect(envelope.plain == "8/15")
        #expect(envelope.approx == "0.5333333333")
        #expect(envelope.approxDigits == 10)
        #expect(envelope.exact == true)
        #expect(envelope.actions == ["numerator", "denominator", "approx"])
        #expect(envelope.stdout == nil)  // empty string folds to nil
        #expect(RowStatus(workerResponse: response) == .ok)
    }

    @Test("maps a worker error envelope")
    func mapsErrorEnvelope() {
        let response: [String: Any] = [
            "id": "e", "ok": false, "kind": "error",
            "plain": "rational division by zero",
            "error": [
                "type": "ZeroDivisionError",
                "message": "rational division by zero",
                "traceback": "Traceback ...",
            ],
        ]
        let envelope = PersistedEnvelope(workerResponse: response)
        #expect(envelope.kind == "error")
        #expect(envelope.error?.type == "ZeroDivisionError")
        #expect(RowStatus(workerResponse: response) == .error)
    }

    @Test("maps artifact entries and resolves liveness immediately")
    func mapsArtifacts() {
        let response: [String: Any] = [
            "ok": true, "kind": "plot", "plain": "Graphics object", "value": true,
            "artifacts": [
                ["type": "image", "format": "svg", "path": "/tmp/x.svg", "bytes": 100],
                ["type": "image", "format": "png", "path": "/tmp/x.png", "bytes": 200],
            ],
        ]
        let envelope = PersistedEnvelope(workerResponse: response)
        #expect(envelope.artifacts.count == 2)
        #expect(envelope.artifacts[0].format == "svg")
        // Files don't exist → liveness resolves to .missing immediately.
        #expect(envelope.artifacts.allSatisfy { $0.status == .missing })
    }

    @Test("an interrupted response maps to the interrupted status")
    func mapsInterrupted() {
        let response: [String: Any] = ["ok": false, "kind": "interrupted"]
        #expect(RowStatus(workerResponse: response) == .interrupted)
    }
}
