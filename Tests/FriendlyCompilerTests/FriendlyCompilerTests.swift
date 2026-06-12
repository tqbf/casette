import Testing
@testable import FriendlyCompiler

// V0.7 unit tests — every spec'd form, every error case, bypass cases, the
// double-integral nesting, and weird spacing. swift-testing.

// MARK: - Helpers

private func sage(_ input: String) -> String? {
    FriendlyCompiler.compile(input).sage
}

private func expectSuccess(_ input: String, _ expectedSage: String,
                           sourceLocation: SourceLocation = #_sourceLocation) {
    let r = FriendlyCompiler.compile(input)
    guard case let .success(s, _) = r else {
        Issue.record("expected .success for \(input), got \(r)", sourceLocation: sourceLocation)
        return
    }
    #expect(s == expectedSage, sourceLocation: sourceLocation)
}

private func expectBypass(_ input: String, sourceLocation: SourceLocation = #_sourceLocation) {
    let r = FriendlyCompiler.compile(input)
    guard case let .bypass(s) = r else {
        Issue.record("expected .bypass for \(input), got \(r)", sourceLocation: sourceLocation)
        return
    }
    #expect(s == input.trimmingCharacters(in: .whitespaces), sourceLocation: sourceLocation)
}

private func expectError(_ input: String, sourceLocation: SourceLocation = #_sourceLocation) -> CompileError? {
    let r = FriendlyCompiler.compile(input)
    guard case let .error(e) = r else {
        Issue.record("expected .error for \(input), got \(r)", sourceLocation: sourceLocation)
        return nil
    }
    return e
}

private func expectAmbiguous(_ input: String, sourceLocation: SourceLocation = #_sourceLocation) -> [String]? {
    let r = FriendlyCompiler.compile(input)
    guard case let .ambiguous(c) = r else {
        Issue.record("expected .ambiguous for \(input), got \(r)", sourceLocation: sourceLocation)
        return nil
    }
    return c
}

// MARK: - Spec forms (exact reference translations)

@Suite("Spec forms")
struct SpecForms {
    @Test func factor() { expectSuccess("factor x^4 - 1", "factor(x^4 - 1)") }
    @Test func expand() { expectSuccess("expand (x + 1)^5", "expand((x + 1)^5)") }
    @Test func simplify() { expectSuccess("simplify sin(x)^2 + cos(x)^2", "(sin(x)^2 + cos(x)^2).simplify_full()") }
    @Test func solveNoVar() { expectSuccess("solve x^2 + 5*x + 6 = 0", "solve(x^2 + 5*x + 6 == 0, x)") }
    @Test func solveForVar() { expectSuccess("solve x^2 + 5*x + 6 = 0 for x", "solve(x^2 + 5*x + 6 == 0, x)") }
    @Test func derivative() { expectSuccess("derivative sin(x^2)", "derivative(sin(x^2), x)") }
    @Test func derivativeWrt() { expectSuccess("derivative sin(x^2) wrt x", "derivative(sin(x^2), x)") }
    @Test func integralIndefinite() { expectSuccess("integral x^2", "integrate(x^2, x)") }
    @Test func integralDefinite() { expectSuccess("integral x^2, x=0..1", "integrate(x^2, (x, 0, 1))") }
    @Test func doubleIntegral() {
        expectSuccess("double integral x*y, x=0..1, y=0..x",
                      "integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))")
    }
    @Test func limit() { expectSuccess("limit sin(x)/x, x->0", "limit(sin(x)/x, x=0)") }
    @Test func taylor() { expectSuccess("taylor sin(x), x=0, order=7", "taylor(sin(x), x, 0, 7)") }
    @Test func plot() { expectSuccess("plot sin(x), x=-pi..pi", "plot(sin(x), (x, -pi, pi))") }
    @Test func matrix() { expectSuccess("matrix [[1,2],[3,4]]", "matrix([[1,2],[3,4]])") }
    @Test func matlabMatrix() {
        expectSuccess("matrix [1, 2, 3 ; 2, 3, 4 ]", "matrix([[1,2,3],[2,3,4]])")
    }
    @Test func matlabMatrixStandalone() {
        expectSuccess("[1, 2, 3 ; 2, 3, 4 ]", "matrix([[1,2,3],[2,3,4]])")
    }
    @Test func matlabMatrixAssignment() {
        expectSuccess("A = [1, 2, 3 ; 2, 3, 4 ]", "A = matrix([[1,2,3],[2,3,4]])\nA")
    }
    @Test func eigenvalues() { expectSuccess("eigenvalues [[1,2],[3,4]]", "matrix([[1,2],[3,4]]).eigenvalues()") }
    @Test func eigenvaluesMatlabMatrix() {
        expectSuccess("eigenvalues [1,2;3,4]", "matrix([[1,2],[3,4]]).eigenvalues()")
    }
    @Test func rref() { expectSuccess("rref [[1,2],[3,4]]", "matrix([[1,2],[3,4]]).rref()") }
    @Test func rrefMatlabMatrix() {
        expectSuccess("rref [1,2,3;4,5,6]", "matrix([[1,2,3],[4,5,6]]).rref()")
    }
}

// MARK: - The double-integral nesting (load-bearing)

@Suite("Double integral nesting")
struct DoubleIntegralNesting {
    @Test func innerBindsLastRange() {
        // Inner integral binds y (the LAST range), outer binds x (the first).
        expectSuccess("double integral x*y, x=0..1, y=0..x",
                      "integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))")
    }
    @Test func constantBounds() {
        expectSuccess("double integral 1, x=0..2, y=0..3",
                      "integrate(integrate(1, (y, 0, 3)), (x, 0, 2))")
    }
    @Test func requiredVariablesOrderOuterThenInner() {
        let r = FriendlyCompiler.compile("double integral x*y, x=0..1, y=0..x")
        guard case let .success(_, vars) = r else { Issue.record("not success"); return }
        #expect(vars == ["x", "y"])
    }
    @Test func needsTwoRanges() {
        #expect(expectError("double integral x*y, x=0..1") != nil)
    }
}

// MARK: - Bypass (raw Sage passes through untouched)

@Suite("Raw Sage bypass")
struct Bypass {
    @Test func arithmetic() { expectBypass("2+2") }
    @Test func alreadyCallSyntax() { expectBypass("factor(x^4-1)") }
    @Test func assignmentEchoesAssignedVariable() {
        expectSuccess("A = matrix([[1,2],[3,4]])", "A = matrix([[1,2],[3,4]])\nA")
    }
    @Test func listAssignmentEchoesAssignedVariable() {
        expectSuccess("A = [1, 2, 3]", "A = [1, 2, 3]\nA")
    }
    @Test func bareExpression() { expectBypass("sin(pi/3)") }
    // `factorial` starts with `factor` but is NOT the command (no space after).
    @Test func factorialNotFactor() { expectBypass("factorial(5)") }
    @Test func methodCall() { expectBypass("x.diff()") }
    @Test func unknownLeadingWord() { expectBypass("foobar x^2") }
    @Test func empty() {
        if case let .bypass(s) = FriendlyCompiler.compile("") { #expect(s == "") }
        else { Issue.record("empty should bypass") }
    }
    @Test func integerLiteral() { expectBypass("104729") }
    // `plotting` would bypass (no space boundary). Spelled-out word check:
    @Test func plottingNotPlot() { expectBypass("plotting_helper(3)") }
}

// MARK: - Errors (useful, position-bearing)

@Suite("Useful errors")
struct Errors {
    @Test func incompleteRange() {
        let e = expectError("integral x^2, x=0..")
        #expect(e?.message.contains("incomplete") == true)
        #expect(e?.suggestion != nil)
    }
    @Test func rangeMissingDotDot() {
        let e = expectError("plot sin(x), x=0")
        #expect(e?.message.contains("..") == true)
    }
    @Test func solveWithoutEquals() {
        let e = expectError("solve x^2 + 1")
        #expect(e?.message.contains("equation") == true)
    }
    @Test func bareCommandNoArg() {
        let e = expectError("factor")
        #expect(e?.message.contains("expression") == true)
    }
    @Test func plotNoRange() {
        let e = expectError("plot sin(x)")
        #expect(e?.suggestion?.contains("plot") == true)
    }
    @Test func matrixNotBracketed() {
        #expect(expectError("matrix (1,2)") != nil)
    }
    @Test func matlabMatrixRejectsEmptyRow() {
        #expect(expectError("matrix [1,2; ]") != nil)
    }
    @Test func matlabMatrixRejectsEmptyCell() {
        #expect(expectError("matrix [1,,2; 3,4,5]") != nil)
    }
    @Test func matlabMatrixAssignmentRejectsEmptyCell() {
        #expect(expectError("A = [1,,2; 3,4,5]") != nil)
    }
    @Test func unbalancedParen() {
        let e = expectError("expand (x+1")
        #expect(e?.message.contains("never closed") == true)
        #expect(e?.position != nil)
    }
    @Test func unbalancedBracket() {
        let e = expectError("matrix [[1,2],[3,4]")
        #expect(e?.message.contains("never closed") == true)
    }
    @Test func mismatchedBracket() {
        let e = expectError("factor (x^4 - 1]")
        #expect(e?.message.contains("mismatch") == true)
    }
    @Test func unexpectedClose() {
        let e = expectError("factor x^4 - 1)")
        #expect(e?.message.contains("no matching opener") == true)
    }
    @Test func taylorMissingOrder() {
        #expect(expectError("taylor sin(x), x=0") != nil)
    }
    @Test func taylorBadOrder() {
        let e = expectError("taylor sin(x), x=0, order=abc")
        #expect(e?.message.contains("whole number") == true)
    }
    @Test func limitMissingArrow() {
        #expect(expectError("limit sin(x)/x, x=0") != nil)
    }
    @Test func derivativeNoVariable() {
        // A constant expression has no variable to differentiate by.
        #expect(expectError("derivative 5") != nil)
    }
    @Test func tooManyRanges() {
        let e = expectError("integral x^2, x=0..1, x=2..3")
        #expect(e?.message.contains("at most one range") == true)
    }
}

// MARK: - Ambiguity (genuine multi-variable cases)

@Suite("Ambiguity")
struct Ambiguity {
    @Test func solveMultiVar() {
        let c = expectAmbiguous("solve x*y = 1")
        #expect(c == ["solve(x*y == 1, x)", "solve(x*y == 1, y)"])
    }
    @Test func derivativeMultiVar() {
        let c = expectAmbiguous("derivative x*y")
        #expect(c?.count == 2)
    }
    @Test func indefiniteIntegralMultiVar() {
        let c = expectAmbiguous("integral x*y")
        #expect(c?.count == 2)
    }
    // Disambiguated by an explicit clause → success, not ambiguous.
    @Test func solveForResolves() { expectSuccess("solve x*y = 1 for x", "solve(x*y == 1, x)") }
    @Test func derivativeWrtResolves() { expectSuccess("derivative x*y wrt y", "derivative(x*y, y)") }
}

// MARK: - Weird spacing & casing

@Suite("Spacing and casing")
struct Spacing {
    @Test func extraSpaces() {
        expectSuccess("factor    x^4 - 1", "factor(x^4 - 1)")
    }
    @Test func leadingTrailingSpaces() {
        expectSuccess("   factor x^4 - 1   ", "factor(x^4 - 1)")
    }
    @Test func tabsAroundCommand() {
        expectSuccess("factor\tx^4 - 1", "factor(x^4 - 1)")
    }
    @Test func spacesInRange() {
        expectSuccess("integral x^2 , x = 0 .. 1", "integrate(x^2, (x, 0, 1))")
    }
    @Test func spacesAroundArrow() {
        expectSuccess("limit sin(x)/x , x -> 0", "limit(sin(x)/x, x=0)")
    }
    @Test func uppercaseCommand() {
        expectSuccess("FACTOR x^4 - 1", "factor(x^4 - 1)")
    }
    @Test func mixedCaseCommand() {
        expectSuccess("Expand (x + 1)^5", "expand((x + 1)^5)")
    }
    @Test func doubleIntegralExtraSpaces() {
        expectSuccess("double integral  x*y ,  x=0..1 ,  y=0..x",
                      "integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))")
    }
    @Test func newlineStripped() {
        expectSuccess("factor x^4 - 1\n", "factor(x^4 - 1)")
    }
}

// MARK: - Command synonyms

@Suite("Synonyms")
struct Synonyms {
    @Test func diffSynonym() { expectSuccess("diff sin(x^2) wrt x", "derivative(sin(x^2), x)") }
    @Test func integrateSynonym() { expectSuccess("integrate x^2, x=0..1", "integrate(x^2, (x, 0, 1))") }
    @Test func doubleIntegrateSynonym() {
        expectSuccess("double integrate x*y, x=0..1, y=0..x",
                      "integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))")
    }
}

// MARK: - Required-variable inference

@Suite("Required variables")
struct RequiredVars {
    @Test func integralReportsBoundVar() {
        let r = FriendlyCompiler.compile("integral x^2, x=0..1")
        guard case let .success(_, vars) = r else { Issue.record("not success"); return }
        #expect(vars == ["x"])
    }
    @Test func plotReportsVar() {
        let r = FriendlyCompiler.compile("plot sin(x), x=-pi..pi")
        guard case let .success(_, vars) = r else { Issue.record("not success"); return }
        // pi is reserved, not a variable.
        #expect(vars == ["x"])
    }
    @Test func matrixHasNoVars() {
        let r = FriendlyCompiler.compile("matrix [[1,2],[3,4]]")
        guard case let .success(_, vars) = r else { Issue.record("not success"); return }
        #expect(vars.isEmpty)
    }
    @Test func piNotReportedAsVar() {
        let r = FriendlyCompiler.compile("factor pi*x")
        guard case let .success(_, vars) = r else { Issue.record("not success"); return }
        #expect(vars == ["x"])
    }
    @Test func functionNamesNotReported() {
        let r = FriendlyCompiler.compile("factor sin(x) + cos(y)")
        guard case let .success(_, vars) = r else { Issue.record("not success"); return }
        #expect(vars == ["x", "y"])
    }
}

// MARK: - No implicit multiplication (payload passed through verbatim)

@Suite("No implicit multiplication")
struct NoImplicitMult {
    @Test func payloadUnchanged() {
        // We do NOT insert `*` — `2x` stays `2x` inside the generated call (it is
        // the user's responsibility / Sage's preparser's job, not ours).
        expectSuccess("factor 2*x", "factor(2*x)")
    }
    @Test func doesNotRewriteAdjacency() {
        // `factor 2x` — we pass `2x` through untouched (no implicit `*` inserted).
        expectSuccess("factor 2x", "factor(2x)")
    }
}
