import Testing
@testable import FriendlyCompiler

// Batch B completion-UI IRs: derivative, limit, taylor, and the sum/product
// `seriesRange` family. Like Batch A, these IRs render back to FRIENDLY INPUT,
// never Sage, and preserve `#ROW` tape references verbatim
// (docs/COMPLETION-UI.md).

@Suite("Derivative formula IR")
struct DerivativeFormulaIRTests {
    @Test func parsesInferringVariable() {
        guard let ir = DerivativeFormulaIR.parse("derivative sin(x^2)") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "sin(x^2)")
        #expect(ir.variable == "x")
        #expect(ir.order == nil)
        #expect(ir.hasExplicitVariable == false)
        #expect(ir.friendlyInput == "derivative sin(x^2)")
    }

    @Test func parsesOrderAndWrt() {
        guard let ir = DerivativeFormulaIR.parse("derivative x*y, 2 wrt y") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "x*y")
        #expect(ir.variable == "y")
        #expect(ir.order == "2")
        #expect(ir.hasExplicitVariable == true)
        #expect(ir.friendlyInput == "derivative x*y, 2 wrt y")
    }

    @Test func parsesOrderWithoutWrt() {
        guard let ir = DerivativeFormulaIR.parse("derivative sin(x), 2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "sin(x)")
        #expect(ir.order == "2")
        #expect(ir.friendlyInput == "derivative sin(x), 2")
    }

    @Test func roundTripStability() {
        guard var ir = DerivativeFormulaIR.parse("derivative sin(x)") else {
            Issue.record("expected parse"); return
        }
        ir.order = "3"
        ir.variable = "x"
        ir.hasExplicitVariable = true
        let rendered = ir.friendlyInput
        #expect(rendered == "derivative sin(x), 3 wrt x")
        #expect(DerivativeFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = DerivativeFormulaIR.parse("derivative #14, 2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#14")
        #expect(ir.order == "2")
        #expect(ir.friendlyInput == "derivative #14, 2")
        #expect(DerivativeFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonDerivative() {
        #expect(DerivativeFormulaIR.parse("integral x^2") == nil)
        #expect(DerivativeFormulaIR.parse("2+2") == nil)
    }
}

@Suite("Limit formula IR")
struct LimitFormulaIRTests {
    @Test func parsesApproach() {
        guard let ir = LimitFormulaIR.parse("limit sin(x)/x, x->0") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "sin(x)/x")
        #expect(ir.variable == "x")
        #expect(ir.point == "0")
        #expect(ir.direction == .both)
        #expect(ir.friendlyInput == "limit sin(x)/x, x->0")
    }

    @Test func parsesDirection() {
        guard let left = LimitFormulaIR.parse("limit sin(x)/x, x->0, left") else {
            Issue.record("expected parse"); return
        }
        #expect(left.direction == .left)
        #expect(left.friendlyInput == "limit sin(x)/x, x->0, left")

        guard let right = LimitFormulaIR.parse("limit f, x->0, right") else {
            Issue.record("expected parse"); return
        }
        #expect(right.direction == .right)
        #expect(right.friendlyInput == "limit f, x->0, right")
    }

    @Test func tolerantHalfTypedApproach() {
        guard let ir = LimitFormulaIR.parse("limit sin(x)/x") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "sin(x)/x")
        #expect(ir.variable.isEmpty)
        #expect(ir.point.isEmpty)
        #expect(ir.friendlyInput == "limit sin(x)/x")
    }

    @Test func roundTripStability() {
        guard var ir = LimitFormulaIR.parse("limit sin(x)/x, x->0") else {
            Issue.record("expected parse"); return
        }
        ir.direction = .right
        let rendered = ir.friendlyInput
        #expect(rendered == "limit sin(x)/x, x->0, right")
        #expect(LimitFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = LimitFormulaIR.parse("limit #7 / x, x->0") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#7 / x")
        #expect(ir.friendlyInput == "limit #7 / x, x->0")
        #expect(LimitFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonLimit() {
        #expect(LimitFormulaIR.parse("integral x^2") == nil)
        #expect(LimitFormulaIR.parse("2+2") == nil)
    }
}

@Suite("Taylor formula IR")
struct TaylorFormulaIRTests {
    @Test func parsesFullGrammar() {
        guard let ir = TaylorFormulaIR.parse("taylor sin(x), x=0, order=7") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "sin(x)")
        #expect(ir.variable == "x")
        #expect(ir.center == "0")
        #expect(ir.order == "7")
        #expect(ir.friendlyInput == "taylor sin(x), x=0, order=7")
    }

    @Test func tolerantPartialForms() {
        guard let exprOnly = TaylorFormulaIR.parse("taylor sin(x)") else {
            Issue.record("expected parse"); return
        }
        #expect(exprOnly.friendlyInput == "taylor sin(x)")

        guard let withCenter = TaylorFormulaIR.parse("taylor sin(x), x=0") else {
            Issue.record("expected parse"); return
        }
        #expect(withCenter.variable == "x")
        #expect(withCenter.center == "0")
        #expect(withCenter.friendlyInput == "taylor sin(x), x=0")
    }

    @Test func orderForcesVarClause() {
        // The order is always the third comma part, so a var=pt clause is kept
        // (even empty) to hold the position.
        var ir = TaylorFormulaIR(expression: "sin(x)", order: "5")
        #expect(ir.friendlyInput == "taylor sin(x), =, order=5")
        ir.variable = "x"
        ir.center = "0"
        #expect(ir.friendlyInput == "taylor sin(x), x=0, order=5")
    }

    @Test func roundTripStability() {
        guard var ir = TaylorFormulaIR.parse("taylor sin(x), x=0, order=7") else {
            Issue.record("expected parse"); return
        }
        ir.order = "5"
        let rendered = ir.friendlyInput
        #expect(rendered == "taylor sin(x), x=0, order=5")
        #expect(TaylorFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = TaylorFormulaIR.parse("taylor #9, x=0, order=4") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#9")
        #expect(ir.friendlyInput == "taylor #9, x=0, order=4")
        #expect(TaylorFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonTaylor() {
        #expect(TaylorFormulaIR.parse("integral x^2") == nil)
    }
}

@Suite("Series-range formula IR")
struct SeriesRangeFormulaIRTests {
    @Test func parsesSumAndProduct() {
        guard let sum = SeriesRangeFormulaIR.parse("sum k^2, k=1..n") else {
            Issue.record("expected parse"); return
        }
        #expect(sum.kind == .sum)
        #expect(sum.expression == "k^2")
        #expect(sum.indexVariable == "k")
        #expect(sum.lowerBound == "1")
        #expect(sum.upperBound == "n")
        #expect(sum.friendlyInput == "sum k^2, k=1..n")

        guard let product = SeriesRangeFormulaIR.parse("product 1 + 1/k, k=1..n") else {
            Issue.record("expected parse"); return
        }
        #expect(product.kind == .product)
        #expect(product.friendlyInput == "product 1 + 1/k, k=1..n")
    }

    @Test func tolerantMissingRange() {
        guard let ir = SeriesRangeFormulaIR.parse("sum k^2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "k^2")
        #expect(ir.indexVariable.isEmpty)
        #expect(ir.lowerBound.isEmpty)
        #expect(ir.friendlyInput == "sum k^2")
    }

    @Test func defaultsIndexToK() {
        var ir = SeriesRangeFormulaIR(kind: .sum, expression: "j")
        ir.lowerBound = "1"
        ir.upperBound = "10"
        #expect(ir.friendlyInput == "sum j, k=1..10")
    }

    @Test func roundTripStability() {
        guard var ir = SeriesRangeFormulaIR.parse("sum k^2, k=1..n") else {
            Issue.record("expected parse"); return
        }
        ir.upperBound = "100"
        let rendered = ir.friendlyInput
        #expect(rendered == "sum k^2, k=1..100")
        #expect(SeriesRangeFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = SeriesRangeFormulaIR.parse("sum #3 * k, k=1..10") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#3 * k")
        #expect(ir.friendlyInput == "sum #3 * k, k=1..10")
        #expect(SeriesRangeFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonSeries() {
        #expect(SeriesRangeFormulaIR.parse("integral x^2") == nil)
        #expect(SeriesRangeFormulaIR.parse("2+2") == nil)
    }
}

@Suite("FormulaIR dispatch (Batch B)")
struct FormulaIRDispatchBatchBTests {
    @Test func dispatchesToTheRightCase() {
        guard case .derivative = FormulaIR.parse("derivative sin(x)") else {
            Issue.record("expected .derivative"); return
        }
        guard case .limit = FormulaIR.parse("limit sin(x)/x, x->0") else {
            Issue.record("expected .limit"); return
        }
        guard case .taylor = FormulaIR.parse("taylor sin(x), x=0, order=7") else {
            Issue.record("expected .taylor"); return
        }
        guard case let .seriesRange(s) = FormulaIR.parse("sum k^2, k=1..n"), s.kind == .sum else {
            Issue.record("expected .seriesRange(sum)"); return
        }
        guard case let .seriesRange(p) = FormulaIR.parse("product k, k=1..n"), p.kind == .product else {
            Issue.record("expected .seriesRange(product)"); return
        }
    }
}
