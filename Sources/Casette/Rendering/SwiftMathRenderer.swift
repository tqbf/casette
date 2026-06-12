import SwiftUI
import SwiftMath

// MARK: - SwiftMath-backed renderer (the ACTIVE engine)
//
// LIFTED from v0/04-latex-rendering MathRenderer.swift (see the note in
// Rendering/MathRenderer.swift). SwiftMath: native Core Text math
// typesetting. Fully offline, no JavaScript bridge, fast. Renders the spec's
// braced sub/superscripts, sums with limits, partials, bmatrix, and
// set-builder that the MathJax-based alternative couldn't (PROBLEMS.md).
// Sage's `array` matrices are rewritten to `pmatrix` by the normalizer.
//
// V1.5 additions over the v0/04 shape (both perf, per MATH-RENDERING.md's
// caching recommendation and PROBLEMS.md's no-main-thread-hitches rule):
//   * normalize+parse-validate goes through `MathRenderCache` (hover/selection
//     re-renders and LazyVStack row recycling stop re-running the regex
//     rewrite and the parser on every body evaluation), and
//   * `SwiftMathLabel.configure` only re-assigns `label.latex` when the
//     string actually changed (assigning re-typesets; `sizeThatFits` +
//     `updateNSView` both run per layout pass).
//
// V1.7 fix-round HARDENING (the AttributeGraph infinite-update-loop hang;
// PROBLEMS.md "AttributeGraph spin"):
//   * EVERY property write in `configure` is change-guarded. SwiftMath's
//     `textAlignment`/`labelMode`/`font(Size)` setters unconditionally call
//     `invalidateIntrinsicContentSize()` + `setNeedsLayout()`, and
//     `textColor` rebuilds the display list's attributed strings +
//     `setNeedsDisplay()`. An unguarded write inside `updateNSView` (which
//     runs INSIDE a SwiftUI graph update) re-invalidates the hosted view's
//     layout metrics, which enqueues ANOTHER graph update, which runs
//     `updateNSView` again — the loop never converges and the main thread
//     spins at 100%.
//   * `sizeThatFits` is PURE: it never touches the live, hosted label.
//     Measurement goes through `MathMeasurementCache` — a never-hosted
//     offscreen `MTMathUILabel` whose self-invalidations are inert, behind
//     a bounded memo so repeated layout passes don't re-typeset at all.
//
// The invariant (do not regress it): no NSViewRepresentable in a tape row
// may write to its own NSView during measurement, and every write during
// `updateNSView` must be a real change — a view whose size depends on a
// value it invalidates is an infinite loop.

struct SwiftMathRenderer: MathRenderer {
    let engineName = "SwiftMath · native Core Text (offline)"

    func render(_ latex: String, displayStyle: MathDisplayStyle) -> some View {
        let entry = MathRenderCache.entry(for: latex)
        return Group {
            if entry.parses {
                SwiftMathLabel(latex: entry.normalized, displayStyle: displayStyle)
            } else {
                // Graceful degradation (the V0.4 contract): malformed LaTeX
                // never crashes and never vanishes — the raw source shows,
                // subtly. (Result cards normally pre-check via
                // `MathContent.choose` and fall back to `plain` instead, so
                // this is the renderer-level backstop.)
                Text(entry.normalized)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// `NSViewRepresentable` wrapper around SwiftMath's `MTMathUILabel`. It
/// reports the label's typeset size to SwiftUI (via `sizeThatFits`, computed
/// on an offscreen measuring instance — NEVER the live view) so the row
/// reserves the right height — without this the NSView collapses to zero
/// and the math overlaps the row header (PROBLEMS.md V0.4). Dark mode is
/// handled by the semantic, dynamic `NSColor.labelColor`.
private struct SwiftMathLabel: NSViewRepresentable {
    let latex: String
    let displayStyle: MathDisplayStyle

    private var fontSize: CGFloat {
        displayStyle == .block ? Theme.mathBlockPointSize : Theme.mathInlinePointSize
    }

    private var mode: MTMathUILabelMode {
        displayStyle == .block ? .display : .text
    }

    func makeNSView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.displayErrorInline = false
        label.setContentHuggingPriority(.required, for: .vertical)
        configure(label)
        return label
    }

    func updateNSView(_ label: MTMathUILabel, context: Context) {
        configure(label)
    }

    /// Report the typeset math size to SwiftUI so the row lays out
    /// correctly; add a small vertical margin so ascenders and descenders
    /// aren't clipped.
    ///
    /// PURE BY CONSTRUCTION (V1.7 fix round): measurement never writes to
    /// the hosted label — `MTMathUILabel`'s setters invalidate intrinsic
    /// content size, and an invalidation issued from inside a measurement
    /// pass re-enqueues the very layout that asked, spinning the
    /// AttributeGraph forever (PROBLEMS.md). The size comes from
    /// `MathMeasurementCache`'s offscreen instance instead.
    ///
    /// The size MUST come from `fittingSize`: SwiftMath's
    /// `intrinsicContentSize` override exists on iOS ONLY, so on macOS that
    /// property returns NSView's no-intrinsic sentinel `(-1, -1)` — which
    /// silently sized every hero 0pt wide × (fontSize+6)pt tall. Single-line
    /// math overdrew its frame and happened to look right; fractions and
    /// matrices were squeezed/clipped (PROBLEMS.md, V1.5 fix round).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: MTMathUILabel, context: Context) -> CGSize? {
        let fitted = MathMeasurementCache.fittedSize(latex: latex, fontSize: fontSize, mode: mode)
        let width = max(fitted.width, 0)
        let height = max(fitted.height, fontSize) + 6
        return CGSize(width: width, height: height)
    }

    /// Every write is change-guarded: each of these setters unconditionally
    /// invalidates layout/display, and `updateNSView` runs inside the graph
    /// update — an unconditional write here IS the infinite-loop bug this
    /// file's header documents.
    private func configure(_ label: MTMathUILabel) {
        if label.fontSize != fontSize { label.fontSize = fontSize }
        if label.labelMode != mode { label.labelMode = mode }
        if label.textAlignment != .left { label.textAlignment = .left }
        // .labelColor is dynamic: set once, it keeps adapting to dark mode.
        if label.textColor != .labelColor { label.textColor = .labelColor }
        if label.latex != latex { label.latex = latex }
    }
}

/// Offscreen, memoized math measurement. The measuring label is never
/// hosted in a window, so the invalidations its setters issue are inert —
/// the live tape labels are measured WITHOUT being touched. Bounded memo
/// (whole-reset on overflow — a self-patching cache is its own bug class,
/// SWIFTUI-RULES §3.2; same policy as `MathRenderCache`).
@MainActor
private enum MathMeasurementCache {
    private static let capacity = 1024
    private static var sizes: [String: CGSize] = [:]
    private static let measuringLabel = MTMathUILabel()

    static func fittedSize(latex: String, fontSize: CGFloat, mode: MTMathUILabelMode) -> CGSize {
        let key = "\(mode == .display ? "D" : "T")|\(fontSize)|\(latex)"
        if let hit = sizes[key] { return hit }
        if sizes.count >= capacity { sizes.removeAll(keepingCapacity: true) }
        if measuringLabel.fontSize != fontSize { measuringLabel.fontSize = fontSize }
        if measuringLabel.labelMode != mode { measuringLabel.labelMode = mode }
        if measuringLabel.latex != latex { measuringLabel.latex = latex }
        let size = measuringLabel.fittingSize
        sizes[key] = size
        return size
    }
}
