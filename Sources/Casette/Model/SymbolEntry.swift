import Foundation

/// One symbol-table entry, mirroring the worker `symbols` op response
/// (`{name, kind, summary}`, WORKER-PROTOCOL.md V0.6). Live as of V1.3: the
/// sidebar refreshes from the real op after every evaluation.
struct SymbolEntry: Identifiable, Equatable, Sendable {
    var name: String
    var kind: String
    var summary: String

    var id: String { name }
}
