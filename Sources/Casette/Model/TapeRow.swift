import Foundation

/// Placeholder tape-row model for the V1.1 shell. Field names and meanings
/// mirror the frozen contracts (SESSION-FORMAT.md `SessionRow` +
/// WORKER-PROTOCOL.md envelope) so the real V1.2 session model can swap in
/// without reshaping any view: `input` vs `sage` is the friendly-compiler
/// split, `kind`/`plain`/`latex`/`approx`/`actions` are envelope fields.
struct TapeRow: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case ok
        case error
        /// V1.1 only: the row was submitted but there is no kernel yet (V1.3).
        case notEvaluated
    }

    let id = UUID()
    var input: String
    var sage: String
    var status: Status
    /// Worker envelope `kind` (frozen kind set).
    var kind: String
    /// Worker envelope `plain` — the primary result text. Empty for a
    /// statement row (assignment), which echoes no value.
    var primary: String
    /// Worker envelope `latex` — carried for the Inspector tab; rendered
    /// math arrives in V1.5.
    var latex: String?
    /// Worker envelope `approx` — the secondary `≈ …` line (V0.8 policy).
    var approx: String?
    /// Error type name (e.g. `ZeroDivisionError`) for `.error` rows.
    var errorType: String?
    /// Worker envelope per-kind `actions` (drives the Actions tab).
    var actions: [String] = []
    var timestamp: Date
    var duration: TimeInterval?

    /// A statement (assignment) echoes no value — the row renders input only.
    var isStatement: Bool { status == .ok && primary.isEmpty }

    /// V1.1 stand-in for a real plot artifact (V1.7 renders PNG artifacts).
    var isPlot: Bool { kind == "plot" }
}
