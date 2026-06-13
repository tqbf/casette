import Foundation

/// The small user-editable shape behind Casette's `subs` formula bar.
///
/// Grammar `subs EXPR, V1=VAL1, V2=VAL2, ...`. The bindings are ONE semantic
/// group — the raw comma-joined bindings text (`x=3, y=4`), NOT individual
/// chips — so the bar edits the substitution as a single token, the way the
/// integral bar treats its bounds as one group. Like the other formula IRs
/// this renders back to friendly input, not Sage; `#14` tape references stay
/// intact until the app's compile boundary.
public struct SubsFormulaIR: Equatable, Sendable {
    public var expression: String
    /// The raw comma-joined bindings text (`x=3, y=4`), or empty.
    public var bindings: String

    public init(expression: String, bindings: String = "") {
        self.expression = expression
        self.bindings = bindings
    }

    public static func parse(_ rawInput: String) -> SubsFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .subs
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""
        let bindings = parts.dropFirst()
            .map { $0.trimmedShim }
            .joined(separator: ", ")

        return SubsFormulaIR(expression: expression, bindings: bindings)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? "subs" : "subs \(trimmedExpression)"

        let b = bindings.trimmedShim
        if !b.isEmpty {
            input += ", \(b)"
        }

        return input
    }
}
