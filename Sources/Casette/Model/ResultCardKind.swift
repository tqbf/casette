import Foundation

/// Which result card a tape row renders — the V1.5 card vocabulary from
/// INITIAL.md (scalar exact / scalar approximate / symbolic / matrix /
/// list / plot / text·stdout / error), plus the row states that aren't
/// results at all (pending, statement, interrupted).
///
/// Derived, never stored: the mapping reads the frozen envelope fields
/// (`kind`, the V0.8 `primaryIsApprox`) and the row status. Card kind only
/// decides PRESENTATION — what the hero is and which chrome applies; the
/// result data never changes (the V1.2 rule).
enum ResultCardKind: Equatable {
    /// Submitted but not completed (spinner / "not evaluated").
    case pending
    /// A statement — no echoed value. Captured stdout still shows.
    case statement
    /// An exact scalar (`8/15`): exact primary, `≈` secondary line.
    case scalarExact
    /// An approximate scalar (`2.5`, force-numeric): `≈` on the primary.
    case scalarApproximate
    /// A symbolic expression / relation.
    case symbolic
    case matrix
    /// A list or tuple (incl. `solve`'s Sequence).
    case list
    /// A plot — card chrome now, the real PNG at V1.7.
    case plot
    /// Text, booleans, and unknown kinds — plain (or repr-degraded) content.
    case text
    case error
    case interrupted

    init(row: SessionRow) {
        switch row.status {
        case .running:
            self = .pending
        case .error:
            self = .error
        case .interrupted:
            self = .interrupted
        case .ok:
            guard let result = row.result else {
                self = .pending  // completed-without-envelope never happens in practice
                return
            }
            self = ResultCardKind(okEnvelope: result)
        }
    }

    /// The kind→card mapping for a successful result envelope.
    init(okEnvelope result: PersistedEnvelope) {
        if result.kind == "plot" {
            self = .plot
        } else if result.kind == "none" || result.plain.isEmpty {
            self = .statement
        } else {
            switch result.kind {
            case "matrix":
                self = .matrix
            case "list":
                self = .list
            case "symbolic", "relation":
                self = .symbolic
            case "integer", "rational":
                // Force-numeric (V0.8) puts the approximation in the primary
                // slot even for exact kinds — the card is honest about it.
                self = (result.primaryIsApprox == true) ? .scalarApproximate : .scalarExact
            case "real", "complex":
                self = .scalarApproximate
            default:  // text, boolean, unknown, …
                self = .text
            }
        }
    }
}
