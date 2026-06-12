import Testing
@testable import FriendlyCompiler

// Batch C lowerings: the new `implicit_plot` and `parametric_plot` keyword
// forms, plus the existing `plot` no-range behavior (the default-range
// extension was SKIPPED — the frozen `plotNoRange` test asserts `plot sin(x)`
// errors, so defaulting it would weaken a frozen assertion). These assertions
// are additive — they never touch the frozen V0.7 contract.

private func expectSuccess(_ input: String, _ expectedSage: String,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    let r = FriendlyCompiler.compile(input)
    guard case let .success(s, _) = r else {
        Issue.record("expected .success for \(input), got \(r)", sourceLocation: sourceLocation)
        return
    }
    #expect(s == expectedSage, sourceLocation: sourceLocation)
}

private func requiredVars(_ input: String,
                          sourceLocation: SourceLocation = #_sourceLocation) -> [String]? {
    let r = FriendlyCompiler.compile(input)
    guard case let .success(_, vars) = r else {
        Issue.record("expected .success for \(input), got \(r)", sourceLocation: sourceLocation)
        return nil
    }
    return vars
}

private func expectError(_ input: String,
                         sourceLocation: SourceLocation = #_sourceLocation) -> CompileError? {
    let r = FriendlyCompiler.compile(input)
    guard case let .error(e) = r else {
        Issue.record("expected .error for \(input), got \(r)", sourceLocation: sourceLocation)
        return nil
    }
    return e
}

@Suite("Implicit-plot lowering")
struct ImplicitPlotLowering {
    @Test func singleEqualsTranslatesToDoubleEquals() {
        expectSuccess(
            "implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2",
            "implicit_plot(x^2 + y^2 == 1, (x, -2, 2), (y, -2, 2))")
    }

    @Test func doubleEqualsPassesThrough() {
        expectSuccess(
            "implicit_plot x^2 + y^2 == 1, x=-2..2, y=-2..2",
            "implicit_plot(x^2 + y^2 == 1, (x, -2, 2), (y, -2, 2))")
    }

    @Test func bareExpressionNormalizesToEqualsZero() {
        expectSuccess(
            "implicit_plot x^2 + y^2 - 1, x=-2..2, y=-2..2",
            "implicit_plot(x^2 + y^2 - 1 == 0, (x, -2, 2), (y, -2, 2))")
    }

    @Test func twoWordPhraseWorks() {
        expectSuccess(
            "implicit plot x^2 + y^2 = 1, x=-2..2, y=-2..2",
            "implicit_plot(x^2 + y^2 == 1, (x, -2, 2), (y, -2, 2))")
    }

    @Test func requiresTwoRanges() {
        let e = expectError("implicit_plot x^2 + y^2 = 1, x=-2..2")
        #expect(e?.message.contains("two ranges") == true)
    }

    @Test func reportsMalformedXRange() {
        let e = expectError("implicit_plot x^2 + y^2 = 1, x=-2, y=-2..2")
        #expect(e?.message.contains("..") == true)
    }

    @Test func reportsMalformedYRange() {
        let e = expectError("implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2")
        #expect(e?.message.contains("..") == true)
    }

    @Test func needsEquation() {
        let e = expectError("implicit_plot")
        #expect(e != nil)
    }

    @Test func requiredVariablesAreRangeVarsFirst() {
        // Both range variables come first, then any free symbols in the
        // equation/bounds (here, none beyond x and y).
        #expect(requiredVars("implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2") == ["x", "y"])
    }

    @Test func requiredVariablesIncludeFreeBoundSymbols() {
        // A free symbol `r` in the bounds is reported after the range vars.
        let vars = requiredVars("implicit_plot x^2 + y^2 = r, x=-r..r, y=-r..r")
        #expect(vars == ["x", "y", "r"])
    }

    @Test func preservesTapeReference() {
        expectSuccess(
            "implicit_plot #3 = 1, x=-2..2, y=-2..2",
            "implicit_plot(#3 == 1, (x, -2, 2), (y, -2, 2))")
    }
}

@Suite("Parametric-plot lowering")
struct ParametricPlotLowering {
    @Test func happyPath() {
        expectSuccess(
            "parametric_plot (cos(t), sin(t)), t=0..2*pi",
            "parametric_plot((cos(t), sin(t)), (t, 0, 2*pi))")
    }

    @Test func twoWordPhraseWorks() {
        expectSuccess(
            "parametric plot (cos(t), sin(t)), t=0..2*pi",
            "parametric_plot((cos(t), sin(t)), (t, 0, 2*pi))")
    }

    @Test func requiredVariablesAreRangeVarFirst() {
        #expect(requiredVars("parametric_plot (cos(t), sin(t)), t=0..2*pi") == ["t"])
    }

    @Test func requiredVariablesIncludeFreeBoundSymbols() {
        let vars = requiredVars("parametric_plot (a*cos(t), a*sin(t)), t=0..b")
        #expect(vars == ["t", "a", "b"])
    }

    @Test func rejectsMissingPair() {
        let e = expectError("parametric_plot cos(t), t=0..2*pi")
        #expect(e?.message.contains("coordinate pair") == true)
    }

    @Test func rejectsPairWithOneCoordinate() {
        let e = expectError("parametric_plot (cos(t)), t=0..2*pi")
        #expect(e?.message.contains("coordinate pair") == true)
    }

    @Test func rejectsPairWithThreeCoordinates() {
        let e = expectError("parametric_plot (cos(t), sin(t), t), t=0..2*pi")
        #expect(e?.message.contains("coordinate pair") == true)
    }

    @Test func requiresRange() {
        let e = expectError("parametric_plot (cos(t), sin(t))")
        #expect(e?.message.contains("one range") == true)
    }

    @Test func reportsMalformedRange() {
        let e = expectError("parametric_plot (cos(t), sin(t)), t=0")
        #expect(e?.message.contains("..") == true)
    }

    @Test func preservesTapeReference() {
        expectSuccess(
            "parametric_plot (#3, sin(t)), t=0..2*pi",
            "parametric_plot((#3, sin(t)), (t, 0, 2*pi))")
    }
}

@Suite("Plot no-range (default-range extension SKIPPED)")
struct PlotNoRangeBehavior {
    // The frozen `plotNoRange` test asserts `plot sin(x)` errors with a
    // plot-mentioning suggestion. Batch C keeps that contract: the default-range
    // extension was deliberately not shipped.
    @Test func singleVariableNoRangeStillErrors() {
        let e = expectError("plot sin(x)")
        #expect(e?.message.contains("range") == true)
        #expect(e?.suggestion?.contains("plot") == true)
    }

    @Test func withRangeUnchanged() {
        expectSuccess("plot sin(x), x=-pi..pi", "plot(sin(x), (x, -pi, pi))")
    }
}
