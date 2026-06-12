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
/// reports the label's fitting size to SwiftUI (via `sizeThatFits`) so the
/// row reserves the right height — without this the NSView collapses to zero
/// and the math overlaps the row header (PROBLEMS.md V0.4). Dark mode is
/// handled by the semantic, dynamic `NSColor.labelColor`.
private struct SwiftMathLabel: NSViewRepresentable {
    let latex: String
    let displayStyle: MathDisplayStyle

    private var fontSize: CGFloat {
        displayStyle == .block ? Theme.mathBlockPointSize : Theme.mathInlinePointSize
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
    /// The size MUST come from `fittingSize`: SwiftMath's
    /// `intrinsicContentSize` override exists on iOS ONLY, so on macOS that
    /// property returns NSView's no-intrinsic sentinel `(-1, -1)` — which
    /// silently sized every hero 0pt wide × (fontSize+6)pt tall. Single-line
    /// math overdrew its frame and happened to look right; fractions and
    /// matrices were squeezed/clipped (PROBLEMS.md, V1.5 fix round).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: MTMathUILabel, context: Context) -> CGSize? {
        configure(label)
        let fitted = label.fittingSize
        let width = max(fitted.width, 0)
        let height = max(fitted.height, fontSize) + 6
        return CGSize(width: width, height: height)
    }

    private func configure(_ label: MTMathUILabel) {
        if label.fontSize != fontSize { label.fontSize = fontSize }
        let mode: MTMathUILabelMode = displayStyle == .block ? .display : .text
        if label.labelMode != mode { label.labelMode = mode }
        label.textAlignment = .left
        label.textColor = .labelColor          // dynamic: adapts to dark mode
        if label.latex != latex { label.latex = latex }
    }
}
