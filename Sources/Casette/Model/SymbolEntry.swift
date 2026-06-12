import Foundation

/// One symbol-table entry, mirroring the worker `symbols` op response
/// (`{name, kind, summary}`, WORKER-PROTOCOL.md V0.6). Live as of V1.3: the
/// sidebar refreshes from the real op after every evaluation.
struct SymbolEntry: Identifiable, Equatable, Sendable {
    var name: String
    var kind: String
    var summary: String

    var id: String { name }

    /// Kinds whose V0.6 summary IS the literal value (a bounded repr), so a
    /// `name = summary` snippet is real, pasteable Sage.
    private static let valueKinds: Set<String> = [
        "integer", "rational", "real", "complex", "boolean",
    ]

    /// What the Symbols tab's "Copy Sage" yields: the pasteable assignment
    /// `name = value` when the summary is honestly the value (scalar kinds,
    /// not truncated), else just the name — always valid Sage, while matrix
    /// summaries like "2×2 over Integer Ring" are descriptions, not values.
    var sageSnippet: String {
        if Self.valueKinds.contains(kind), !summary.hasSuffix("…") {
            return "\(name) = \(summary)"
        }
        return name
    }
}
