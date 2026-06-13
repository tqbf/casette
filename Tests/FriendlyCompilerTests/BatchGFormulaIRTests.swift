import Testing
@testable import FriendlyCompiler

@Suite("Statistics FormulaIR (Batch G)")
struct StatisticsFormulaIRTests {
    @Test func normalRoundTrips() {
        guard let ir = StatsFormulaIR.parse("normal_cdf 1.96, mean=0, sd=1") else {
            Issue.record("expected stats IR")
            return
        }
        #expect(ir.kind == .normalCDF)
        #expect(ir.positional == ["1.96"])
        #expect(ir.named["mean"] == "0")
        #expect(ir.named["sd"] == "1")
        #expect(ir.friendlyInput == "normal_cdf 1.96, mean=0, sd=1")
    }

    @Test func preservesEmptyNamedValues() {
        guard let ir = StatsFormulaIR.parse("binomial_cdf 3, n=10, p=") else {
            Issue.record("expected stats IR")
            return
        }
        #expect(ir.kind == .binomialCDF)
        #expect(ir.named["p"] == "")
        #expect(ir.friendlyInput == "binomial_cdf 3, n=10, p=")
    }

    @Test func preservesEmptyPositionalSlot() {
        guard let ir = StatsFormulaIR.parse("normal_between , 1") else {
            Issue.record("expected stats IR")
            return
        }
        #expect(ir.positional == ["", "1"])
        #expect(ir.friendlyInput == "normal_between , 1")
    }

    @Test func dispatchesFromFormulaIR() {
        guard case let .stats(ir) = FormulaIR.parse("poisson_between 1, 4, lambda=3") else {
            Issue.record("expected stats family")
            return
        }
        #expect(ir.kind == .poissonBetween)
    }

    @Test func allCommandsParseAsStats() {
        let commands = [
            "normal_pdf 0",
            "normal_cdf 0",
            "normal_between -1, 1",
            "normal_inv .95",
            "binomial_pmf 3, n=10, p=.5",
            "binomial_cdf 3, n=10, p=.5",
            "binomial_between 3, 7, n=10, p=.5",
            "binomial_at_most 3, n=10, p=.5",
            "binomial_at_least 8, n=10, p=.5",
            "poisson_pmf 2, lambda=3",
            "poisson_cdf 2, lambda=3",
            "poisson_between 1, 4, lambda=3",
            "poisson_at_most 2, lambda=3",
            "poisson_at_least 5, lambda=3",
            "exponential_pdf 1, rate=2",
            "exponential_cdf 1, rate=2",
            "exponential_between 1, 2, rate=2",
            "exponential_inv .95, rate=2",
            "uniform_pdf .5, min=0, max=1",
            "uniform_cdf .5, min=0, max=1",
            "uniform_between .2, .8, min=0, max=1",
            "uniform_inv .95, min=0, max=1",
        ]

        for command in commands {
            guard case .stats = FormulaIR.parse(command) else {
                Issue.record("expected stats IR for \(command)")
                continue
            }
        }
    }
}
