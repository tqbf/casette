import Testing
@testable import FriendlyCompiler

// Batch E completion-UI IRs: the vector-calculus family (gradient, hessian,
// jacobian), `subs`, `numeric`, and `latex` (which rides `UnaryFormulaIR`).
// Like the earlier batches, these IRs render back to FRIENDLY INPUT, never
// Sage, and preserve `#ROW` tape references verbatim (docs/COMPLETION-UI.md).

@Suite("Vector calculus formula IR")
struct VectorCalculusFormulaIRTests {
    @Test func parsesGradientBare() {
        guard let ir = VectorCalculusFormulaIR.parse("gradient x^2 + y^2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .gradient)
        #expect(ir.expression == "x^2 + y^2")
        #expect(ir.variables.isEmpty)
        #expect(ir.friendlyInput == "gradient x^2 + y^2")
    }

    @Test func parsesGradientWithVariableList() {
        guard let ir = VectorCalculusFormulaIR.parse("gradient x^2 + y^2, [x,y]") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .gradient)
        #expect(ir.expression == "x^2 + y^2")
        #expect(ir.variables == "[x,y]")
        #expect(ir.friendlyInput == "gradient x^2 + y^2, [x,y]")
    }

    @Test func parsesHessian() {
        guard let ir = VectorCalculusFormulaIR.parse("hessian x^2 + y^2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .hessian)
        #expect(ir.expression == "x^2 + y^2")
        #expect(ir.friendlyInput == "hessian x^2 + y^2")
    }

    @Test func hessianNeverRendersVariables() {
        // Even if a variables field is somehow set, hessian renders bare.
        var ir = VectorCalculusFormulaIR(kind: .hessian, expression: "x^2", variables: "[x]")
        #expect(ir.friendlyInput == "hessian x^2")
        ir.variables = ""
        #expect(ir.friendlyInput == "hessian x^2")
    }

    @Test func parsesJacobian() {
        guard let ir = VectorCalculusFormulaIR.parse("jacobian [x^2+y, sin(x*y)], [x,y]") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .jacobian)
        #expect(ir.expression == "[x^2+y, sin(x*y)]")
        #expect(ir.variables == "[x,y]")
        #expect(ir.friendlyInput == "jacobian [x^2+y, sin(x*y)], [x,y]")
    }

    @Test func gradAliasNormalizesToCanonicalCommand() {
        guard let ir = VectorCalculusFormulaIR.parse("grad x^2 + y^2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.kind == .gradient)
        #expect(ir.friendlyInput == "gradient x^2 + y^2")
    }

    @Test func parsesBareCommandWithEmptyExpression() {
        for (input, kind) in [
            ("gradient", VectorCalculusFormulaIR.Kind.gradient),
            ("hessian", .hessian),
            ("jacobian", .jacobian),
        ] {
            guard let ir = VectorCalculusFormulaIR.parse(input) else {
                Issue.record("expected parse for bare \(input)"); continue
            }
            #expect(ir.kind == kind)
            #expect(ir.expression.isEmpty)
            #expect(ir.friendlyInput == input)
        }
    }

    @Test func gradientRoundTripStability() {
        guard var ir = VectorCalculusFormulaIR.parse("gradient x^2 + y^2") else {
            Issue.record("expected parse"); return
        }
        ir.variables = "[x, y]"
        let rendered = ir.friendlyInput
        #expect(rendered == "gradient x^2 + y^2, [x, y]")
        #expect(VectorCalculusFormulaIR.parse(rendered) == ir)
    }

    @Test func jacobianRoundTripStability() {
        guard let ir = VectorCalculusFormulaIR.parse("jacobian [a, b], [x,y]") else {
            Issue.record("expected parse"); return
        }
        #expect(VectorCalculusFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = VectorCalculusFormulaIR.parse("gradient #14 + y^2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#14 + y^2")
        #expect(ir.friendlyInput == "gradient #14 + y^2")
        #expect(VectorCalculusFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonVectorCalculus() {
        #expect(VectorCalculusFormulaIR.parse("integral x^2") == nil)
        #expect(VectorCalculusFormulaIR.parse("2+2") == nil)
        #expect(VectorCalculusFormulaIR.parse("gradient(x^2)") == nil)
    }
}

@Suite("Subs formula IR")
struct SubsFormulaIRTests {
    @Test func parsesSingleBinding() {
        guard let ir = SubsFormulaIR.parse("subs x^2 + y, x=3") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "x^2 + y")
        #expect(ir.bindings == "x=3")
        #expect(ir.friendlyInput == "subs x^2 + y, x=3")
    }

    @Test func parsesMultipleBindingsAsOneGroup() {
        guard let ir = SubsFormulaIR.parse("subs x^2 + y, x=3, y=4") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "x^2 + y")
        #expect(ir.bindings == "x=3, y=4")
        #expect(ir.friendlyInput == "subs x^2 + y, x=3, y=4")
    }

    @Test func substituteAliasNormalizes() {
        guard let ir = SubsFormulaIR.parse("substitute x^2 + y, x=3") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.friendlyInput == "subs x^2 + y, x=3")
    }

    @Test func bareCommandOmitsBindingsClause() {
        guard let ir = SubsFormulaIR.parse("subs x^2 + y") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.bindings.isEmpty)
        #expect(ir.friendlyInput == "subs x^2 + y")
    }

    @Test func roundTripStability() {
        guard var ir = SubsFormulaIR.parse("subs x^2 + y") else {
            Issue.record("expected parse"); return
        }
        ir.bindings = "x=3, y=4"
        let rendered = ir.friendlyInput
        #expect(rendered == "subs x^2 + y, x=3, y=4")
        #expect(SubsFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = SubsFormulaIR.parse("subs #2, x=3") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#2")
        #expect(ir.bindings == "x=3")
        #expect(ir.friendlyInput == "subs #2, x=3")
        #expect(SubsFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonSubs() {
        #expect(SubsFormulaIR.parse("factor x^2") == nil)
        #expect(SubsFormulaIR.parse("subs(x=3)") == nil)
    }
}

@Suite("Numeric formula IR")
struct NumericFormulaIRTests {
    @Test func parsesBare() {
        guard let ir = NumericFormulaIR.parse("numeric pi") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "pi")
        #expect(ir.digits.isEmpty)
        #expect(ir.friendlyInput == "numeric pi")
    }

    @Test func parsesWithDigits() {
        guard let ir = NumericFormulaIR.parse("numeric pi, 50") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "pi")
        #expect(ir.digits == "50")
        #expect(ir.friendlyInput == "numeric pi, 50")
    }

    @Test func approxAliasNormalizes() {
        guard let ir = NumericFormulaIR.parse("approx pi") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.friendlyInput == "numeric pi")
    }

    @Test func roundTripStability() {
        guard var ir = NumericFormulaIR.parse("numeric pi") else {
            Issue.record("expected parse"); return
        }
        ir.digits = "50"
        let rendered = ir.friendlyInput
        #expect(rendered == "numeric pi, 50")
        #expect(NumericFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = NumericFormulaIR.parse("numeric #5, 20") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#5")
        #expect(ir.digits == "20")
        #expect(ir.friendlyInput == "numeric #5, 20")
        #expect(NumericFormulaIR.parse(ir.friendlyInput) == ir)
    }

    @Test func rejectsNonNumeric() {
        #expect(NumericFormulaIR.parse("factor x^2") == nil)
    }
}

@Suite("Latex rides UnaryFormulaIR")
struct LatexUnaryIRTests {
    @Test func parsesAsUnaryLatex() {
        guard let ir = UnaryFormulaIR.parse("latex x^2/2") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.keyword == .latex)
        #expect(ir.expression == "x^2/2")
        #expect(ir.friendlyInput == "latex x^2/2")
    }

    @Test func roundTripStability() {
        guard var ir = UnaryFormulaIR.parse("latex x^2/2") else {
            Issue.record("expected parse"); return
        }
        ir.expression = "integral(sin(x), x)"
        let rendered = ir.friendlyInput
        #expect(rendered == "latex integral(sin(x), x)")
        #expect(UnaryFormulaIR.parse(rendered) == ir)
    }

    @Test func preservesTapeReference() {
        guard let ir = UnaryFormulaIR.parse("latex #5") else {
            Issue.record("expected parse"); return
        }
        #expect(ir.expression == "#5")
        #expect(ir.friendlyInput == "latex #5")
        #expect(UnaryFormulaIR.parse(ir.friendlyInput) == ir)
    }
}

@Suite("FormulaIR dispatch (Batch E)")
struct FormulaIRDispatchBatchETests {
    @Test func dispatchesVectorCalculus() {
        for trigger in [
            "gradient x^2 + y^2",
            "grad x^2",
            "hessian x^2 + y^2",
            "jacobian [a, b], [x,y]",
        ] {
            guard case .vectorCalculus = FormulaIR.parse(trigger) else {
                Issue.record("expected .vectorCalculus for \(trigger)"); continue
            }
        }
    }

    @Test func dispatchesSubs() {
        guard case .subs = FormulaIR.parse("subs x^2 + y, x=3") else {
            Issue.record("expected .subs"); return
        }
        guard case .subs = FormulaIR.parse("substitute x^2, x=3") else {
            Issue.record("expected .subs for substitute"); return
        }
    }

    @Test func dispatchesNumeric() {
        guard case .numeric = FormulaIR.parse("numeric pi") else {
            Issue.record("expected .numeric"); return
        }
        guard case .numeric = FormulaIR.parse("approx pi, 50") else {
            Issue.record("expected .numeric for approx"); return
        }
    }

    @Test func latexDispatchesToUnary() {
        guard case let .unary(ir) = FormulaIR.parse("latex x^2/2"), ir.keyword == .latex else {
            Issue.record("expected .unary(latex)"); return
        }
    }

    @Test func bareCommandWordsDispatch() {
        guard case .vectorCalculus = FormulaIR.parse("gradient") else {
            Issue.record("expected .vectorCalculus for bare gradient"); return
        }
        guard case .subs = FormulaIR.parse("subs") else {
            Issue.record("expected .subs for bare subs"); return
        }
        guard case .numeric = FormulaIR.parse("numeric") else {
            Issue.record("expected .numeric for bare numeric"); return
        }
    }
}
