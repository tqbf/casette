import Foundation

/// One point-in-time snapshot of the live user symbol table — what the worker
/// `symbols` op returns (V0.6: the full list, cheap enough to re-fetch after
/// every eval). Each refresh REPLACES the whole snapshot; entries are never
/// patched incrementally (SWIFTUI-RULES §3.2 — rebuild, don't patch).
///
/// Not part of the persisted session (SESSION-FORMAT.md has no symbols — the
/// table is derived live from the namespace, and a restore without a worker
/// has no namespace to ask).
struct SymbolSnapshot: Equatable, Sendable {
    /// Sorted by name, exactly as the worker `symbols` op returns them.
    var entries: [SymbolEntry]
    /// When the snapshot was taken; nil when no worker has ever answered
    /// (placeholder data, pre-V1.3).
    var capturedAt: Date?

    static let empty = SymbolSnapshot(entries: [], capturedAt: nil)

    func visibleEntries(showingBuiltinSymbols: Bool) -> [SymbolEntry] {
        guard !showingBuiltinSymbols else { return entries }
        return entries.filter { !$0.isUntouchedBootVariable }
    }
}
