import Foundation

/// The small user-editable shape behind Casette's vector-calculus formula bars:
/// `gradient`, `hessian`, and `jacobian`. One IR covers all three (the way
/// `UnaryFormulaIR` covers expand/factor/simplify) — they share a leading
/// expression and an optional bracketed variable list.
///
/// The variable list is ONE semantic group (the bracketed `[x, y]` text). For
/// `gradient` it is optional; for `jacobian` it is the second required clause
/// and the expression field holds the bracketed FUNCTIONS list; `hessian`
/// never renders a variable list. Like the other formula IRs this renders back
/// to friendly input, not Sage; `#14` tape references stay intact until the
/// app's compile boundary.
public struct VectorCalculusFormulaIR: Equatable, Sendable {
    /// Which vector-calculus command this bar represents. The cases mirror the
    /// matching `FriendlyCompiler.Keyword`s so the chip and lowering agree.
    public enum Kind: Equatable, Sendable, CaseIterable {
        case gradient
        case hessian
        case jacobian

        /// The canonical friendly command word (also the rendered prefix).
        public var command: String {
            switch self {
            case .gradient: return "gradient"
            case .hessian: return "hessian"
            case .jacobian: return "jacobian"
            }
        }

        /// The uppercase chip title shown in the formula bar.
        public var title: String {
            switch self {
            case .gradient: return "GRADIENT"
            case .hessian: return "HESSIAN"
            case .jacobian: return "JACOBIAN"
            }
        }

        fileprivate init?(_ keyword: FriendlyCompiler.Keyword) {
            switch keyword {
            case .gradient: self = .gradient
            case .hessian: self = .hessian
            case .jacobian: self = .jacobian
            default: return nil
            }
        }
    }

    public var kind: Kind
    /// The leading expression; for `jacobian` this is the bracketed functions
    /// list (`[x^2+y, sin(x*y)]`).
    public var expression: String
    /// The bracketed variable-list text (`[x, y]`), or empty. `hessian` never
    /// renders this.
    public var variables: String

    public init(kind: Kind, expression: String, variables: String = "") {
        self.kind = kind
        self.expression = expression
        self.variables = variables
    }

    public static func parse(_ rawInput: String) -> VectorCalculusFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              let kind = Kind(command.keyword)
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""

        // `hessian` carries no variable list; the others take the remaining
        // top-level clauses joined back as the bracketed list text.
        let variables: String
        if kind == .hessian {
            variables = ""
        } else {
            variables = parts.dropFirst().joined(separator: ", ").trimmedShim
        }

        return VectorCalculusFormulaIR(
            kind: kind, expression: expression, variables: variables)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty
            ? kind.command
            : "\(kind.command) \(trimmedExpression)"

        if kind != .hessian {
            let vars = variables.trimmedShim
            if !vars.isEmpty {
                input += ", \(vars)"
            }
        }

        return input
    }
}
