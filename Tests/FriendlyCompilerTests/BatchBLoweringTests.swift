import Testing
@testable import FriendlyCompiler

// Batch B lowerings: the new `sum`/`product` keyword forms, the derivative
// `order` extension, and the limit `direction` extension. These assertions are
// additive — they never touch the frozen V0.7 contract.

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

private func expectAmbiguous(_ input: String,
                             sourceLocation: SourceLocation = #_sourceLocation) -> [String]? {
    let r = FriendlyCompiler.compile(input)
    guard case let .ambiguous(c) = r else {
        Issue.record("expected .ambiguous for \(input), got \(r)", sourceLocation: sourceLocation)
        return nil
    }
    return c
}

@Suite("Sum and product lowering")
struct SumProductLowering {
    @Test func sumHappyPath() {
        expectSuccess("sum k^2, k=1..n", "sum(k^2, k, 1, n)")
    }
    @Test func productHappyPath() {
        expectSuccess("product 1 + 1/k, k=1..n", "product(1 + 1/k, k, 1, n)")
    }
    @Test func sumConstantBounds() {
        expectSuccess("sum k^2, k=1..10", "sum(k^2, k, 1, 10)")
    }
    @Test func sumRequiresIndexAndFreeVar() {
        // The bound index `k` plus the free upper-bound symbol `n`.
        #expect(requiredVars("sum k^2, k=1..n") == ["k", "n"])
    }
    @Test func sumMissingRange() {
        let e = expectError("sum k^2")
        #expect(e?.message.contains("needs a range") == true)
    }
    @Test func sumMissingExpression() {
        #expect(expectError("sum") != nil)
    }
    @Test func sumMalformedRange() {
        let e = expectError("sum k^2, k=1..")
        #expect(e != nil)
    }
    @Test func sumTooManyRanges() {
        let e = expectError("sum k^2, k=1..n, j=1..m")
        #expect(e?.message.contains("one range") == true)
    }
    @Test func sumPreservesTapeReference() {
        expectSuccess("sum #3 * k, k=1..10", "sum(#3 * k, k, 1, 10)")
    }
}

@Suite("Derivative order lowering")
struct DerivativeOrderLowering {
    @Test func orderInferredVariable() {
        expectSuccess("derivative sin(x), 2", "derivative(sin(x), x, 2)")
    }
    @Test func orderWithWrt() {
        expectSuccess("derivative x*y, 2 wrt y", "derivative(x*y, y, 2)")
    }
    @Test func orderAmbiguousCandidatesCarryOrder() {
        let c = expectAmbiguous("derivative x*y, 2")
        #expect(c == ["derivative(x*y, x, 2)", "derivative(x*y, y, 2)"])
    }
    @Test func noOrderStillFirstDerivative() {
        // Byte-identical to the frozen single-payload path.
        expectSuccess("derivative sin(x^2)", "derivative(sin(x^2), x)")
    }
    @Test func orderPreservesTapeReference() {
        expectSuccess("derivative #14, 2 wrt x", "derivative(#14, x, 2)")
    }
}

@Suite("Limit direction lowering")
struct LimitDirectionLowering {
    @Test func leftDirection() {
        expectSuccess("limit sin(x)/x, x->0, left", "limit(sin(x)/x, x=0, dir='-')")
    }
    @Test func rightDirection() {
        expectSuccess("limit sin(x)/x, x->0, right", "limit(sin(x)/x, x=0, dir='+')")
    }
    @Test func directionCaseInsensitive() {
        expectSuccess("limit sin(x)/x, x->0, RIGHT", "limit(sin(x)/x, x=0, dir='+')")
    }
    @Test func twoClauseFormUnchanged() {
        expectSuccess("limit sin(x)/x, x->0", "limit(sin(x)/x, x=0)")
    }
    @Test func invalidDirection() {
        let e = expectError("limit sin(x)/x, x->0, sideways")
        #expect(e?.message.contains("direction must be") == true)
    }
}
