import Foundation

/// The small user-editable shape behind Casette's single-expression transform
/// bars: `expand`, `factor`, `simplify`, and `latex`. Each wraps one
/// expression payload.
///
/// Like the other formula IRs, this renders back to friendly input, not Sage.
/// App-specific source forms such as `#14` tape references remain intact here;
/// Casette expands them at its compile boundary before calling the compiler.
public struct UnaryFormulaIR: Equatable, Sendable {
    /// Which single-expression command this bar represents. The cases mirror the
    /// matching `FriendlyCompiler.Keyword`s so the bar's chip and lowering agree.
    public enum Kind: Equatable, Sendable, CaseIterable {
        case expand
        case factor
        case simplify
        case latex
        case factorial
        case isPrime
        case factorInteger
        case mean

        /// The canonical friendly command word (also the rendered prefix).
        public var command: String {
            switch self {
            case .expand: return "expand"
            case .factor: return "factor"
            case .simplify: return "simplify"
            case .latex: return "latex"
            case .factorial: return "factorial"
            case .isPrime: return "is_prime"
            case .factorInteger: return "factor_integer"
            case .mean: return "mean"
            }
        }

        /// The uppercase chip title shown in the formula bar.
        public var title: String {
            switch self {
            case .expand: return "EXPAND"
            case .factor: return "FACTOR"
            case .simplify: return "SIMPLIFY"
            case .latex: return "LATEX"
            case .factorial: return "FACTORIAL"
            case .isPrime: return "IS PRIME"
            case .factorInteger: return "FACTOR INTEGER"
            case .mean: return "MEAN"
            }
        }

        fileprivate init?(_ keyword: FriendlyCompiler.Keyword) {
            switch keyword {
            case .expand: self = .expand
            case .factor: self = .factor
            case .simplify: self = .simplify
            case .latex: self = .latex
            case .factorial: self = .factorial
            case .isPrime: self = .isPrime
            case .factorInteger: self = .factorInteger
            case .mean: self = .mean
            default: return nil
            }
        }
    }

    public var keyword: Kind
    public var expression: String

    public init(keyword: Kind, expression: String) {
        self.keyword = keyword
        self.expression = expression
    }

    public static func parse(_ rawInput: String) -> UnaryFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              let kind = Kind(command.keyword)
        else { return nil }

        let expression = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        return UnaryFormulaIR(keyword: kind, expression: expression)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        return trimmedExpression.isEmpty
            ? keyword.command
            : "\(keyword.command) \(trimmedExpression)"
    }
}
