import Testing
@testable import FriendlyCompiler

// Batch E lowerings: vector calculus (`gradient`, `hessian`, `jacobian`) plus
// the misc forms `subs`, `numeric`, and `latex`. These assertions are additive
// — the frozen V0.7 contract stays byte-identical.

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

private func expectBypass(_ input: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let r = FriendlyCompiler.compile(input)
    guard case .bypass = r else {
        Issue.record("expected .bypass for \(input), got \(r)", sourceLocation: sourceLocation)
        return
    }
}

@Suite("Gradient lowering (Batch E)")
struct GradientLowering {
    @Test func bareForm() {
        expectSuccess("gradient x^2 + y^2", "(x^2 + y^2).gradient()")
        #expect(requiredVars("gradient x^2 + y^2") == ["x", "y"])
    }

    @Test func withVariableList() {
        expectSuccess("gradient x^2 + y^2, [x,y]", "(x^2 + y^2).gradient([x, y])")
        #expect(requiredVars("gradient x^2 + y^2, [x,y]") == ["x", "y"])
    }

    @Test func gradAlias() {
        expectSuccess("grad x^2 + y^2", "(x^2 + y^2).gradient()")
        expectSuccess("grad x^2 + y^2, [x,y]", "(x^2 + y^2).gradient([x, y])")
    }

    @Test func variableListMustBeBracketed() {
        let e = expectError("gradient x^2 + y^2, x, y")
        #expect(e?.message.contains("bracketed") == true)
    }

    @Test func variableListRejectsNonVariableEntry() {
        let e = expectError("gradient x^2 + y^2, [x, 3]")
        #expect(e?.message.contains("bracketed") == true)
    }

    @Test func emptyErrors() {
        let e = expectError("gradient")
        #expect(e?.suggestion?.contains("gradient") == true)
    }

    @Test func callSyntaxBypasses() {
        expectBypass("gradient(x^2)")
    }
}

@Suite("Hessian lowering (Batch E)")
struct HessianLowering {
    @Test func bareForm() {
        expectSuccess("hessian x^2 + y^2", "(x^2 + y^2).hessian()")
        #expect(requiredVars("hessian x^2 + y^2") == ["x", "y"])
    }

    @Test func secondClauseErrors() {
        let e = expectError("hessian x^2 + y^2, [x,y]")
        #expect(e?.message.contains("just an expression") == true)
    }

    @Test func emptyErrors() {
        let e = expectError("hessian")
        #expect(e?.suggestion?.contains("hessian") == true)
    }

    @Test func callSyntaxBypasses() {
        expectBypass("hessian(x^2)")
    }
}

@Suite("Jacobian lowering (Batch E)")
struct JacobianLowering {
    @Test func happyPath() {
        expectSuccess(
            "jacobian [x^2+y, sin(x*y)], [x,y]",
            "jacobian([x^2+y, sin(x*y)], [x, y])")
    }

    @Test func reportsVarsAndFreeVariables() {
        // Bound vars first (x, y), then any remaining free symbols.
        let vars = requiredVars("jacobian [a*x, b*y], [x,y]")
        #expect(vars?.prefix(2) == ["x", "y"])
        #expect(vars?.contains("a") == true)
        #expect(vars?.contains("b") == true)
    }

    @Test func missingVariableListErrors() {
        let e = expectError("jacobian [x^2+y, sin(x*y)]")
        #expect(e?.suggestion?.contains("jacobian") == true)
    }

    @Test func missingFunctionsListErrors() {
        let e = expectError("jacobian x^2+y, [x,y]")
        #expect(e?.message.contains("bracketed") == true)
    }

    @Test func variableListMustBeBracketed() {
        let e = expectError("jacobian [x^2+y, sin(x*y)], x, y")
        #expect(e?.message.contains("bracketed") == true)
    }

    @Test func emptyErrors() {
        let e = expectError("jacobian")
        #expect(e?.suggestion?.contains("jacobian") == true)
    }

    @Test func callSyntaxBypasses() {
        expectBypass("jacobian([x], [x])")
    }
}

@Suite("Subs lowering (Batch E)")
struct SubsLowering {
    @Test func singleBinding() {
        expectSuccess("subs x^2 + y, x=3", "(x^2 + y).subs(x=3)")
    }

    @Test func multipleBindings() {
        expectSuccess("subs x^2 + y, x=3, y=4", "(x^2 + y).subs(x=3, y=4)")
    }

    @Test func substituteAlias() {
        expectSuccess("substitute x^2 + y, x=3", "(x^2 + y).subs(x=3)")
    }

    @Test func reportsBindingVarsAndFreeVariables() {
        // The binding var names plus the expression's free vars (x, y).
        #expect(requiredVars("subs x^2 + y, x=3") == ["x", "y"])
    }

    @Test func reportsValueFreeVariables() {
        // A value with its own free variable is reported too.
        let vars = requiredVars("subs x^2 + y, x=a")
        #expect(vars?.contains("x") == true)
        #expect(vars?.contains("y") == true)
        #expect(vars?.contains("a") == true)
    }

    @Test func missingBindingErrors() {
        let e = expectError("subs x^2 + y")
        #expect(e?.suggestion?.contains("subs x^2 + y, x=3") == true)
    }

    @Test func malformedBindingErrors() {
        let e = expectError("subs x^2 + y, 3")
        #expect(e?.message.contains("var=value") == true)
    }

    @Test func rangeBindingErrors() {
        // A `..` value is not a binding.
        let e = expectError("subs x^2 + y, x=0..1")
        #expect(e?.message.contains("var=value") == true)
    }

    @Test func callSyntaxBypasses() {
        // `subs(...)` has no trailing space after `subs`, so it bypasses.
        expectBypass("subs(x=3)")
    }
}

@Suite("Numeric lowering (Batch E)")
struct NumericLowering {
    @Test func bareForm() {
        expectSuccess("numeric pi", "N(pi)")
    }

    @Test func withDigits() {
        expectSuccess("numeric pi, 50", "N(pi, digits=50)")
    }

    @Test func approxAlias() {
        expectSuccess("approx pi", "N(pi)")
        expectSuccess("approx pi, 50", "N(pi, digits=50)")
    }

    @Test func decimalAlias() {
        expectSuccess("decimal pi", "N(pi)")
    }

    @Test func reportsFreeVariables() {
        #expect(requiredVars("numeric x + 1") == ["x"])
    }

    @Test func nonDigitSecondClauseErrors() {
        let e = expectError("numeric pi, fifty")
        #expect(e?.message.contains("whole number") == true)
    }

    @Test func emptyErrors() {
        let e = expectError("numeric")
        #expect(e?.suggestion?.contains("numeric") == true)
    }
}

@Suite("Latex lowering (Batch E)")
struct LatexLowering {
    @Test func happyPath() {
        expectSuccess("latex x^2/2", "latex(x^2/2)")
    }

    @Test func wrapsCallExpression() {
        expectSuccess("latex integral(sin(x), x)", "latex(integral(sin(x), x))")
    }

    @Test func reportsFreeVariables() {
        #expect(requiredVars("latex x^2/2") == ["x"])
    }

    @Test func callSyntaxBypasses() {
        expectBypass("latex(x^2)")
    }
}
