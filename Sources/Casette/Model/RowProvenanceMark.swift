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
    /// Loaded from the last session's file — visible on the tape, but not
    /// present in the current Sage namespace until Replay Session recomputes
    /// it.
    case cached
    /// Recomputed by Replay Session (re-sent into a fresh worker).
    case replayed

    /// The quiet tag text shown next to the row's timestamp.
    var label: String {
        switch self {
        case .cached: "not live"
        case .replayed: "replayed"
        }
    }

    /// Tooltip explaining what the tag means.
    var help: String {
        switch self {
        case .cached:
            "Restored from your last session — visible here, but not live in Sage until you replay the session."
        case .replayed:
            "Recomputed by Replay Session in a fresh Sage worker."
        }
    }

    /// The Inspector's "Source" field text.
    var inspectorDescription: String {
        switch self {
        case .cached: "Restored cache (not live in the current Sage session)"
        case .replayed: "Replayed (recomputed this session)"
        }
    }
}
