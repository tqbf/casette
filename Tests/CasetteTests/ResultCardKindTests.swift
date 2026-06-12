import Foundation
import Testing
@testable import Casette

/// The envelope→card mapping (INITIAL.md V1.5 card vocabulary). Presentation
/// derivation only — the envelope is never changed by it.
@Suite("ResultCardKind mapping")
struct ResultCardKindTests {
    private func okRow(_ result: PersistedEnvelope) -> SessionRow {
        SessionRow(input: "i", sage: "i", result: result, status: .ok, timestamp: .now)
    }

    @Test("exact scalars: integer and rational")
    func scalarExact() {
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "integer", plain: "4", exact: true, primaryIsApprox: false)) == .scalarExact)
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "rational", plain: "8/15", exact: true, primaryIsApprox: false)) == .scalarExact)
    }

    @Test("approximate scalars: real/complex, and force-numeric exact kinds")
    func scalarApproximate() {
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "real", plain: "2.5", exact: false, primaryIsApprox: true)) == .scalarApproximate)
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "complex", plain: "3.0 + 4.0*I", exact: false)) == .scalarApproximate)
        // V0.8 force-numeric: an exact rational displayed numerically.
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "rational", plain: "0.3333333333", primaryIsApprox: true,
            exactValue: "1/3")) == .scalarApproximate)
    }

    @Test("symbolic and relation → symbolic card")
    func symbolicCard() {
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "symbolic", plain: "sqrt(2)")) == .symbolic)
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "relation", plain: "x == 1")) == .symbolic)
    }

    @Test("matrix, list, plot")
    func structuredKinds() {
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "matrix", plain: "[1 2]\n[3 4]")) == .matrix)
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "list", plain: "[3, 1]")) == .list)
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "plot", plain: "Graphics object")) == .plot)
    }

    @Test("text, boolean, and unknown degrade to the text card")
    func textishKinds() {
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "text", plain: "hello")) == .text)
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "boolean", plain: "True")) == .text)
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "unknown", plain: "[2, 1, 3]")) == .text)
    }

    @Test("a statement (kind none / empty plain) is the statement card")
    func statementCard() {
        #expect(ResultCardKind(okEnvelope: PersistedEnvelope(
            kind: "none", plain: "", stdout: "hello\n")) == .statement)
    }

    @Test("row status drives pending / error / interrupted")
    func statusDriven() {
        let pending = SessionRow(input: "2+2", sage: "2+2", result: nil, status: .running, timestamp: .now)
        #expect(pending.cardKind == .pending)

        let error = SessionRow(
            input: "1/0", sage: "1/0",
            result: PersistedEnvelope(
                kind: "error", plain: "rational division by zero",
                error: PersistedError(type: "ZeroDivisionError", message: "rational division by zero")),
            status: .error, timestamp: .now)
        #expect(error.cardKind == .error)

        let interrupted = SessionRow(
            input: "sleep(30)", sage: "sleep(30)",
            result: PersistedEnvelope(
                kind: "interrupted", plain: "",
                error: PersistedError(type: "KeyboardInterrupt", message: "eval interrupted")),
            status: .interrupted, timestamp: .now)
        #expect(interrupted.cardKind == .interrupted)
    }

    @Test("card kind never mutates the envelope (presentation only)")
    func presentationOnly() throws {
        let row = okRow(PersistedEnvelope(
            kind: "rational", plain: "8/15", latex: "\\frac{8}{15}", approx: "0.5333333333"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys  // deterministic bytes
        let before = try encoder.encode(row.result)
        _ = row.cardKind
        let after = try encoder.encode(row.result)
        #expect(before == after)
    }
}

@Suite("Truncation display (the honest 'N of M chars')")
struct TruncationDisplayTests {
    @Test("a truncated envelope with sizes renders shown-of-total")
    func noteWithSizes() {
        let envelope = PersistedEnvelope(
            kind: "integer", plain: String(repeating: "9", count: 8192) + " …",
            truncated: true,
            truncation: PersistedTruncation(plainLength: 456_574, plainCap: 8192))
        let note = envelope.truncationNote
        #expect(note != nil)
        #expect(note?.contains((8192 + 2).formatted()) == true)  // shown (incl. " …")
        #expect(note?.contains(456_574.formatted()) == true)     // of M
    }

    @Test("truncated without recorded sizes still says so (pre-V1.5 files)")
    func noteWithoutSizes() {
        let envelope = PersistedEnvelope(kind: "integer", plain: "123 …", truncated: true)
        #expect(envelope.truncationNote == "Truncated by Sage")
    }

    @Test("not truncated → no note")
    func noNote() {
        #expect(PersistedEnvelope(kind: "integer", plain: "4").truncationNote == nil)
    }

    @Test("the truncation field round-trips Codable and is omitted when nil")
    func codableRoundTrip() throws {
        let with = PersistedEnvelope(
            kind: "integer", plain: "x", truncated: true,
            truncation: PersistedTruncation(plainLength: 100, reprLength: 90, plainCap: 10, reprCap: 10))
        let data = try JSONEncoder().encode(with)
        let decoded = try JSONDecoder().decode(PersistedEnvelope.self, from: data)
        #expect(decoded == with)

        // nil truncation encodes to a file WITHOUT the key — schema v1 files
        // stay byte-compatible (the additive-field rule).
        let without = PersistedEnvelope(kind: "integer", plain: "4")
        let text = String(decoding: try JSONEncoder().encode(without), as: UTF8.self)
        #expect(!text.contains("truncation\""))
    }
}
