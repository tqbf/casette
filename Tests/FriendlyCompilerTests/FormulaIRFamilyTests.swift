import Testing
@testable import FriendlyCompiler

// Batch A completion-UI IRs: the single-expression `unary` family
// (expand/factor/simplify), the `solve` family, and `FormulaIR` dispatch.
// These IRs render back to FRIENDLY INPUT, never Sage, and preserve `#ROW`
// tape references verbatim (docs/COMPLETION-UI.md).

@Suite("Unary formula IR")
struct UnaryFormulaIRTests {
    @Test func parsesEachKeyword() {
        #expect(UnaryFormulaIR.parse("expand (x+1)^3")
            == UnaryFormulaIR(keyword: .expand, expression: "(x+1)^3"))
        #expect(UnaryFormulaIR.parse("factor x^2 - 1")
            == UnaryFormulaIR(keyword: .factor, expression: "x^2 - 1"))
        #expect(UnaryFormulaIR.parse("simplify sin(x)^2 + cos(x)^2")
            == UnaryFormulaIR(keyword: .simplify, expression: "sin(x)^2 + cos(x)^2"))
    }

    @Test func parsesBareKeyword() {
        #expect(UnaryFormulaIR.parse("expand")
            == UnaryFormulaIR(keyword: .expand, expression: ""))
        #expect(UnaryFormulaIR.parse("expand")?.friendlyInput == "expand")
    }

    @Test func rejectsNonUnaryAndRawSage() {
        #expect(UnaryFormulaIR.parse("solve x^2 = 1") == nil)
        #expect(UnaryFormulaIR.parse("integral x^2") == nil)
        #expect(UnaryFormulaIR.parse("factorial(5)") == nil)
        #expect(UnaryFormulaIR.parse("2+2") == nil)
    }

    @Test func roundTripStability() {
        guard var ir = UnaryFormulaIR.parse("factor x^2 - 1") else {
            Issue.record("expected parse")
            return
        }
        ir.expression = "x^4 - 1"
        let rendered = ir.friendlyInput
        #expect(rendered == "factor x^4 - 1")
        #expect(UnaryFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = UnaryFormulaIR.parse("expand #14 + x^2") else {
            Issue.record("expected parse")
            return
        }
        #expect(ir.expression == "#14 + x^2")
        #expect(ir.friendlyInput == "expand #14 + x^2")
        #expect(UnaryFormulaIR.parse(ir.friendlyInput) == ir)
    }
}

@Suite("Solve formula IR")
struct SolveFormulaIRTests {
    @Test func parsesEquationInferringVariable() {
        guard let ir = SolveFormulaIR.parse("solve x^2 - 1 = 0") else {
            Issue.record("expected parse")
            return
        }
        #expect(ir.equation == "x^2 - 1 = 0")
        #expect(ir.variable == "x")
        #expect(ir.hasExplicitVariable == false)
        #expect(ir.friendlyInput == "solve x^2 - 1 = 0")
    }

    @Test func parsesForClause() {
        guard let ir = SolveFormulaIR.parse("solve x*y = 1 for x") else {
            Issue.record("expected parse")
            return
        }
        #expect(ir.equation == "x*y = 1")
        #expect(ir.variable == "x")
        #expect(ir.hasExplicitVariable == true)
        #expect(ir.friendlyInput == "solve x*y = 1 for x")
    }

    @Test func keepsEquationVerbatim() {
        // The equation token is NOT split on '='.
        guard let ir = SolveFormulaIR.parse("solve x^2 - 1 = 0") else {
            Issue.record("expected parse")
            return
        }
        #expect(ir.equation == "x^2 - 1 = 0")
    }

    @Test func preservesTapeReference() {
        guard let ir = SolveFormulaIR.parse("solve #14 + x = 0") else {
            Issue.record("expected parse")
            return
        }
        #expect(ir.equation == "#14 + x = 0")
        #expect(ir.friendlyInput == "solve #14 + x = 0")
    }

    @Test func roundTripStability() {
        guard var ir = SolveFormulaIR.parse("solve x^2 - 1 = 0") else {
            Issue.record("expected parse")
            return
        }
        ir.variable = "x"
        ir.hasExplicitVariable = true
        let rendered = ir.friendlyInput
        #expect(rendered == "solve x^2 - 1 = 0 for x")
        #expect(SolveFormulaIR.parse(rendered) == ir)
    }

    @Test func rejectsNonSolve() {
        #expect(SolveFormulaIR.parse("factor x^2 - 1") == nil)
        #expect(SolveFormulaIR.parse("2+2") == nil)
    }
}

@Suite("FormulaIR dispatch")
struct FormulaIRDispatchTests {
    @Test func dispatchesToTheRightCase() {
        guard case .integral = FormulaIR.parse("integral x^2") else {
            Issue.record("expected .integral"); return
        }
        guard case let .unary(u) = FormulaIR.parse("factor x^2 - 1"), u.keyword == .factor else {
            Issue.record("expected .unary(factor)"); return
        }
        guard case let .unary(e) = FormulaIR.parse("expand (x+1)^3"), e.keyword == .expand else {
            Issue.record("expected .unary(expand)"); return
        }
        guard case let .unary(s) = FormulaIR.parse("simplify sin(x)"), s.keyword == .simplify else {
            Issue.record("expected .unary(simplify)"); return
        }
        guard case .solve = FormulaIR.parse("solve x^2 = 1") else {
            Issue.record("expected .solve"); return
        }
    }

    @Test func returnsNilForRawSage() {
        #expect(FormulaIR.parse("2+2") == nil)
        #expect(FormulaIR.parse("factorial(5)") == nil)
    }
}
