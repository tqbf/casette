import Foundation

// MARK: - App-side additions to the lifted V0.10 session model
//
// SessionModel.swift / PersistedEnvelope.swift are verbatim lifts (kept
// diffable against v0/10). Everything the app layers on top — Identifiable
// for ForEach, derived presentation helpers, and applying an evaluation
// outcome — lives here. All of it is computed/derived; none of it changes the
// Codable shape, so the persisted format stays exactly SESSION-FORMAT.md v1.

extension SessionRow: Identifiable {}

extension SessionRow {
    /// A statement (assignment) echoes no value — the row renders input only.
    /// Derived, never stored: the worker reports a statement as `kind:"none"`
    /// with an empty `plain` (V0.1 None-suppression).
    var isStatement: Bool {
        guard status == .ok, let result else { return false }
        return result.kind == "none" || result.plain.isEmpty
    }

    /// The row's result is a plot (V1.7 renders the PNG artifact).
    var isPlot: Bool { result?.kind == "plot" }

    /// The row was submitted but its evaluation has not completed —
    /// either genuinely in flight (V1.3+) or, with no kernel connected,
    /// honestly "not evaluated". `RowStatus.running` means *incomplete*
    /// (SESSION-FORMAT.md: "on restore a running row is incomplete, not a
    /// result"); which message the UI shows is decided by `KernelState`.
    var isPending: Bool { status == .running }

    /// Error type name (e.g. `ZeroDivisionError`) for error/interrupted rows.
    var errorType: String? { result?.error?.type }

    /// `durationSeconds` under the name the views/spec use.
    var duration: TimeInterval? { durationSeconds }

    /// Applies a finished evaluation to this (pending) row. Identity, input,
    /// sage, and timestamp are untouched — only the outcome fields change.
    /// Provenance becomes `cached` with `cachedAt = date`, matching the V0.10
    /// recorder: a freshly evaluated result is what a later restore loads as
    /// "cached".
    mutating func apply(_ evaluation: Evaluation, at date: Date = .now) {
        status = evaluation.status
        result = evaluation.result
        durationSeconds = evaluation.duration
        provenance = Provenance(kind: .cached, cachedAt: date)
    }
}
