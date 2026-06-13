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
    /// A worker statement with no echoed value — the row renders input only.
    /// Simple assignments compiled by the app append a final expression and
    /// therefore normally render the assigned value instead.
    var isStatement: Bool {
        guard status == .ok, let result else { return false }
        return result.kind == "none" || result.plain.isEmpty
    }

    /// The row's result is a plot (the card renders its PNG artifacts —
    /// V1.7).
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

    /// Which V1.5 result card this row renders. Derived from status + the
    /// frozen envelope fields; presentation only.
    var cardKind: ResultCardKind { ResultCardKind(row: self) }

    /// The row's Sage as a reusable EXPRESSION for follow-up commands — the
    /// V1.6 Actions tab's `(<expr>).det()` strategy (`ResultAction`). For an
    /// echoed assignment (`A = ...\nA`), the reusable expression is the assigned
    /// name. nil when the row can't honestly be re-stated as one expression.
    var reusableExpression: String? {
        guard status == .ok, !isStatement, !sage.isEmpty else { return nil }
        if let assignedName = assignmentEchoName(in: sage) { return assignedName }
        guard !sage.contains("\n") else { return nil }
        return sage
    }

    /// The Sage command the card's "Approximate Numerically" context-menu
    /// item evaluates (`(<expr>).n()`) — exactly the Actions tab's `approx`
    /// action, surfaced on the card so a full-precision approximation row is
    /// one click away (V1.8). nil when the worker didn't offer `approx` for
    /// this kind (matrix/list/plot/error — no scalar approximation; real/
    /// complex — already numeric) or the row has no reusable expression.
    var approximateCommand: String? {
        guard let result, result.actions.contains("approx"),
              let expression = reusableExpression
        else { return nil }
        return ResultAction(name: "approx").command(wrapping: expression)
    }

    /// The tape abbreviates large matrix LaTeX with explicit ellipses. When
    /// that happens, the row should show the table-view affordance; the table
    /// content itself is fetched from Sage's stored row value by the model.
    var hasAbbreviatedMatrixDisplay: Bool {
        guard result?.kind == "matrix",
              let latex = result?.latex,
              latex.contains("\\cdots") || latex.contains("\\vdots")
        else { return false }
        return true
    }

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

private func assignmentEchoName(in sage: String) -> String? {
    let lines = sage.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count == 2 else { return nil }
    let echo = lines[1].trimmedApp
    guard !echo.isEmpty, lines[0].trimmedApp.hasPrefix("\(echo) =") else { return nil }
    return echo.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } ? echo : nil
}

private extension StringProtocol {
    var trimmedApp: String {
        var sub = Substring(self)
        while let first = sub.first, first == " " || first == "\t" { sub = sub.dropFirst() }
        while let last = sub.last, last == " " || last == "\t" { sub = sub.dropLast() }
        return String(sub)
    }
}

extension PersistedEnvelope {
    /// The honest truncation note for a capped result ("showing N of M
    /// characters", per the worker's truncation object), or nil when the
    /// result wasn't truncated. Falls back to a plain "Truncated by Sage"
    /// when the sizes weren't recorded (e.g. a pre-V1.5 restored session).
    var truncationNote: String? {
        guard truncated else { return nil }
        guard let total = truncation?.plainLength else { return "Truncated by Sage" }
        return "Truncated — showing \(plain.count.formatted()) of \(total.formatted()) characters"
    }
}
