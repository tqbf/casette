import Foundation

/// The quiet per-row provenance mark (V1.9): shown ONLY where a row's result
/// did not come from a fresh evaluation in this app run — restored-from-disk
/// (`cached`) or recomputed by Replay Session (`replayed`). A row evaluated
/// normally this run shows nothing (fresh is the default; marking it would be
/// noise — V0.10's call: quiet).
///
/// Derived presentation, never persisted: the persisted `Provenance` can't
/// distinguish "evaluated just now" from "loaded from disk" (a fresh eval is
/// recorded as `cached` because that's what a later restore loads), so
/// `ShellModel` keeps the transient set of row IDs that arrived via restore
/// and derives the mark from membership + the persisted provenance kind.
enum RowProvenanceMark: Equatable {
    /// Loaded from the last session's file — Sage was not involved.
    case cached
    /// Recomputed by Replay Session (re-sent into a fresh worker).
    case replayed

    /// The quiet tag text shown next to the row's timestamp.
    var label: String {
        switch self {
        case .cached: "cached"
        case .replayed: "replayed"
        }
    }

    /// Tooltip explaining what the tag means.
    var help: String {
        switch self {
        case .cached:
            "Restored from your last session — this result was not recomputed."
        case .replayed:
            "Recomputed by Replay Session in a fresh Sage worker."
        }
    }

    /// The Inspector's "Source" field text.
    var inspectorDescription: String {
        switch self {
        case .cached: "Cached (restored from the last session)"
        case .replayed: "Replayed (recomputed this session)"
        }
    }
}
