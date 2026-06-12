import Testing
@testable import FriendlyCompiler

// Batch C completion-UI IRs: plot, implicit_plot, and parametric_plot. Like the
// earlier batches, these IRs render back to FRIENDLY INPUT, never Sage, and
// preserve `#ROW` tape references verbatim (docs/COMPLETION-UI.md).

@Suite("Plot formula IR")
struct PlotFormulaIRTests {
    @Test func parsesWithRange() {
        guard let ir = PlotFormulaIR.parse("plot sin(x), x=-pi..pi") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "sin(x)")
        #expect(ir.variable == "x")
        #expect(ir.lowerBound == "-pi")
        #expect(ir.upperBound == "pi")
        #expect(ir.friendlyInput == "plot sin(x), x=-pi..pi")
    }

    @Test func tolerantNoRange() {
        guard let ir = PlotFormulaIR.parse("plot sin(x)") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "sin(x)")
        #expect(ir.variable == "x")  // inferred, single free var
        #expect(ir.lowerBound == nil)
        #expect(ir.upperBound == nil)
        #expect(ir.friendlyInput == "plot sin(x)")
    }

    @Test func defaultsVariableToXWhenBoundsSet() {
        var ir = PlotFormulaIR(expression: "f")
        ir.lowerBound = "0"
        ir.upperBound = "1"
        #expect(ir.friendlyInput == "plot f, x=0..1")
    }

    @Test func roundTripStability() {
        guard var ir = PlotFormulaIR.parse("plot sin(x), x=-pi..pi") else {
            Issue.record("expected parse"); return
        }
        ir.upperBound = "2*pi"
        let rendered = ir.friendlyInput
        #expect(rendered == "plot sin(x), x=-pi..2*pi")
        #expect(PlotFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = PlotFormulaIR.parse("plot #14, x=0..1") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#14")
        #expect(ir.friendlyInput == "plot #14, x=0..1")
        #expect(PlotFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonPlot() {
        #expect(PlotFormulaIR.parse("integral x^2") == nil)
        #expect(PlotFormulaIR.parse("2+2") == nil)
    }
}

@Suite("Implicit-plot formula IR")
struct ImplicitPlotFormulaIRTests {
    @Test func parsesFullGrammar() {
        guard let ir = ImplicitPlotFormulaIR.parse("implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.equation == "x^2 + y^2 = 1")
        #expect(ir.xVariable == "x")
        #expect(ir.xLower == "-2")
        #expect(ir.xUpper == "2")
        #expect(ir.yVariable == "y")
        #expect(ir.yLower == "-2")
        #expect(ir.yUpper == "2")
        #expect(ir.friendlyInput == "implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2")
    }

    @Test func tolerantNoRanges() {
        guard let ir = ImplicitPlotFormulaIR.parse("implicit_plot x^2 + y^2 = 1") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.equation == "x^2 + y^2 = 1")
        #expect(ir.xLower == nil)
        #expect(ir.yLower == nil)
        #expect(ir.friendlyInput == "implicit_plot x^2 + y^2 = 1")
    }

    @Test func renderingBothGroupsWhenOnlyYSet() {
        // Clause positions matter: a y-group with content still renders the
        // x-group (with empty bounds) so y stays the second clause.
        var ir = ImplicitPlotFormulaIR(equation: "x^2 + y^2 = 1")
        ir.yLower = "-2"
        ir.yUpper = "2"
        #expect(ir.friendlyInput == "implicit_plot x^2 + y^2 = 1, x=.., y=-2..2")
    }

    @Test func twoWordTriggerParses() {
        guard let underscore = ImplicitPlotFormulaIR.parse("implicit_plot x^2 = 1, x=-2..2, y=-2..2") else {
            Issue.record("expected parse for implicit_plot"); return
        }
        #expect(underscore.equation == "x^2 = 1")
        guard let spaced = ImplicitPlotFormulaIR.parse("implicit plot x^2 = 1, x=-2..2, y=-2..2") else {
            Issue.record("expected parse for 'implicit plot'"); return
        }
        #expect(spaced.equation == "x^2 = 1")
    }

    @Test func roundTripStability() {
        guard var ir = ImplicitPlotFormulaIR.parse("implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2") else {
            Issue.record("expected parse"); return
        }
        ir.xUpper = "3"
        let rendered = ir.friendlyInput
        #expect(rendered == "implicit_plot x^2 + y^2 = 1, x=-2..3, y=-2..2")
        #expect(ImplicitPlotFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = ImplicitPlotFormulaIR.parse("implicit_plot #5 = 1, x=-2..2, y=-2..2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.equation == "#5 = 1")
        #expect(ir.friendlyInput == "implicit_plot #5 = 1, x=-2..2, y=-2..2")
        #expect(ImplicitPlotFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonImplicitPlot() {
        #expect(ImplicitPlotFormulaIR.parse("plot sin(x)") == nil)
        #expect(ImplicitPlotFormulaIR.parse("integral x^2") == nil)
    }
}

@Suite("Parametric-plot formula IR")
struct ParametricPlotFormulaIRTests {
    @Test func parsesFullGrammar() {
        guard let ir = ParametricPlotFormulaIR.parse("parametric_plot (cos(t), sin(t)), t=0..2*pi") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.xExpression == "cos(t)")
        #expect(ir.yExpression == "sin(t)")
        #expect(ir.variable == "t")
        #expect(ir.lowerBound == "0")
        #expect(ir.upperBound == "2*pi")
        #expect(ir.friendlyInput == "parametric_plot (cos(t), sin(t)), t=0..2*pi")
    }

    @Test func tolerantNoRange() {
        guard let ir = ParametricPlotFormulaIR.parse("parametric_plot (cos(t), sin(t))") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.xExpression == "cos(t)")
        #expect(ir.yExpression == "sin(t)")
        #expect(ir.lowerBound == nil)
        #expect(ir.friendlyInput == "parametric_plot (cos(t), sin(t))")
    }

    @Test func defaultsVariableToTWhenBoundsSet() {
        var ir = ParametricPlotFormulaIR(xExpression: "cos(u)", yExpression: "sin(u)")
        ir.lowerBound = "0"
        ir.upperBound = "1"
        #expect(ir.friendlyInput == "parametric_plot (cos(u), sin(u)), t=0..1")
    }

    @Test func twoWordTriggerParses() {
        guard let spaced = ParametricPlotFormulaIR.parse("parametric plot (cos(t), sin(t)), t=0..2*pi") else {
            Issue.record("expected parse for 'parametric plot'"); return
        }
        #expect(spaced.xExpression == "cos(t)")
    }

    @Test func roundTripStability() {
        guard var ir = ParametricPlotFormulaIR.parse("parametric_plot (cos(t), sin(t)), t=0..2*pi") else {
            Issue.record("expected parse"); return
        }
        ir.upperBound = "pi"
        let rendered = ir.friendlyInput
        #expect(rendered == "parametric_plot (cos(t), sin(t)), t=0..pi")
        #expect(ParametricPlotFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = ParametricPlotFormulaIR.parse("parametric_plot (#3, sin(t)), t=0..1") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.xExpression == "#3")
        #expect(ir.friendlyInput == "parametric_plot (#3, sin(t)), t=0..1")
        #expect(ParametricPlotFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonParametricPlot() {
        #expect(ParametricPlotFormulaIR.parse("plot sin(x)") == nil)
        #expect(ParametricPlotFormulaIR.parse("integral x^2") == nil)
    }
}

@Suite("FormulaIR dispatch (Batch C)")
struct FormulaIRDispatchBatchCTests {
    @Test func dispatchesToTheRightCase() {
        guard case .plot = FormulaIR.parse("plot sin(x), x=-pi..pi") else {
            Issue.record("expected .plot"); return
        }
        guard case .implicitPlot = FormulaIR.parse("implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2") else {
            Issue.record("expected .implicitPlot"); return
        }
        guard case .implicitPlot = FormulaIR.parse("implicit plot x^2 = 1, x=-2..2, y=-2..2") else {
            Issue.record("expected .implicitPlot for two-word phrase"); return
        }
        guard case .parametricPlot = FormulaIR.parse("parametric_plot (cos(t), sin(t)), t=0..2*pi") else {
            Issue.record("expected .parametricPlot"); return
        }
        guard case .parametricPlot = FormulaIR.parse("parametric plot (cos(t), sin(t)), t=0..2*pi") else {
            Issue.record("expected .parametricPlot for two-word phrase"); return
        }
    }
}
