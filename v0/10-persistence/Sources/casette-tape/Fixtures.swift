import Foundation
import SessionStore

// MARK: - The proof tape (curated input→sage pairs)
//
// We HARDCODE known-good (input, sage) pairs taken from the v0/07 friendly
// compiler README (its frozen reference table) rather than shelling out to the
// sagecalc-compile CLI. Documented choice: it keeps this proof self-contained and
// hermetic (no cross-package CLI dependency), while still exercising BOTH a
// friendly-compiled input AND a raw-Sage bypass — the input/sage distinction the
// session rows store (FRIENDLY-COMPILER.md). The pairs below are exactly the v0/07
// table outputs.
//
// The tape is deliberately STATE-DEPENDENT: row "A = matrix(...)" assigns A, and
// a later row "A.eigenvalues()" uses it — so a correct replay MUST preserve order.

enum Fixtures {
  /// The main proof tape. Mixes friendly-compiled inputs and raw-Sage bypasses.
  static var mainTape: [RecordStep] {
    [
      // friendly: "factor x^4 - 1" → factor(x^4 - 1)  (needs x)
      RecordStep(
        input: "factor x^4 - 1",
        sage: "factor(x^4 - 1)",
        requiredVariables: ["x"]),
      // raw Sage bypass: a rational sum (exact primary + approx secondary, V0.8)
      RecordStep(
        input: "1/3 + 1/5",
        sage: "1/3 + 1/5"),
      // raw Sage bypass: assigns A into the namespace (state-dependent setup)
      RecordStep(
        input: "A = matrix([[2, 0], [0, 3]])",
        sage: "A = matrix([[2, 0], [0, 3]])"),
      // friendly: "eigenvalues [[2,0],[0,3]]" → ...  but here we USE the stored A
      // to PROVE order-dependent replay: this row references the prior row's A.
      RecordStep(
        input: "A.eigenvalues()",
        sage: "A.eigenvalues()"),
      // raw Sage bypass: a symbolic exact value (sqrt(2) — exact, with approx)
      RecordStep(
        input: "sqrt(2)",
        sage: "sqrt(2)",
        requiredVariables: []),
    ]
  }

  /// A tape whose single row is a PLOT, used for the missing-artifact proof.
  static var plotTape: [RecordStep] {
    [
      RecordStep(
        input: "plot sin(x), -pi..pi",
        sage: "plot(sin(x), (x, -pi, pi))",
        requiredVariables: ["x"]),
    ]
  }
}
