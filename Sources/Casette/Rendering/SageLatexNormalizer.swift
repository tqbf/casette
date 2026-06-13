import Foundation

// MARK: - LaTeX normalization (the V0.4 boundary)
//
// LIFTED from v0/04-latex-rendering MathRenderer.swift (see the note in
// Rendering/MathRenderer.swift). Worker LaTeX is valid, but each engine has
// quirks; normalize at the boundary so the engine sees input it can render.
// Documented in plans/MATH-RENDERING.md. The abstraction absorbs these so
// app code stays clean.

enum SageLatexNormalizer {

    /// Normalize for SwiftMath (the active engine). SwiftMath renders braced
    /// scripts, sums, partials, bmatrix, and set-builder natively — its one
    /// gap is the `array` environment, which Sage uses for every matrix. So
    /// the load-bearing transform here is Sage
    /// `\left(\begin{array}{…}…\end{array}\right)` → `\begin{pmatrix}…\end{pmatrix}`
    /// (and `[`→bmatrix, `|`→vmatrix, `\{`→Bmatrix).
    static func normalizeForSwiftMath(_ latex: String) -> String {
        let collapsed = collapseWhitespace(latex)
        let unwrapped = stripRedundantRelationParens(collapsed)
        return rewriteSageArrayMatrices(unwrapped)
    }

    /// SwiftMath can parse Sage's tuple-list basis LaTeX, but measured on
    /// macOS it can assert while laying out nested `\left[ \left( ... \right) ]`
    /// groups such as `right_kernel().basis()`. Treat that family as unsupported
    /// so result cards fall back to the worker's plain text instead of crashing.
    static func isUnsafeForSwiftMathLayout(_ normalizedLatex: String) -> Bool {
        normalizedLatex.range(
            of: #"\\left\[\s*\\left\("#,
            options: .regularExpression
        ) != nil
    }

    private static func collapseWhitespace(_ latex: String) -> String {
        latex
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strip Sage's redundant parens around a bare numeric relation side
    /// (V1.5 fix round, display-only). Sage's own `latex()` of a solve list
    /// wraps negative/rational right-hand sides:
    ///   `\left[x = \left(-3\right), x = \left(\frac{3}{2}\right)\right]`
    /// The parens around a LONE signed number after a relation sign carry no
    /// meaning, so the card shows `x = -3`. Deliberately narrow: only after
    /// `= ` / `< ` / `> `, only a bare signed integer, `a/b`, or
    /// `\frac{a}{b}`, and never when the group carries a script (`^`/`_`,
    /// where the parens would be load-bearing). Copy LaTeX still yields
    /// Sage's own unmodified string — this rewrites the DISPLAYED math only.
    static func stripRedundantRelationParens(_ s: String) -> String {
        guard let re = try? NSRegularExpression(
            pattern: #"([=<>] )\\left\((-?(?:\d+(?:/\d+)?|\\frac\{\d+\}\{\d+\}))\\right\)(?![\^_])"#
        ) else { return s }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: "$1$2")
    }

    /// Rewrite Sage's `array`-based matrices into SwiftMath's delimiter matrix
    /// environments. Sage emits e.g.
    ///   `\left(\begin{array}{rr} 1 & 2 \\ 3 & 4 \end{array}\right)`
    /// SwiftMath has no `array`, but supports `pmatrix`/`bmatrix`/`vmatrix`,
    /// which carry their own delimiters — so we drop the `\left(…\right)`
    /// wrapper and the `{rr}` column spec and pick the matrix env from the
    /// delimiter Sage used. The cell body (`&`, `\\`) is unchanged.
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
