import Foundation
import FriendlyCompiler

/// One context-sensitive action for a selected result — the V1.6 Actions tab
/// face of the envelope's per-kind `actions` names (WORKER-PROTOCOL.md).
///
/// Command strategy (the V1.6 design decision, V1.11 builds on it): the
/// worker has NO `ans` variable, so a follow-up command must re-state what it
/// operates on. Each command action wraps the row's own generated Sage —
/// "det" on a `matrix([[1,2],[3,4]])` row builds
/// `(matrix([[1,2],[3,4]])).det()`. That is honest (the command is exactly
/// what runs, previewable in the input before evaluating), stateless (no
/// hidden result references), and replay-safe (the command re-evaluates
/// correctly from the tape alone, in tape order).
///
/// Derived, never stored: action names stay frozen wire vocabulary; this type
/// is presentation + command building only.
struct ResultAction: Identifiable, Equatable, Sendable {
    /// What activating the action does.
    enum Behavior: Equatable, Sendable {
        /// Builds a Sage follow-up command around the row's reusable
        /// expression (see `SessionRow.reusableExpression`).
        case command
        /// Copies the result's plain text (the `text` kind's `copy`).
        case copyPlain
        /// Copies the error traceback (`copy_traceback`).
        case copyTraceback
        /// Listed by the worker but not actionable from THIS tab — shown
        /// inert with the reason (plot save/copy live on the plot card's own
        /// context menu since V1.7; richer wiring is V1.11).
        case unavailable(String)
    }

    /// The frozen wire name (`det`, `simplify`, `copy_traceback`, …).
    let name: String

    var id: String { name }

    /// All actions for a result envelope, in the worker's order.
    static func actions(for result: PersistedEnvelope) -> [ResultAction] {
        result.actions.map { ResultAction(name: $0) }
    }

    /// Human title for the sidebar row. Unknown names show as themselves —
    /// honest, and a future worker vocabulary degrades visibly, not silently.
    var title: String {
        switch name {
        case "factor": "Factor"
        case "is_prime": "Is Prime?"
        case "next_prime": "Next Prime"
        case "approx": "Numeric Approximation"
        case "hex": "Hexadecimal"
        case "numerator": "Numerator"
        case "denominator": "Denominator"
        case "continued_fraction": "Continued Fraction"
        case "approx_more_digits": "More Digits"
        case "round": "Round"
        case "real_part": "Real Part"
        case "imag_part": "Imaginary Part"
        case "abs": "Absolute Value"
        case "arg": "Argument"
        case "conjugate": "Conjugate"
        case "simplify": "Simplify"
        case "trig_simplify": "Trig Simplify"
        case "expand": "Expand"
        case "diff": "Differentiate"
        case "integrate": "Integrate"
        case "solve": "Solve"
        case "lhs": "Left-Hand Side"
        case "rhs": "Right-Hand Side"
        case "subtract_sides": "Subtract Sides"
        case "det": "Determinant"
        case "rank": "Rank"
        case "rref": "Reduced Row Echelon"
        case "eigenvalues": "Eigenvalues"
        case "transpose": "Transpose"
        case "inverse": "Inverse"
        case "column_space": "Column Space"
        case "row_space": "Row Space"
        case "right_kernel": "Right Kernel Basis"
        case "length": "Length"
        case "sort": "Sort"
        case "sum": "Sum"
        case "set": "As Set"
        case "repr": "Repr"
        case "type": "Type"
        case "copy": "Copy Text"
        case "copy_traceback": "Copy Traceback"
        case "save_png": "Save PNG"
        case "save_svg": "Save SVG"
        case "show": "Show"
        default: name
        }
    }

    var behavior: Behavior {
        switch name {
        case "copy": .copyPlain
        case "copy_traceback": .copyTraceback
        case "save_png", "save_svg", "show":
            .unavailable("Use the plot image on the tape — click to expand; right-click to copy or save.")
        case _ where commandTemplateExists: .command
        default: .unavailable("Not supported by this version of Casette.")
        }
    }

    /// The Sage command this action builds around the row's reusable
    /// expression, or nil for non-command behaviors. The expression is
    /// parenthesized wherever it lands in method position, so operator
    /// precedence can never change its meaning (`(2 + 3).is_prime()`).
    func command(wrapping expression: String) -> String? {
        let wrapped = "(\(expression))"
        switch name {
        case "factor": return "factor(\(expression))"
        case "is_prime": return "\(wrapped).is_prime()"
        case "next_prime": return "next_prime(\(expression))"
        case "approx": return "\(wrapped).n()"
        case "hex": return "hex(\(expression))"
        case "numerator": return "\(wrapped).numerator()"
        case "denominator": return "\(wrapped).denominator()"
        case "continued_fraction": return "continued_fraction(\(expression))"
        case "approx_more_digits": return "\(wrapped).n(digits=50)"
        case "round": return "round(\(expression))"
        case "real_part": return "\(wrapped).real()"
        case "imag_part": return "\(wrapped).imag()"
        case "abs": return "abs(\(expression))"
        case "arg": return "\(wrapped).arg()"
        case "conjugate": return "\(wrapped).conjugate()"
        case "simplify": return "\(wrapped).simplify_full()"
        case "trig_simplify": return "\(wrapped).simplify_trig()"
        case "expand": return "expand(\(expression))"
        case "diff": return "diff(\(expression), \(Self.primaryVariable(of: expression)))"
        case "integrate": return "integrate(\(expression), \(Self.primaryVariable(of: expression)))"
        case "solve": return "solve(\(expression), \(Self.primaryVariable(of: expression)))"
        case "lhs": return "\(wrapped).lhs()"
        case "rhs": return "\(wrapped).rhs()"
        case "subtract_sides": return "\(wrapped).lhs() - \(wrapped).rhs()"
        case "det": return "\(wrapped).det()"
        case "rank": return "\(wrapped).rank()"
        case "rref": return "\(wrapped).rref()"
        case "eigenvalues": return "\(wrapped).eigenvalues()"
        case "transpose": return "\(wrapped).transpose()"
        case "inverse": return "\(wrapped).inverse()"
        case "column_space": return "\(wrapped).column_space().basis()"
        case "row_space": return "\(wrapped).row_space().basis()"
        case "right_kernel": return "\(wrapped).right_kernel().basis()"
        case "length": return "len(\(expression))"
        case "sort": return "sorted(\(expression))"
        case "sum": return "sum(\(expression))"
        case "set": return "Set(\(expression))"
        case "repr": return "repr(\(expression))"
        case "type": return "type(\(expression))"
        default: return nil
        }
    }

    private var commandTemplateExists: Bool {
        command(wrapping: "_") != nil
    }

    /// The variable a `diff`/`integrate`/`solve` command names: the
    /// expression's first free variable by the SAME documented heuristic the
    /// compiler's prelude policy uses, falling back to `x`. The inserted
    /// command is editable in the input before evaluating, so a multi-variable
    /// expression's choice is a visible, correctable default — never hidden.
    private static func primaryVariable(of expression: String) -> String {
        FriendlyCompiler.freeVariables(in: expression).first ?? "x"
    }
}
