import Testing
@testable import FriendlyCompiler

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

@Suite("Statistics lowering (Batch G)")
struct StatisticsLowering {
    @Test func normalDistribution() {
        expectSuccess("normal_pdf 0", "normal_pdf(0)")
        expectSuccess("normal_cdf 1.96, mean=0, sd=1", "normal_cdf(1.96, mean=0, sd=1)")
        expectSuccess("normal_between -1, 1", "normal_between(-1, 1)")
        expectSuccess("normal_inv .975", "normal_inv(.975)")
    }

    @Test func binomialDistribution() {
        expectSuccess("binomial_pmf 3, n=10, p=.5", "binomial_pmf(3, n=10, p=.5)")
        expectSuccess("binomial_cdf 3, n=10, p=.5", "binomial_cdf(3, n=10, p=.5)")
        expectSuccess(
            "binomial_between 3, 7, n=10, p=.5",
            "binomial_between(3, 7, n=10, p=.5)")
        expectSuccess(
            "binomial_at_most 3, n=10, p=.5",
            "binomial_at_most(3, n=10, p=.5)")
        expectSuccess(
            "binomial_at_least 8, n=10, p=.5",
            "binomial_at_least(8, n=10, p=.5)")
    }

    @Test func poissonDistribution() {
        expectSuccess("poisson_pmf 2, lambda=3", "poisson_pmf(2, lambda_=3)")
        expectSuccess("poisson_cdf 2, lambda=3", "poisson_cdf(2, lambda_=3)")
        expectSuccess(
            "poisson_between 1, 4, lambda=3",
            "poisson_between(1, 4, lambda_=3)")
        expectSuccess("poisson_at_most 2, lambda=3", "poisson_at_most(2, lambda_=3)")
        expectSuccess("poisson_at_least 5, lambda=3", "poisson_at_least(5, lambda_=3)")
    }

    @Test func exponentialDistribution() {
        expectSuccess("exponential_pdf 1, rate=2", "exponential_pdf(1, rate=2)")
        expectSuccess("exponential_cdf 1, rate=2", "exponential_cdf(1, rate=2)")
        expectSuccess(
            "exponential_between 1, 2, rate=2",
            "exponential_between(1, 2, rate=2)")
        expectSuccess("exponential_inv .95, rate=2", "exponential_inv(.95, rate=2)")
    }

    @Test func uniformDistribution() {
        expectSuccess("uniform_pdf .5, min=0, max=1", "uniform_pdf(.5, low=0, high=1)")
        expectSuccess("uniform_cdf .5, min=0, max=1", "uniform_cdf(.5, low=0, high=1)")
        expectSuccess(
            "uniform_between .2, .8, min=0, max=1",
            "uniform_between(.2, .8, low=0, high=1)")
        expectSuccess("uniform_inv .95, min=0, max=1", "uniform_inv(.95, low=0, high=1)")
    }

    @Test func reportsFreeVariablesFromValuesOnly() {
        #expect(requiredVars("normal_cdf z, mean=mu, sd=sigma") == ["z", "mu", "sigma"])
        #expect(requiredVars("poisson_cdf k, lambda=lam") == ["k", "lam"])
    }

    @Test func missingRequiredNamedArgumentErrors() {
        let e = expectError("binomial_cdf 3, n=10")
        #expect(e?.message.contains("p=") == true)
        #expect(e?.suggestion?.contains("binomial_cdf") == true)
    }

    @Test func unknownNamedArgumentErrors() {
        let e = expectError("normal_cdf 1, sigma=2")
        #expect(e?.message.contains("sigma") == true)
        #expect(e?.suggestion?.contains("normal_cdf") == true)
    }

    @Test func positionalValuesMustComeFirst() {
        let e = expectError("normal_between -1, mean=0, 1")
        #expect(e?.message.contains("positional values") == true)
    }
}
