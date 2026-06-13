import Testing
@testable import FriendlyCompiler

// Batch F lowerings: environment commands (`var`, `assume`, `forget`) and the
// number-theory forms (`choose`, `gcd`, `lcm`, `factorial`, `is_prime`,
// `factor_integer`, `mean`). These assertions are additive — the frozen V0.7
// contract stays byte-identical.

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

@Suite("Var lowering (Batch F)")
struct VarLowering {
    @Test func spaceSeparated() {
        expectSuccess("var x y z", "var('x y z')")
        #expect(requiredVars("var x y z") == [])
    }

    @Test func commaSeparated() {
        expectSuccess("var x, y, z", "var('x y z')")
    }

    @Test func single() {
        expectSuccess("var theta", "var('theta')")
    }

    @Test func nonIdentifierErrors() {
        let e = expectError("var 3 x")
        #expect(e?.message.contains("identifiers") == true)
        #expect(e?.suggestion?.contains("var a b c") == true)
    }

    // The critical pin: `var = 3` must stay the assignment echo, byte-identical
    // to the pre-`var`-keyword behavior.
    @Test func assignmentEchoIsPreserved() {
        expectSuccess("var = 3", "var = 3\nvar")
        #expect(requiredVars("var = 3") == [])
    }

    @Test func callSyntaxBypasses() {
        expectBypass("var('x')")
    }
}

@Suite("Assume lowering (Batch F)")
struct AssumeLowering {
    @Test func comparison() {
        expectSuccess("assume x > 0", "assume(x > 0)")
        #expect(requiredVars("assume x > 0") == ["x"])
    }

    @Test func comparisonLessEqual() {
        expectSuccess("assume n <= 10", "assume(n <= 10)")
    }

    @Test func comparisonNotEqual() {
        expectSuccess("assume x != 0", "assume(x != 0)")
    }

    @Test func propertyReal() {
        expectSuccess("assume x real", "assume(x, 'real')")
    }

    @Test func propertyInteger() {
        expectSuccess("assume n integer", "assume(n, 'integer')")
    }

    @Test func propertyWithIsStripped() {
        expectSuccess("assume x is real", "assume(x, 'real')")
    }

    @Test func positiveLowersToComparison() {
        expectSuccess("assume x positive", "assume(x > 0)")
    }

    @Test func negativeLowersToComparison() {
        expectSuccess("assume x negative", "assume(x < 0)")
    }

    @Test func bareEqualsIsRejected() {
        let e = expectError("assume x = 3")
        #expect(e?.message.contains("comparison") == true)
    }

    @Test func unknownPropertyErrors() {
        let e = expectError("assume x prime")
        #expect(e?.suggestion?.contains("assume x > 0") == true)
    }

    @Test func reportsConditionFreeVariables() {
        #expect(requiredVars("assume x > 0") == ["x"])
        #expect(requiredVars("assume x real") == ["x"])
    }
}

@Suite("Forget lowering (Batch F)")
struct ForgetLowering {
    @Test func bareWord() {
        expectSuccess("forget", "forget()")
        #expect(requiredVars("forget") == [])
    }

    @Test func allKeyword() {
        expectSuccess("forget all", "forget()")
    }

    @Test func assumptionsKeyword() {
        expectSuccess("forget assumptions", "forget()")
    }

    @Test func garbagePayloadErrors() {
        let e = expectError("forget x > 0")
        #expect(e?.message.contains("clears all assumptions") == true)
    }
}

@Suite("Choose lowering (Batch F)")
struct ChooseLowering {
    @Test func happyPath() {
        expectSuccess("choose 10, 3", "binomial(10, 3)")
    }

    @Test func reportsFreeVariables() {
        let vars = requiredVars("choose n, k")
        #expect(vars?.contains("n") == true)
        #expect(vars?.contains("k") == true)
    }

    @Test func arityErrorTooFew() {
        let e = expectError("choose 10")
        #expect(e?.suggestion?.contains("choose 10, 3") == true)
    }

    @Test func arityErrorTooMany() {
        let e = expectError("choose 10, 3, 2")
        #expect(e?.suggestion?.contains("choose 10, 3") == true)
    }
}

@Suite("Gcd / Lcm lowering (Batch F)")
struct GcdLcmLowering {
    @Test func oneBracketedList() {
        expectSuccess("gcd [12, 18, 24]", "gcd([12, 18, 24])")
        expectSuccess("lcm [12, 18, 24]", "lcm([12, 18, 24])")
    }

    @Test func twoValues() {
        expectSuccess("gcd 12, 18", "gcd(12, 18)")
        expectSuccess("lcm 4, 6", "lcm(4, 6)")
    }

    @Test func threeOrMoreValuesWrapInList() {
        expectSuccess("gcd 12, 18, 24", "gcd([12, 18, 24])")
        expectSuccess("lcm 2, 3, 4, 5", "lcm([2, 3, 4, 5])")
    }

    @Test func oneNonBracketedErrors() {
        let e = expectError("gcd 12")
        #expect(e?.suggestion?.contains("gcd [12, 18, 24]") == true)
    }

    @Test func reportsFreeVariables() {
        #expect(requiredVars("gcd a, b") == ["a", "b"])
    }
}

@Suite("Factorial / IsPrime / FactorInteger lowering (Batch F)")
struct UnaryNumberTheoryLowering {
    @Test func factorial() {
        expectSuccess("factorial 5", "factorial(5)")
    }

    @Test func isPrime() {
        expectSuccess("is_prime 104729", "is_prime(104729)")
    }

    @Test func factorInteger() {
        expectSuccess("factor_integer 3600", "factor(3600)")
    }

    @Test func primeFactorizationAlias() {
        expectSuccess("prime_factorization 60", "factor(60)")
    }

    // COLLISION: `factor_integer 60` must NOT match `factor` — the char after
    // "factor" is "_", not whitespace.
    @Test func factorIntegerDoesNotMatchFactor() {
        expectSuccess("factor_integer 60", "factor(60)")
    }

    // COLLISION: `factorial 5` must NOT match `factor` (next char is "i").
    @Test func factorialDoesNotMatchFactor() {
        expectSuccess("factorial 5", "factorial(5)")
    }

    // `is_prime(7)` is already a call — it bypasses (no trailing space).
    @Test func isPrimeCallBypasses() {
        expectBypass("is_prime(7)")
    }

    @Test func reportsFreeVariables() {
        #expect(requiredVars("factorial n") == ["n"])
    }
}

@Suite("Mean lowering (Batch F)")
struct MeanLowering {
    // The owned lowering keeps results exact: sum([1,2,3])/len([1,2,3]) → 2.
    @Test func ownedLowering() {
        expectSuccess("mean [1, 2, 3]", "sum([1, 2, 3])/len([1, 2, 3])")
    }

    @Test func variableData() {
        expectSuccess("mean data", "sum(data)/len(data)")
        #expect(requiredVars("mean data") == ["data"])
    }

    @Test func multiClauseErrors() {
        let e = expectError("mean 1, 2, 3")
        #expect(e?.suggestion?.contains("mean [1, 2, 3]") == true)
    }
}
