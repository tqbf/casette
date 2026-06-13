import Foundation
import SwiftMath
import Testing
@testable import Casette

// MARK: - The V1.5 rendering boundary
//
// The normalizer rules are the V0.4 contract (plans/MATH-RENDERING.md):
// Sage's `array` matrices rewrite to SwiftMath's delimiter environments,
// whitespace collapses, everything else passes through. `MathContent` is the
// card-level fallback decision: math when the engine parses the LaTeX,
// `plain` otherwise — malformed LaTeX must never crash and never vanish.

@Suite("SageLatexNormalizer (lifted V0.4 rules)")
struct SageLatexNormalizerTests {
    @Test("Sage's parenthesized array matrix becomes pmatrix")
    func parenArrayBecomesPmatrix() {
        let sage = "\\left(\\begin{array}{rr}\n1 & 2 \\\\\n3 & 4\n\\end{array}\\right)"
        let out = SageLatexNormalizer.normalizeForSwiftMath(sage)
        #expect(out == "\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}")
    }

    @Test("bracket / bar / brace delimiters map to their matrix environments")
    func delimiterVariants() {
        #expect(SageLatexNormalizer.rewriteSageArrayMatrices(
            "\\left[\\begin{array}{r}1\\end{array}\\right]")
            == "\\begin{bmatrix}1\\end{bmatrix}")
        #expect(SageLatexNormalizer.rewriteSageArrayMatrices(
            "\\left|\\begin{array}{r}1\\end{array}\\right|")
            == "\\begin{vmatrix}1\\end{vmatrix}")
        #expect(SageLatexNormalizer.rewriteSageArrayMatrices(
            "\\left\\{\\begin{array}{r}1\\end{array}\\right\\}")
            == "\\begin{Bmatrix}1\\end{Bmatrix}")
    }

    @Test("a bare array (no \\left wrapper) becomes plain matrix")
    func bareArrayBecomesMatrix() {
        #expect(SageLatexNormalizer.rewriteSageArrayMatrices(
            "\\begin{array}{cc}a & b\\end{array}")
            == "\\begin{matrix}a & b\\end{matrix}")
    }

    @Test("cell bodies (& and \\\\) are untouched by the rewrite")
    func cellBodyUnchanged() {
        let out = SageLatexNormalizer.rewriteSageArrayMatrices(
            "\\left(\\begin{array}{rrr}1 & x^{2} & \\frac{1}{3} \\\\ 4 & 5 & 6\\end{array}\\right)")
        #expect(out.contains("1 & x^{2} & \\frac{1}{3} \\\\ 4 & 5 & 6"))
    }

    @Test("newlines collapse to spaces; non-matrix LaTeX passes through")
    func whitespaceAndPassthrough() {
        #expect(SageLatexNormalizer.normalizeForSwiftMath("\\frac{8}{15}\n") == "\\frac{8}{15}")
        let poly = "x^{8} + 8 \\, x^{7} + 28 \\, x^{6}"
        #expect(SageLatexNormalizer.normalizeForSwiftMath(poly) == poly)
    }

    @Test("a surrounding expression around the matrix survives")
    func surroundingExpressionSurvives() {
        let out = SageLatexNormalizer.rewriteSageArrayMatrices(
            "2 \\, \\left(\\begin{array}{rr}1 & 0 \\\\ 0 & 1\\end{array}\\right) + I")
        #expect(out == "2 \\, \\begin{pmatrix}1 & 0 \\\\ 0 & 1\\end{pmatrix} + I")
    }
}

@Suite("Redundant relation parens strip (V1.5 fix round, display-only)")
struct RelationParensTests {
    @Test("Sage's solve-list parens around bare numbers strip: x = (-3) reads x = -3")
    func bareNumericParensStrip() {
        // The real Sage 9.5 shape for solve(x^2+5*x+6==0, x).
        #expect(SageLatexNormalizer.stripRedundantRelationParens(
            #"\left[x = \left(-3\right), x = \left(-2\right)\right]"#)
            == #"\left[x = -3, x = -2\right]"#)
        // …and for a rational solution (solve(2*x==3, x)).
        #expect(SageLatexNormalizer.stripRedundantRelationParens(
            #"\left[x = \left(\frac{3}{2}\right)\right]"#)
            == #"\left[x = \frac{3}{2}\right]"#)
    }

    @Test("the strip is narrow: scripted, symbolic, and unrelated parens all survive")
    func loadBearingParensSurvive() {
        // A scripted group's parens are load-bearing.
        let scripted = #"x = \left(-3\right)^{2}"#
        #expect(SageLatexNormalizer.stripRedundantRelationParens(scripted) == scripted)
        // Non-numeric content is untouched (Sage emits y = \frac{1}{x}
        // unwrapped anyway, but stay safe).
        let symbolic = #"y = \left(\frac{1}{x}\right)"#
        #expect(SageLatexNormalizer.stripRedundantRelationParens(symbolic) == symbolic)
        // Parens not preceded by a relation sign are untouched.
        let bare = #"2 \, \left(-3\right)"#
        #expect(SageLatexNormalizer.stripRedundantRelationParens(bare) == bare)
        // Matrix latex never matches (no relation sign before \left().
        let matrix = #"\left(\begin{array}{rr}-1 & 2 \\ 3 & 4\end{array}\right)"#
        #expect(SageLatexNormalizer.stripRedundantRelationParens(matrix) == matrix)
    }
}

@MainActor
@Suite("MathContent fallback selection (V0.4 graceful degradation)")
struct MathContentTests {
    @Test("valid LaTeX renders as math")
    func validLatexIsMath() {
        #expect(MathContent.choose(latex: "\\frac{8}{15}") == .math(latex: "\\frac{8}{15}"))
        // The real Sage matrix form parses too (after normalization).
        let matrix = "\\left(\\begin{array}{rr}\n1 & 2 \\\\\n3 & 4\n\\end{array}\\right)"
        #expect(MathContent.choose(latex: matrix) == .math(latex: matrix))
    }

    @Test("missing or empty LaTeX falls back to plain")
    func missingLatexIsPlain() {
        #expect(MathContent.choose(latex: nil) == .plain)
        #expect(MathContent.choose(latex: "") == .plain)
    }

    @Test("malformed LaTeX falls back to plain — never crashes")
    func malformedLatexIsPlain() {
        #expect(MathContent.choose(latex: "\\badmacro{unclosed") == .plain)
        #expect(MathContent.choose(latex: "\\begin{array}{rr}1\\end{nonsense}") == .plain)
    }

    @Test("legacy basis-vector tuple lists fall back before SwiftMath layout")
    func legacyBasisVectorTupleListFallsBack() {
        let basis = #"\left[\left(1,\,-2,\,1\right)\right]"#
        let normalized = SageLatexNormalizer.normalizeForSwiftMath(basis)
        #expect(SageLatexNormalizer.hasNestedLeftRightGroup(normalized))
        #expect(SageLatexNormalizer.isUnsafeForSwiftMathLayout(normalized))
        #expect(MathContent.choose(latex: basis) == .plain)
    }

    @Test("nested delimiter groups fall back before SwiftMath spacing asserts")
    func nestedDelimiterGroupsFallBack() {
        let nested = #"\left\{\left(x + 1\right),\,2\right\}"#
        let normalized = SageLatexNormalizer.normalizeForSwiftMath(nested)
        #expect(SageLatexNormalizer.hasNestedLeftRightGroup(normalized))
        #expect(MathContent.choose(latex: nested) == .plain)
    }

    @Test("legacy flat vector tuple latex falls back before SwiftMath spacing asserts")
    func legacyFlatVectorTupleFallsBack() {
        let vector = #"\left(0,\,1,\,2,\,3,\,4,\,5,\,6\right)"#
        let normalized = SageLatexNormalizer.normalizeForSwiftMath(vector)
        #expect(SageLatexNormalizer.hasFlatCommaDelimitedLeftRightGroup(normalized))
        #expect(SageLatexNormalizer.isUnsafeForSwiftMathLayout(normalized))
        #expect(MathContent.choose(latex: vector) == .plain)
    }

    @Test("sequential delimiter groups still render")
    func sequentialDelimiterGroupsAreSafe() {
        let sequential = #"\left(x + 1\right) + \left(y + 1\right)"#
        let normalized = SageLatexNormalizer.normalizeForSwiftMath(sequential)
        #expect(!SageLatexNormalizer.hasNestedLeftRightGroup(normalized))
        #expect(MathContent.choose(latex: sequential) == .math(latex: sequential))
    }

    @Test("normalized matrices are not treated as nested delimiter groups")
    func normalizedMatricesAreSafe() {
        let matrix = "\\left(\\begin{array}{rr}1 & 2 \\\\ 3 & 4\\end{array}\\right)"
        let normalized = SageLatexNormalizer.normalizeForSwiftMath(matrix)
        #expect(normalized == "\\begin{pmatrix}1 & 2 \\\\ 3 & 4\\end{pmatrix}")
        #expect(!SageLatexNormalizer.hasNestedLeftRightGroup(normalized))
        #expect(MathContent.choose(latex: matrix) == .math(latex: matrix))
    }

    @Test("worker basis-vector LaTeX renders as math")
    func workerBasisVectorLatexRendersAsMath() {
        let basis = #"\mathcal{B} = \left\{\begin{pmatrix}1 \\ -2 \\ 1\end{pmatrix}\right\}"#
        #expect(!SageLatexNormalizer.isUnsafeForSwiftMathLayout(
            SageLatexNormalizer.normalizeForSwiftMath(basis)
        ))
        #expect(MathContent.choose(latex: basis) == .math(latex: basis))
    }

    @Test("the cache memoizes and stays consistent across repeat lookups")
    func cacheIsConsistent() {
        let latex = "\\sqrt{2}"
        let first = MathRenderCache.entry(for: latex)
        let second = MathRenderCache.entry(for: latex)
        #expect(first.parses && second.parses)
        #expect(first.normalized == second.normalized)
    }
}

// MARK: - SwiftMath sizing facts the hero layout relies on (V1.5 fix round)
//
// The wrapper's `sizeThatFits` must read `MTMathUILabel.fittingSize`:
// SwiftMath overrides `intrinsicContentSize` on iOS ONLY, so on macOS that
// property returns NSView's no-intrinsic sentinel (-1, -1) — which silently
// sized every hero 0pt wide × (fontSize+6)pt tall and squeezed/clipped
// fractions and matrices on screen. These tests lock in the engine facts so
// a SwiftMath version bump that changes them fails loudly.

@MainActor
@Suite("SwiftMath hero sizing (fittingSize, display mode)")
struct SwiftMathSizingTests {
    @Test("fittingSize carries the typeset size; intrinsicContentSize is the macOS sentinel")
    func fittingSizeCarriesTheMathSize() {
        let label = MTMathUILabel()
        label.fontSize = Theme.mathBlockPointSize
        label.labelMode = .display
        label.latex = "\\frac{8}{15}"
        let fitted = label.fittingSize
        #expect(fitted.width > 10)
        #expect(fitted.height > 30)  // full-size digits stacked over the bar
        // The trap: on macOS there is no intrinsicContentSize override.
        #expect(label.intrinsicContentSize.width < 0)
        #expect(label.intrinsicContentSize.height < 0)
    }

    @Test("hero policy: display mode typesets a fraction at full size, text mode at script size")
    func displayModeFractionIsFullSize() {
        func size(_ mode: MTMathUILabelMode) -> CGSize {
            let label = MTMathUILabel()
            label.fontSize = Theme.mathBlockPointSize
            label.labelMode = mode
            label.latex = "\\frac{8}{15}"
            return label.fittingSize
        }
        let display = size(.display)
        let text = size(.text)
        // Display-mode digits are full size — the hero must never invert the
        // visual hierarchy against the input echo line.
        #expect(display.height > text.height)
        #expect(display.width > text.width)
    }
}
