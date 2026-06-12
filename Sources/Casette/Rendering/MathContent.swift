import Foundation

/// The card-level fallback decision for a result's hero: render the
/// envelope's `latex` as math, or fall back to `plain` monospaced text.
///
/// The V0.4 graceful-degradation contract, applied where the card can make a
/// BETTER choice than the renderer: when LaTeX is missing or SwiftMath can't
/// parse it, the most useful thing to show isn't the broken LaTeX source —
/// it's the result's `plain` text, which the worker always provides. The
/// renderer's own raw-source fallback remains as the backstop for direct
/// `MathView` callers.
@MainActor
enum MathContent: Equatable {
    /// Render this LaTeX (pre-validated to parse) through `MathView`.
    case math(latex: String)
    /// No usable LaTeX — render the envelope's `plain` text, monospaced.
    case plain

    /// Picks the hero content for an envelope's `latex` field. Never crashes
    /// on malformed LaTeX; parse validation is memoized (`MathRenderCache`).
    static func choose(latex: String?) -> MathContent {
        guard let latex, !latex.isEmpty else { return .plain }
        return MathRenderCache.entry(for: latex).parses ? .math(latex: latex) : .plain
    }
}
