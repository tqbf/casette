import Foundation

/// The small user-editable shape behind Casette's single-expression transform
/// bars: `expand`, `factor`, and `simplify`. Each wraps one expression payload.
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

        /// The canonical friendly command word (also the rendered prefix).
        public var command: String {
            switch self {
            case .expand: return "expand"
            case .factor: return "factor"
            case .simplify: return "simplify"
            }
        }

        /// The uppercase chip title shown in the formula bar.
        public var title: String {
            switch self {
            case .expand: return "EXPAND"
            case .factor: return "FACTOR"
            case .simplify: return "SIMPLIFY"
            }
        }

        fileprivate init?(_ keyword: FriendlyCompiler.Keyword) {
            switch keyword {
            case .expand: self = .expand
            case .factor: self = .factor
            case .simplify: self = .simplify
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
