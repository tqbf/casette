import SwiftUI
import AppKit
import SwiftMath
import LaTeXSwiftUI

// MARK: - MathRenderer abstraction
//
// This is the surviving artifact of V0.4. The app never talks to a concrete math
// library directly — it asks a `MathRenderer` for a SwiftUI view. That keeps the
// engine swappable (SwiftMath today; LaTeXSwiftUI or a future "Textual" tomorrow)
// without touching any call site. It migrates into the real app at V1.5.
//
// Why the abstraction earned its keep in V0.4: the product decision named
// "Textual" (disqualified: macOS-15 floor, markdown-only math). We chose
// LaTeXSwiftUI/MathJax next — but on screen it failed every braced sub/superscript
// (`\sum_{n=0}^{\infty}`, `\int_{0}^{1}`, `x^{8}`) in this environment (a
// MathJaxSwift/JavaScriptCore marshaling defect; see PROBLEMS.md). We swapped the
// engine to SwiftMath behind this protocol with ZERO app-code changes. That's the
// whole point.
//
// Contract:
//   - `render(_:displayStyle:)` returns a `View` for a single LaTeX string drawn
//     from the worker envelope's `latex` field (or a hand-authored test snippet).
//   - The renderer is responsible for graceful degradation: malformed LaTeX must
//     NOT crash and must NOT vanish — it shows the raw source as a visible
//     degraded fallback. The app relies on this guarantee.

/// How a piece of math should be laid out in the tape.
enum MathDisplayStyle {
    /// Block / display math — centered, on its own line, full size. The default
    /// for a result row's hero math.
    case block
    /// Inline math — sits on the text baseline at body size, for math woven into
    /// a sentence.
    case inline
}

/// The abstraction every view renders math through. Implementations wrap a
/// concrete typesetting engine. `render` is `@MainActor` because SwiftUI view
/// construction (and the underlying engines) are main-actor-isolated.
@MainActor
protocol MathRenderer {
    associatedtype Body: View
    /// A short identifier for the backing engine, surfaced in the UI footer so we
    /// can tell at a glance which engine produced what's on screen.
    nonisolated var engineName: String { get }
    @ViewBuilder
    func render(_ latex: String, displayStyle: MathDisplayStyle) -> Body
}

// MARK: - LaTeX normalization
//
// Worker LaTeX (and the spec snippets) are valid, but each engine has quirks.
// Normalize at the boundary so the engine sees input it can render. Documented in
// plans/MATH-RENDERING.md. The abstraction absorbs these so app code stays clean.
enum SageLatexNormalizer {

    /// Normalize for SwiftMath (the active engine). SwiftMath renders the spec's
    /// braced scripts, sums, partials, bmatrix, and set-builder natively — its one
    /// gap is the `array` environment, which Sage uses for every matrix. So the
    /// load-bearing transform here is Sage `\left(\begin{array}{…}…\end{array}\right)`
    /// → `\begin{pmatrix}…\end{pmatrix}` (and `[`→bmatrix, `|`→vmatrix).
    static func normalizeForSwiftMath(_ latex: String) -> String {
        let collapsed = collapseWhitespace(latex)
        return rewriteSageArrayMatrices(collapsed)
    }

    /// Normalize for LaTeXSwiftUI/MathJax (the documented alternative).
    static func normalizeForLaTeXSwiftUI(_ latex: String) -> String {
        collapseWhitespace(latex)
    }

    private static func collapseWhitespace(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rewrite Sage's `array`-based matrices into SwiftMath's delimiter matrix
    /// environments. Sage emits e.g.
    ///   `\left(\begin{array}{rr} 1 & 2 \\ 3 & 4 \end{array}\right)`
    /// SwiftMath has no `array`, but supports `pmatrix`/`bmatrix`/`vmatrix`, which
    /// carry their own delimiters — so we drop the `\left(…\right)` wrapper and the
    /// `{rr}` column spec and pick the matrix env from the delimiter Sage used.
    /// The cell body (`&`, `\\`) is unchanged.
    static func rewriteSageArrayMatrices(_ s: String) -> String {
        let variants: [(open: String, close: String, env: String)] = [
            ("\\left(", "\\right)", "pmatrix"),
            ("\\left[", "\\right]", "bmatrix"),
            ("\\left|", "\\right|", "vmatrix"),
            ("\\left\\{", "\\right\\}", "Bmatrix"),
        ]
        var out = s
        for v in variants {
            // \left( \begin{array}{...} BODY \end{array} \right)  ->  \begin{pmatrix} BODY \end{pmatrix}
            let pattern = NSRegularExpression.escapedPattern(for: v.open)
                + #"\s*\\begin\{array\}\{[^}]*\}(.*?)\\end\{array\}\s*"#
                + NSRegularExpression.escapedPattern(for: v.close)
            if let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = re.stringByReplacingMatches(
                    in: out, range: range,
                    withTemplate: "\\\\begin{\(v.env)}$1\\\\end{\(v.env)}")
            }
        }
        // A bare `\begin{array}{...}` with no \left…\right wrapper → plain matrix.
        if let re = try? NSRegularExpression(
            pattern: #"\\begin\{array\}\{[^}]*\}(.*?)\\end\{array\}"#,
            options: [.dotMatchesLineSeparators]) {
            let range = NSRange(out.startIndex..<out.endIndex, in: out)
            out = re.stringByReplacingMatches(
                in: out, range: range,
                withTemplate: "\\\\begin{matrix}$1\\\\end{matrix}")
        }
        return out
    }
}

// MARK: - SwiftMath-backed renderer (the ACTIVE engine)

/// The production renderer: SwiftMath — native Core Text math typesetting. Fully
/// offline, no JavaScript bridge, fast. Renders the spec's braced sub/superscripts,
/// sums with limits, partials, bmatrix, and set-builder that the MathJax-based
/// alternative couldn't in this environment. Sage's `array` matrices are rewritten
/// to `pmatrix` by the normalizer.
struct SwiftMathRenderer: MathRenderer {
    let engineName = "SwiftMath · native Core Text (offline)"

    func render(_ latex: String, displayStyle: MathDisplayStyle) -> some View {
        let cleaned = SageLatexNormalizer.normalizeForSwiftMath(latex)
        // Pre-validate with SwiftMath's parser. On failure, render the raw source
        // as plain text (the spec's graceful degradation) — a pure SwiftUI path,
        // no broken NSView. This keeps the fallback simple and correctly sized.
        var error: NSError?
        _ = MTMathListBuilder.build(fromString: cleaned, error: &error)
        return Group {
            if error == nil {
                SwiftMathLabel(latex: cleaned, displayStyle: displayStyle)
            } else {
                Text(cleaned)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }
}

/// `NSViewRepresentable` wrapper around SwiftMath's `MTMathUILabel`. It reports the
/// label's fitting size to SwiftUI (via `sizeThatFits`) so the row reserves the
/// right height — without this the NSView collapses to zero and the math overlaps
/// the row header. Dark mode is handled by the semantic `NSColor.labelColor`.
private struct SwiftMathLabel: NSViewRepresentable {
    let latex: String
    let displayStyle: MathDisplayStyle

    private var fontSize: CGFloat { displayStyle == .block ? 22 : 15 }

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

    /// Report the intrinsic math size to SwiftUI so the row lays out correctly
    /// (macOS 13+/14 `sizeThatFits` representable API).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: MTMathUILabel, context: Context) -> CGSize? {
        configure(label)
        // MTMathUILabel overrides intrinsicContentSize to the rendered math size.
        // Add a small vertical margin so ascenders/descenders aren't clipped and
        // the row reserves enough height (otherwise tall glyphs overlap siblings).
        let fitted = label.intrinsicContentSize
        let width = max(fitted.width, 0)
        let height = max(fitted.height, fontSize) + 6
        return CGSize(width: width, height: height)
    }

    private func configure(_ label: MTMathUILabel) {
        label.fontSize = fontSize
        label.labelMode = displayStyle == .block ? .display : .text
        label.textAlignment = .left
        label.textColor = .labelColor          // dynamic: adapts to dark mode
        label.latex = latex
    }
}

// MARK: - LaTeXSwiftUI-backed renderer (documented ALTERNATIVE, not active)
//
// Kept in the codebase to prove the abstraction is real and to document the
// MathJax path. It renders Sage's `array` natively but fails braced scripts here
// (PROBLEMS.md). Not wired up — `activeMathRenderer` points at SwiftMath.
struct LaTeXSwiftUIRenderer: MathRenderer {
    let engineName = "LaTeXSwiftUI · MathJax/JavaScriptCore (offline)"

    func render(_ latex: String, displayStyle: MathDisplayStyle) -> some View {
        let cleaned = SageLatexNormalizer.normalizeForLaTeXSwiftUI(latex)
        let wrapped: String = displayStyle == .block
            ? "\\[" + cleaned + "\\]"
            : "\\(" + cleaned + "\\)"
        return LaTeX(wrapped)
            .parsingMode(.onlyEquations)
            .errorMode(.original)            // raw source on failure — no crash
            .imageRenderingMode(.template)
            .blockMode(displayStyle == .block ? .blockViews : .alwaysInline)
            .renderingStyle(.progress)
    }
}

// MARK: - App-facing entry point

/// The single renderer the whole app uses. Swap this one line to change engines —
/// the rest of the app is untouched. That swappability is the V0.4 deliverable.
let activeMathRenderer = SwiftMathRenderer()

/// A thin SwiftUI view that renders one LaTeX string through `activeMathRenderer`.
/// This is what rows actually place on screen; they never see the concrete engine.
struct MathView: View {
    let latex: String
    var displayStyle: MathDisplayStyle = .block

    var body: some View {
        activeMathRenderer.render(latex, displayStyle: displayStyle)
    }
}
