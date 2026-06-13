import Testing
@testable import FriendlyCompiler

// Partial-edit invariance: the completion-UI defect where a half-typed range
// (e.g. `integral x^2, x=0..`) was dropped by the STRICT compiler-grade range
// parser, so the lower bound the user typed vanished when focus moved on.
//
// Each formula family with multi-field state is exercised exactly as the view
// bindings drive it: the bar re-parses the CURRENT draft, mutates ONE field,
// renders `friendlyInput` back to the draft, and the next access re-parses that
// draft. The invariant: after EVERY field edit, re-parsing the rendered draft
// yields an IR EQUAL to the mutated one — i.e. nothing previously typed is lost.
//
// These IRs are the partial-edit surface; the COMPILER still uses the strict
// `parseRange` (an incomplete range is a real compile error, explained in the
// preview line), so this file is about the editing shape, not lowering.

@Suite("Partial-edit invariance (no field is ever lost mid-edit)")
struct PartialEditInvarianceTests {

    // MARK: - Driver

    /// Simulate one bar edit exactly as a view binding does: re-parse the CURRENT
    /// draft, mutate one field, render `friendlyInput` back as the new draft.
    ///
    /// The fixed-point invariant matches the view's data flow. The binding always
    /// RE-READS the IR from a fresh parse of the draft, so the only thing that can
    /// be lost is data IN the rendered draft. Two checks together pin that:
    ///   1. `mutated`'s rendered draft, parsed and rendered AGAIN, is byte-stable
    ///      (parse∘render is idempotent — no field decays across a round trip).
    ///   2. `extract(reparsed) == extract(mutated)` — the specific field(s) the
    ///      user just typed survive verbatim (the actual data-loss defect).
    /// (Whole-IR equality would spuriously fail on DERIVED fields like inferred
    /// variables / `hasExplicitVariable`, which the live binding re-derives every
    /// read; those aren't user data and aren't what the defect was about.)
    @discardableResult
    private func edit<IR: Equatable, Field: Equatable>(
        _ draft: String,
        parse: (String) -> IR?,
        render: (IR) -> String,
        mutate: (inout IR) -> Void,
        survives extract: (IR) -> Field,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> String {
        guard var ir = parse(draft) else {
            Issue.record("\(label): expected the draft `\(draft)` to parse", sourceLocation: sourceLocation)
            return draft
        }
        mutate(&ir)
        let rendered = render(ir)
        guard let reparsed = parse(rendered) else {
            Issue.record(
                "\(label): rendered draft `\(rendered)` failed to re-parse",
                sourceLocation: sourceLocation)
            return rendered
        }
        // 1. The rendered draft is a stable fixed point (no decay on re-render).
        #expect(
            render(reparsed) == rendered,
            "\(label): `\(rendered)` is not a fixed point — it re-renders differently",
            sourceLocation: sourceLocation)
        // 2. The field the user just typed survived the round trip.
        #expect(
            extract(reparsed) == extract(ir),
            "\(label): the edited field was LOST in `\(rendered)`",
            sourceLocation: sourceLocation)
        return rendered
    }

    // MARK: - Integral (expr, then lower, then upper)

    @Test func integralFieldByField() {
        var draft = "integral x^2"
        draft = edit(draft, parse: IntegralFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.expression = "x^3" }, survives: \.expression, "integral expr")
        draft = edit(draft, parse: IntegralFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.lowerBound = "0" }, survives: \.lowerBound, "integral lower")
        // The defect repro: after the lower bound, the draft is `..., x=0..` —
        // re-parsing must keep `0`, not drop it.
        #expect(draft.contains("x=0.."))
        draft = edit(draft, parse: IntegralFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.upperBound = "1" }, survives: \.upperBound, "integral upper")
        #expect(draft == "integral x^3, x=0..1")
    }

    @Test func integralUpperBeforeLower() {
        // Filling the upper first leaves a `..hi` lower-less range; it must survive.
        var draft = "integral x^2"
        draft = edit(draft, parse: IntegralFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.upperBound = "1" }, survives: \.upperBound, "integral upper-first")
        #expect(draft.contains("..1"))
        draft = edit(draft, parse: IntegralFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.lowerBound = "0" }, survives: \.lowerBound, "integral lower-after")
        #expect(draft == "integral x^2, x=0..1")
    }

    // MARK: - Plot (expr, lower, upper)

    @Test func plotFieldByField() {
        var draft = "plot sin(x)"
        draft = edit(draft, parse: PlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.lowerBound = "-pi" }, survives: \.lowerBound, "plot lower")
        #expect(draft.contains("x=-pi.."))
        draft = edit(draft, parse: PlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.upperBound = "pi" }, survives: \.upperBound, "plot upper")
        #expect(draft == "plot sin(x), x=-pi..pi")
    }

    // MARK: - Sum (expr, index var, lower, upper)

    @Test func sumFieldByField() {
        var draft = "sum k^2"
        draft = edit(draft, parse: SeriesRangeFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.indexVariable = "k" }, survives: \.indexVariable, "sum var")
        draft = edit(draft, parse: SeriesRangeFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.lowerBound = "1" }, survives: \.lowerBound, "sum lower")
        #expect(draft.contains("k=1.."))
        draft = edit(draft, parse: SeriesRangeFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.upperBound = "n" }, survives: \.upperBound, "sum upper")
        #expect(draft == "sum k^2, k=1..n")
    }

    // MARK: - Parametric plot (pair pieces, then bounds)

    @Test func parametricPlotFieldByField() {
        var draft = "parametric_plot (cos(t), sin(t))"
        draft = edit(draft, parse: ParametricPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.lowerBound = "0" }, survives: \.lowerBound, "parametric lower")
        #expect(draft.contains("t=0.."))
        draft = edit(draft, parse: ParametricPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.upperBound = "2*pi" }, survives: \.upperBound, "parametric upper")
        #expect(draft == "parametric_plot (cos(t), sin(t)), t=0..2*pi")
    }

    // MARK: - Implicit plot (eq, then xLower, xUpper, yLower, yUpper one at a time)

    @Test func implicitPlotFieldByField() {
        var draft = "implicit_plot x^2 + y^2 = 1"
        draft = edit(draft, parse: ImplicitPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.xLower = "-2" }, survives: \.xLower, "implicit xLower")
        draft = edit(draft, parse: ImplicitPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.xUpper = "2" }, survives: \.xUpper, "implicit xUpper")
        draft = edit(draft, parse: ImplicitPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.yLower = "-2" }, survives: \.yLower, "implicit yLower")
        draft = edit(draft, parse: ImplicitPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.yUpper = "2" }, survives: \.yUpper, "implicit yUpper")
        #expect(draft == "implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2")
    }

    @Test func implicitPlotYBeforeX() {
        // Filling y first must NOT collapse the x clause: the equation keeps its
        // `= 1` and the partially-typed x range round-trips.
        var draft = "implicit_plot x^2 + y^2 = 1"
        draft = edit(draft, parse: ImplicitPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.yLower = "-2"; $0.yUpper = "2" }, survives: \.yLower, "implicit y-first")
        #expect(draft == "implicit_plot x^2 + y^2 = 1, x=.., y=-2..2")
        draft = edit(draft, parse: ImplicitPlotFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.xLower = "-2"; $0.xUpper = "2" }, survives: \.xLower, "implicit x-after")
        #expect(draft == "implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2")
    }

    // MARK: - Taylor (expr, var, center, order)

    @Test func taylorFieldByField() {
        var draft = "taylor sin(x)"
        draft = edit(draft, parse: TaylorFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.variable = "x" }, survives: \.variable, "taylor var")
        draft = edit(draft, parse: TaylorFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.center = "0" }, survives: \.center, "taylor center")
        draft = edit(draft, parse: TaylorFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.order = "7" }, survives: \.order, "taylor order")
        #expect(draft == "taylor sin(x), x=0, order=7")
    }

    @Test func taylorEmptyCenterSurvives() {
        // `taylor sin(x), x=` (var typed, center still empty) must round-trip.
        var draft = "taylor sin(x)"
        draft = edit(draft, parse: TaylorFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.variable = "x" }, survives: \.variable, "taylor var-only")
        #expect(draft == "taylor sin(x), x=")
    }

    // MARK: - Limit (expr, var, point, direction)

    @Test func limitFieldByField() {
        var draft = "limit sin(x)/x"
        draft = edit(draft, parse: LimitFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.variable = "x" }, survives: \.variable, "limit var")
        // The defect's limit analogue: `limit expr, x->` must keep the variable.
        #expect(draft == "limit sin(x)/x, x->")
        draft = edit(draft, parse: LimitFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.point = "0" }, survives: \.point, "limit point")
        draft = edit(draft, parse: LimitFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.direction = .right }, survives: \.direction, "limit direction")
        #expect(draft == "limit sin(x)/x, x->0, right")
    }

    // MARK: - Derivative (expr, order, var)

    @Test func derivativeFieldByField() {
        var draft = "derivative sin(x^2)"
        draft = edit(draft, parse: DerivativeFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.order = "2" }, survives: \.order, "derivative order")
        #expect(draft.contains(", 2"))
        draft = edit(draft, parse: DerivativeFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.variable = "x"; $0.hasExplicitVariable = true },
                     survives: \.variable, "derivative var")
        #expect(draft == "derivative sin(x^2), 2 wrt x")
    }

    // MARK: - Subs (expr, then bindings)

    @Test func subsFieldByField() {
        var draft = "subs x^2 + y"
        draft = edit(draft, parse: SubsFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.bindings = "x=3" }, survives: \.bindings, "subs bindings")
        #expect(draft == "subs x^2 + y, x=3")
        draft = edit(draft, parse: SubsFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.bindings = "x=3, y=4" }, survives: \.bindings, "subs bindings grow")
        #expect(draft == "subs x^2 + y, x=3, y=4")
    }

    // MARK: - Numeric (expr, then digits)

    @Test func numericFieldByField() {
        var draft = "numeric pi"
        draft = edit(draft, parse: NumericFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.digits = "50" }, survives: \.digits, "numeric digits")
        #expect(draft == "numeric pi, 50")
    }

    // MARK: - Statistics (positional holes, named parameters)

    @Test func statsNamedFieldByField() {
        var draft = "binomial_cdf 3"
        draft = edit(draft, parse: StatsFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.named["n"] = "10" }, survives: { $0.named["n"] }, "stats n")
        #expect(draft == "binomial_cdf 3, n=10")
        draft = edit(draft, parse: StatsFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.named["p"] = ".5" }, survives: { $0.named["p"] }, "stats p")
        #expect(draft == "binomial_cdf 3, n=10, p=.5")
    }

    @Test func statsUpperBeforeLower() {
        var draft = "normal_between"
        draft = edit(draft, parse: StatsFormulaIR.parse, render: \.friendlyInput,
                     mutate: {
                         $0.positional = ["", "1"]
                     },
                     survives: \.positional,
                     "stats upper-first")
        #expect(draft == "normal_between , 1")
        draft = edit(draft, parse: StatsFormulaIR.parse, render: \.friendlyInput,
                     mutate: { $0.positional[0] = "-1" },
                     survives: \.positional,
                     "stats lower-after")
        #expect(draft == "normal_between -1, 1")
    }
}
