import Foundation

/// The pure logic behind the V1.9 "Replay Session" command: which preludes a
/// row needs before its `sage` is re-sent, and whether a replayed result
/// DIFFERS from the cached one (the V0.10 supersede policy's trigger).
///
/// The replay loop itself lives on `ShellModel` (it drives the kernel queue);
/// everything decidable without a worker lives here, unit-testable.
enum SessionReplay {
    /// The `var('V')` preludes to send before replaying a row — the same
    /// per-row declaration policy submission uses (FRIENDLY-COMPILER.md):
    /// a fresh worker's namespace has none of the original session's
    /// variables, so friendly rows re-declare their required variables.
    ///
    /// Derived by recompiling the row's recorded input, exactly like rerun:
    /// a friendly row reports its `requiredVariables`; a raw-Sage bypass
    /// reports none (the boot prelude's calculator variables plus the tape's own
    /// earlier assignments are its namespace, in order); an input that now
    /// compiles ambiguous uses its RECORDED resolution (`row.sage`), with
    /// variables re-derived by the compiler's own heuristic — replay never
    /// re-asks.
    static func preludes(for row: SessionRow) -> [String] {
        switch CompiledInput.compile(row.input) {
        case let .ready(compiled):
            return compiled.preludes
        case .ambiguous:
            return CompiledInput.chosenCandidate(raw: row.input, sage: row.sage).preludes
        case .error:
            return []  // a previously submitted input can't stop compiling
        }
    }

    /// Returns a short reason string if the two envelopes differ in a way that
    /// matters for display, or nil if they are equivalent. Artifacts are
    /// compared by FORMAT SET only — NEVER by path: a fresh worker writes new
    /// `/tmp` paths every run, so a path diff is not a meaningful supersession
    /// (PROBLEMS.md V0.10 "paths aren't identity"). Ported verbatim from
    /// v0/10's `WorkerDriver.difference`.
    static func difference(
        cached: PersistedEnvelope, replayed: PersistedEnvelope
    ) -> String? {
        if cached.kind != replayed.kind {
            return "kind changed (\(cached.kind) → \(replayed.kind))"
        }
        if cached.plain != replayed.plain {
            return "plain changed"
        }
        if cached.latex != replayed.latex {
            return "latex changed"
        }
        if cached.approx != replayed.approx {
            return "approx changed"
        }
        let cachedFormats = cached.artifacts.map(\.format).sorted()
        let replayedFormats = replayed.artifacts.map(\.format).sorted()
        if cachedFormats != replayedFormats {
            return "artifact set changed"
        }
        return nil
    }
}
