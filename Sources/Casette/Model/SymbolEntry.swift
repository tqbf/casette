import Foundation

/// Placeholder symbol-table entry. Mirrors the worker `symbols` op response
/// (`{name, kind, summary}`, WORKER-PROTOCOL.md V0.6) so V1.6 can feed the
/// live op straight into the same view.
struct SymbolEntry: Identifiable, Equatable, Sendable {
    var name: String
    var kind: String
    var summary: String

    var id: String { name }
}
