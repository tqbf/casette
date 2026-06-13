import Foundation

/// The small user-editable shape behind Casette's `numeric` formula bar.
///
/// Grammar `numeric EXPR` or `numeric EXPR, DIGITS`. The optional digit count
/// is one group (defaulting empty). Like the other formula IRs this renders
/// back to friendly input, not Sage; `#14` tape references stay intact until
/// the app's compile boundary.
public struct NumericFormulaIR: Equatable, Sendable {
    public var expression: String
    /// The optional digit-count text, or empty.
    public var digits: String

    public init(expression: String, digits: String = "") {
        self.expression = expression
        self.digits = digits
    }

    public static func parse(_ rawInput: String) -> NumericFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .numeric
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""
        let digits = parts.dropFirst().first?.trimmedShim ?? ""

        return NumericFormulaIR(expression: expression, digits: digits)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? "numeric" : "numeric \(trimmedExpression)"

        let d = digits.trimmedShim
        if !d.isEmpty {
            input += ", \(d)"
        }

        return input
    }
}
