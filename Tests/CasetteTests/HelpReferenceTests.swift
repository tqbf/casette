import Testing
@testable import Casette

@Suite("HelpReference")
struct HelpReferenceTests {
    @Test("friendly compiler help covers the shipped command families")
    func coversCommandFamilies() {
        let commands = Set(
            HelpReference.sections
                .flatMap(\.examples)
                .map { $0.command.split(separator: " ").first.map(String.init) ?? "" }
        )

        for command in [
            "factor", "solve", "integral", "derivative", "limit", "plot",
            "matrix", "gradient", "subs", "numeric", "var", "assume",
            "choose", "mean", "normal_pdf", "binomial_pmf", "poisson_pmf",
            "exponential_pdf", "uniform_pdf", "binomial_cdf", "poisson_cdf",
            "poisson_at_most", "exponential_cdf", "uniform_cdf",
        ] {
            #expect(commands.contains(command), "missing \(command)")
        }
    }

    @Test("help includes the boundary rules users need")
    func includesBoundaryRules() {
        let examples = HelpReference.sections.flatMap(\.examples)

        #expect(examples.contains { $0.command == "factor(x^4 - 1)" })
        #expect(examples.contains { $0.command == "#14" })
        #expect(examples.contains { $0.command == "plot sin(x)" })
    }
}
