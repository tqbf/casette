import Foundation

// MARK: - Worker `symbols` response (raw JSON) → SymbolSnapshot
//
// The app-side half of the V0.6 `symbols` op (WORKER-PROTOCOL.md): the worker
// returns `{ok, op:"symbols", symbols:[{name, kind, summary}]}` sorted by
// name; each refresh replaces the whole snapshot (§3.2 rebuild-don't-patch).
// Kept out of EnvelopeMapping.swift, which is a verbatim v0/10 lift.

extension SymbolSnapshot {
    /// Builds a snapshot from a raw worker `symbols` response, or nil when
    /// the response isn't a successful symbols reply. Tolerant of missing
    /// per-entry fields (forward-compatible, like the envelope mapping).
    init?(workerResponse response: [String: Any], capturedAt: Date = .now) {
        guard response["ok"] as? Bool == true,
              let list = response["symbols"] as? [[String: Any]]
        else { return nil }
        let entries = list.compactMap { entry -> SymbolEntry? in
            guard let name = entry["name"] as? String else { return nil }
            return SymbolEntry(
                name: name,
                kind: entry["kind"] as? String ?? "",
                summary: entry["summary"] as? String ?? "")
        }
        self.init(entries: entries, capturedAt: capturedAt)
    }
}
