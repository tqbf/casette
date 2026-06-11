import Foundation

/// The corpus the proof renders. Three provenances matter:
///   1. The spec's five hand-authored test LaTeX snippets (V0.4 INITIAL.md).
///   2. Real `latex` strings pulled from the canonical V0.1 worker (Sage 9.5) —
///      captured live, NOT hand-typed, so we prove the actual envelope renders.
///   3. An inline case, a deliberately invalid case, and bulk filler for scroll.
enum SampleData {

    /// The five spec test snippets, verbatim from plans/INITIAL.md § V0.4.
    static let specCases: [MathResult] = [
        MathResult(
            source: "\\int_0^1 x^2\\,dx",
            kind: "spec", latex: "\\int_0^1 x^2\\,dx",
            plain: "definite integral of x^2 from 0 to 1",
            displayStyle: .block, provenance: .spec),
        MathResult(
            source: "\\begin{bmatrix}1 & 2\\\\ 3 & 4\\end{bmatrix}",
            kind: "spec", latex: "\\begin{bmatrix}1 & 2\\\\ 3 & 4\\end{bmatrix}",
            plain: "2x2 matrix [[1,2],[3,4]] (bmatrix form)",
            displayStyle: .block, provenance: .spec),
        MathResult(
            source: "\\frac{\\partial^2 f}{\\partial x \\partial y}",
            kind: "spec", latex: "\\frac{\\partial^2 f}{\\partial x \\partial y}",
            plain: "mixed second partial derivative",
            displayStyle: .block, provenance: .spec),
        MathResult(
            source: "\\sum_{n=0}^{\\infty} \\frac{x^n}{n!}",
            kind: "spec", latex: "\\sum_{n=0}^{\\infty} \\frac{x^n}{n!}",
            plain: "exponential series sum",
            displayStyle: .block, provenance: .spec),
        MathResult(
            source: "\\left\\{x \\in \\mathbb{R} : x^2 < 2\\right\\}",
            kind: "spec", latex: "\\left\\{x \\in \\mathbb{R} : x^2 < 2\\right\\}",
            plain: "set-builder: { x in R : x^2 < 2 }",
            displayStyle: .block, provenance: .spec),
    ]

    /// Real `latex` fields captured from the canonical worker (Sage 9.5) on
    /// 2026-06-11. These are the actual strings V1 will render — note Sage's
    /// `\left(\begin{array}{rr}` matrix form (NOT bmatrix), its `\,` thin spaces,
    /// `4 i + 3` complex form, and the `\left[ … \right]` solve/list form.
    static let workerCases: [MathResult] = [
        MathResult(
            source: "1/3 + 1/5",
            kind: "rational", latex: "\\frac{8}{15}",
            plain: "8/15", displayStyle: .block, provenance: .worker),
        MathResult(
            source: "matrix([[1,2],[3,4]])",
            kind: "matrix",
            latex: "\\left(\\begin{array}{rr}\n1 & 2 \\\\\n3 & 4\n\\end{array}\\right)",
            plain: "[1 2]\n[3 4]", displayStyle: .block, provenance: .worker),
        MathResult(
            source: "matrix([[1,2],[3,4]]).rref()",
            kind: "matrix",
            latex: "\\left(\\begin{array}{rr}\n1 & 0 \\\\\n0 & 1\n\\end{array}\\right)",
            plain: "[1 0]\n[0 1]", displayStyle: .block, provenance: .worker),
        MathResult(
            source: "expand((x+1)^8)",
            kind: "symbolic",
            latex: "x^{8} + 8 \\, x^{7} + 28 \\, x^{6} + 56 \\, x^{5} + 70 \\, x^{4} + 56 \\, x^{3} + 28 \\, x^{2} + 8 \\, x + 1",
            plain: "x^8 + 8*x^7 + 28*x^6 + 56*x^5 + 70*x^4 + 56*x^3 + 28*x^2 + 8*x + 1",
            displayStyle: .block, provenance: .worker),
        MathResult(
            source: "factor(x^4 - 1)",
            kind: "symbolic",
            latex: "{\\left(x^{2} + 1\\right)} {\\left(x + 1\\right)} {\\left(x - 1\\right)}",
            plain: "(x^2 + 1)*(x + 1)*(x - 1)",
            displayStyle: .block, provenance: .worker),
        MathResult(
            source: "integrate(sin(x)^3, x)",
            kind: "symbolic",
            latex: "\\frac{1}{3} \\, \\cos\\left(x\\right)^{3} - \\cos\\left(x\\right)",
            plain: "1/3*cos(x)^3 - cos(x)",
            displayStyle: .block, provenance: .worker),
        MathResult(
            source: "x^2 + 5*x + 6 == 0",
            kind: "relation",
            latex: "x^{2} + 5 \\, x + 6 = 0",
            plain: "x^2 + 5*x + 6 == 0",
            displayStyle: .block, provenance: .worker),
        MathResult(
            source: "solve(x^2 + 5*x + 6 == 0, x)",
            kind: "list",
            latex: "\\left[x = \\left(-3\\right), x = \\left(-2\\right)\\right]",
            plain: "[x == -3, x == -2]",
            displayStyle: .block, provenance: .worker),
        MathResult(
            source: "diff(sin(x*y), x, y)",
            kind: "symbolic",
            latex: "-x y \\sin\\left(x y\\right) + \\cos\\left(x y\\right)",
            plain: "-x*y*sin(x*y) + cos(x*y)",
            displayStyle: .block, provenance: .worker),
        MathResult(
            source: "3 + 4*I",
            kind: "complex",
            latex: "4 i + 3",
            plain: "4*I + 3",
            displayStyle: .block, provenance: .worker),
        MathResult(
            source: "N(sqrt(2), digits=50)",
            kind: "real",
            latex: "1.4142135623730950488016887242096980785696718753769",
            plain: "1.4142135623730950488016887242096980785696718753769",
            displayStyle: .block, provenance: .worker),
    ]

    /// Inline math: rendered on a text baseline, woven into a sentence.
    static let inlineCases: [MathResult] = [
        MathResult(
            source: "Euler's identity, inline",
            kind: "inline", latex: "e^{i\\pi} + 1 = 0",
            plain: "e^{i pi} + 1 = 0",
            displayStyle: .inline, provenance: .inline),
        MathResult(
            source: "Inline fraction in a sentence",
            kind: "inline", latex: "\\frac{8}{15}",
            plain: "8/15",
            displayStyle: .inline, provenance: .inline),
    ]

    /// Deliberately INVALID LaTeX — unbalanced braces / unknown command. Proves
    /// the graceful-fallback path: no crash, raw source shown as degraded output.
    static let invalidCase = MathResult(
        source: "\\frac{1}{ + \\notacommand{x \\begin{matrix} oops",
        kind: "error",
        latex: "\\frac{1}{ + \\notacommand{x \\begin{matrix} oops",
        plain: "(intentionally malformed LaTeX — should degrade, not crash)",
        displayStyle: .block, provenance: .invalid)

    /// Bulk filler so the list has 50+ rows to judge scrolling performance.
    /// Cycles a few cheap-but-real expressions with a varying index.
    static func bulkCases(count: Int) -> [MathResult] {
        let templates: [(String, String)] = [
            ("sum_{k=1}^{n}", "\\sum_{k=1}^{%d} k = \\frac{%d \\cdot %d}{2}"),
            ("integral", "\\int_0^{%d} x\\,dx = \\frac{%d^2}{2}"),
            ("binomial", "\\binom{%d}{2} = \\frac{%d(%d-1)}{2}"),
            ("root", "\\sqrt{%d} \\approx %d"),
            ("power", "2^{%d} = %d"),
        ]
        return (1...count).map { i in
            let (label, tmpl) = templates[i % templates.count]
            let n = (i % 9) + 2
            // Fill the template's %d slots positionally (harmless if it produces a
            // mathematically loose statement — the point is rendering + scroll).
            let latex = String(format: tmpl, n, n, n, n)
            return MathResult(
                source: "bulk #\(i): \(label)",
                kind: "bulk", latex: latex,
                plain: "bulk row \(i)",
                displayStyle: .block, provenance: .bulk)
        }
    }

    /// The full ordered corpus the app shows: spec → worker → inline → invalid →
    /// bulk (to comfortably exceed 50 rows).
    static let all: [MathResult] =
        specCases
        + workerCases
        + inlineCases
        + [invalidCase]
        + bulkCases(count: 40)
}
