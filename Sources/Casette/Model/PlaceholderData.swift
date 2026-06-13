import Foundation

/// Fake session data for the shell, now expressed in the REAL V1.2 model
/// (`SessionRow` + `PersistedEnvelope`, lifted from v0/10). Every value is
/// faithful to what the real worker returns (kinds, plain text, LaTeX, the
/// V0.8 exact/approx split, the per-kind actions map from WORKER-PROTOCOL.md)
/// so the layout is exercised by product-shaped content, not lorem ipsum.
/// V1.3 replaces this with live evaluations.
enum PlaceholderData {
    // Per-kind actions, verbatim from the frozen WORKER-PROTOCOL.md map.
    private static let integerActions = ["factor", "is_prime", "next_prime", "approx", "hex"]
    private static let rationalActions = ["numerator", "denominator", "approx", "continued_fraction"]
    private static let symbolicActions = [
        "simplify", "trig_simplify", "factor", "expand", "approx", "diff",
        "integrate",
    ]
    private static let matrixActions = [
        "det", "rank", "rref", "eigenvalues", "transpose", "inverse",
        "column_space", "row_space", "right_kernel", "change_ring_RDF",
    ]
    private static let listActions = ["length", "sort", "sum", "set"]
    private static let plotActions = ["save_png", "save_svg", "show"]
    private static let errorActions = ["copy_traceback"]

    static let rows: [SessionRow] = {
        let base = Date.now.addingTimeInterval(-11 * 60)
        func at(_ minute: Double) -> Date { base.addingTimeInterval(minute * 60) }

        /// A completed row: provenance is `cached` at the eval time, exactly
        /// as the V0.10 recorder stamps a freshly evaluated result.
        func row(
            input: String, sage: String, status: RowStatus = .ok,
            result: PersistedEnvelope?, at timestamp: Date, duration: Double?
        ) -> SessionRow {
            SessionRow(
                input: input, sage: sage, result: result, status: status,
                timestamp: timestamp, durationSeconds: duration,
                provenance: Provenance(kind: .cached, cachedAt: timestamp)
            )
        }

        /// A worker statement with no value (V0.1 None-suppression).
        let statement = PersistedEnvelope(kind: "none", plain: "")

        return [
            row(
                input: "2 + 2", sage: "2 + 2",
                result: PersistedEnvelope(
                    kind: "integer", plain: "4", latex: "4", repr: "4",
                    exact: true, primaryIsApprox: false, actions: integerActions
                ),
                at: at(0), duration: 0.0008
            ),
            row(
                input: "1/3 + 1/5", sage: "1/3 + 1/5",
                result: PersistedEnvelope(
                    kind: "rational", plain: "8/15", latex: "\\frac{8}{15}", repr: "8/15",
                    approx: "0.5333333333", approxDigits: 10,
                    exact: true, primaryIsApprox: false, actions: rationalActions
                ),
                at: at(1), duration: 0.0011
            ),
            row(
                input: "sqrt(2)", sage: "sqrt(2)",
                result: PersistedEnvelope(
                    kind: "symbolic", plain: "sqrt(2)", latex: "\\sqrt{2}", repr: "sqrt(2)",
                    approx: "1.414213562", approxDigits: 10,
                    exact: true, primaryIsApprox: false, actions: symbolicActions
                ),
                at: at(2), duration: 0.0019
            ),
            row(
                input: "x = var(\"x\")", sage: "x = var(\"x\")",
                result: statement, at: at(3), duration: 0.0006
            ),
            row(
                input: "factor x^4 - 1", sage: "factor(x^4 - 1)",
                result: PersistedEnvelope(
                    kind: "symbolic", plain: "(x^2 + 1)*(x + 1)*(x - 1)",
                    latex: "{\\left(x^{2} + 1\\right)} {\\left(x + 1\\right)} {\\left(x - 1\\right)}",
                    repr: "(x^2 + 1)*(x + 1)*(x - 1)",
                    exact: true, primaryIsApprox: false, actions: symbolicActions
                ),
                at: at(4), duration: 0.0014
            ),
            row(
                input: "expand (x + 1)^8", sage: "expand((x + 1)^8)",
                result: PersistedEnvelope(
                    kind: "symbolic",
                    plain: "x^8 + 8*x^7 + 28*x^6 + 56*x^5 + 70*x^4 + 56*x^3 + 28*x^2 + 8*x + 1",
                    latex: "x^{8} + 8 \\, x^{7} + 28 \\, x^{6} + 56 \\, x^{5} + 70 \\, x^{4} + 56 \\, x^{3} + 28 \\, x^{2} + 8 \\, x + 1",
                    repr: "x^8 + 8*x^7 + 28*x^6 + 56*x^5 + 70*x^4 + 56*x^3 + 28*x^2 + 8*x + 1",
                    exact: true, primaryIsApprox: false, actions: symbolicActions
                ),
                at: at(5), duration: 0.0021
            ),
            row(
                input: "A = matrix([[2,1],[1,2]])", sage: "A = matrix([[2,1],[1,2]])",
                result: statement, at: at(6), duration: 0.0009
            ),
            row(
                input: "A", sage: "A",
                result: PersistedEnvelope(
                    kind: "matrix", plain: "[2 1]\n[1 2]",
                    // Sage's real matrix LaTeX — the `array` form the
                    // normalizer rewrites to pmatrix (PROBLEMS.md V0.4).
                    latex: "\\left(\\begin{array}{rr}\n2 & 1 \\\\\n1 & 2\n\\end{array}\\right)",
                    repr: "[2 1]\n[1 2]",
                    actions: matrixActions
                ),
                at: at(6.5), duration: 0.0012
            ),
            row(
                input: "print(\"hello\")", sage: "print(\"hello\")",
                result: PersistedEnvelope(kind: "none", plain: "", stdout: "hello\n"),
                at: at(6.7), duration: 0.0005
            ),
            row(
                input: "A.eigenvalues()", sage: "A.eigenvalues()",
                result: PersistedEnvelope(
                    kind: "list", plain: "[3, 1]", latex: "\\left[3, 1\\right]",
                    repr: "[3, 1]", actions: listActions
                ),
                at: at(7), duration: 0.0035
            ),
            row(
                input: "solve x^2 + 5*x + 6 = 0", sage: "solve(x^2 + 5*x + 6 == 0, x)",
                result: PersistedEnvelope(
                    kind: "list", plain: "[x == -3, x == -2]",
                    latex: "\\left[x = \\left(-3\\right), x = \\left(-2\\right)\\right]",
                    repr: "[x == -3, x == -2]", actions: listActions
                ),
                at: at(8), duration: 0.0042
            ),
            row(
                input: "plot sin(x), x=-pi..pi", sage: "plot(sin(x), (x, -pi, pi))",
                result: PersistedEnvelope(
                    kind: "plot",
                    plain: "Graphics object consisting of 1 graphics primitive",
                    repr: "Graphics object consisting of 1 graphics primitive",
                    actions: plotActions,
                    // Path-ref artifacts whose worker /tmp dir is gone — the
                    // EXPECTED restored state (PROBLEMS.md V0.5/V0.10), so the
                    // shell exercises the graceful-degrade path from day one.
                    artifacts: [
                        PersistedArtifact(
                            type: "image", format: "svg",
                            path: "/tmp/sagecalc/session-0-placeholder/plot-00001.svg",
                            bytes: 20587, status: .missing
                        ),
                        PersistedArtifact(
                            type: "image", format: "png",
                            path: "/tmp/sagecalc/session-0-placeholder/plot-00001.png",
                            bytes: 18896, status: .missing
                        ),
                    ]
                ),
                at: at(9), duration: 0.31
            ),
            row(
                input: "1/0", sage: "1/0", status: .error,
                result: PersistedEnvelope(
                    kind: "error", plain: "rational division by zero",
                    repr: "rational division by zero", actions: errorActions,
                    error: PersistedError(
                        type: "ZeroDivisionError",
                        message: "rational division by zero",
                        traceback: "Traceback (most recent call last):\n  ...\nZeroDivisionError: rational division by zero"
                    )
                ),
                at: at(10), duration: 0.0007
            ),
        ]
    }()

    /// Entries sorted by name, exactly as the worker `symbols` op returns them.
    static let symbols = SymbolSnapshot(
        entries: [
            SymbolEntry(name: "A", kind: "matrix", summary: "2×2 over Integer Ring"),
            SymbolEntry(name: "f", kind: "symbolic function", summary: "x |--> sin(x)/x"),
            SymbolEntry(name: "n", kind: "integer", summary: "104729"),
            SymbolEntry(name: "x", kind: "symbolic variable", summary: "x"),
        ],
        capturedAt: nil
    )
}
