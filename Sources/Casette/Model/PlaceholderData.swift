import Foundation

/// Fake session data for the V1.1 shell. Every value is faithful to what the
/// real worker returns (kinds, plain text, LaTeX, the V0.8 exact/approx
/// split, the per-kind actions map from WORKER-PROTOCOL.md) so the layout is
/// exercised by product-shaped content, not lorem ipsum.
enum PlaceholderData {
    // Per-kind actions, verbatim from the frozen WORKER-PROTOCOL.md map.
    private static let integerActions = ["factor", "is_prime", "next_prime", "approx", "hex"]
    private static let rationalActions = ["numerator", "denominator", "approx", "continued_fraction"]
    private static let symbolicActions = ["simplify", "factor", "expand", "approx", "diff", "integrate"]
    private static let listActions = ["length", "sort", "sum", "set"]
    private static let plotActions = ["save_png", "save_svg", "show"]
    private static let errorActions = ["copy_traceback"]

    static let rows: [TapeRow] = {
        let base = Date.now.addingTimeInterval(-11 * 60)
        func at(_ minute: Double) -> Date { base.addingTimeInterval(minute * 60) }

        return [
            TapeRow(
                input: "2 + 2", sage: "2 + 2", status: .ok, kind: "integer",
                primary: "4", latex: "4",
                actions: integerActions, timestamp: at(0), duration: 0.0008
            ),
            TapeRow(
                input: "1/3 + 1/5", sage: "1/3 + 1/5", status: .ok, kind: "rational",
                primary: "8/15", latex: "\\frac{8}{15}", approx: "0.5333333333",
                actions: rationalActions, timestamp: at(1), duration: 0.0011
            ),
            TapeRow(
                input: "sqrt(2)", sage: "sqrt(2)", status: .ok, kind: "symbolic",
                primary: "sqrt(2)", latex: "\\sqrt{2}", approx: "1.414213562",
                actions: symbolicActions, timestamp: at(2), duration: 0.0019
            ),
            TapeRow(
                input: "x = var(\"x\")", sage: "x = var(\"x\")", status: .ok, kind: "none",
                primary: "", timestamp: at(3), duration: 0.0006
            ),
            TapeRow(
                input: "factor x^4 - 1", sage: "factor(x^4 - 1)", status: .ok, kind: "symbolic",
                primary: "(x^2 + 1)*(x + 1)*(x - 1)",
                latex: "{\\left(x^{2} + 1\\right)} {\\left(x + 1\\right)} {\\left(x - 1\\right)}",
                actions: symbolicActions, timestamp: at(4), duration: 0.0014
            ),
            TapeRow(
                input: "expand (x + 1)^8", sage: "expand((x + 1)^8)", status: .ok, kind: "symbolic",
                primary: "x^8 + 8*x^7 + 28*x^6 + 56*x^5 + 70*x^4 + 56*x^3 + 28*x^2 + 8*x + 1",
                latex: "x^{8} + 8 \\, x^{7} + 28 \\, x^{6} + 56 \\, x^{5} + 70 \\, x^{4} + 56 \\, x^{3} + 28 \\, x^{2} + 8 \\, x + 1",
                actions: symbolicActions, timestamp: at(5), duration: 0.0021
            ),
            TapeRow(
                input: "A = matrix([[2,1],[1,2]])", sage: "A = matrix([[2,1],[1,2]])",
                status: .ok, kind: "none",
                primary: "", timestamp: at(6), duration: 0.0009
            ),
            TapeRow(
                input: "A.eigenvalues()", sage: "A.eigenvalues()", status: .ok, kind: "list",
                primary: "[3, 1]", latex: "\\left[3, 1\\right]",
                actions: listActions, timestamp: at(7), duration: 0.0035
            ),
            TapeRow(
                input: "solve x^2 + 5*x + 6 = 0", sage: "solve(x^2 + 5*x + 6 == 0, x)",
                status: .ok, kind: "list",
                primary: "[x == -3, x == -2]",
                latex: "\\left[x = \\left(-3\\right), x = \\left(-2\\right)\\right]",
                actions: listActions, timestamp: at(8), duration: 0.0042
            ),
            TapeRow(
                input: "plot sin(x), x=-pi..pi", sage: "plot(sin(x), (x, -pi, pi))",
                status: .ok, kind: "plot",
                primary: "Graphics object consisting of 1 graphics primitive",
                actions: plotActions, timestamp: at(9), duration: 0.31
            ),
            TapeRow(
                input: "1/0", sage: "1/0", status: .error, kind: "error",
                primary: "rational division by zero",
                errorType: "ZeroDivisionError",
                actions: errorActions, timestamp: at(10), duration: 0.0007
            ),
        ]
    }()

    /// Sorted by name, exactly as the worker `symbols` op returns them.
    static let symbols: [SymbolEntry] = [
        SymbolEntry(name: "A", kind: "matrix", summary: "2×2 over Integer Ring"),
        SymbolEntry(name: "f", kind: "symbolic function", summary: "x |--> sin(x)/x"),
        SymbolEntry(name: "n", kind: "integer", summary: "104729"),
        SymbolEntry(name: "x", kind: "symbolic variable", summary: "x"),
    ]
}
