import Foundation

/// The small user-editable shape behind Casette's derivative formula bar.
///
/// `derivative EXPR` optionally takes a trailing `, N` order (all digits, comma
/// form only) and a trailing `wrt v` clause. Like the other formula IRs, this
/// renders back to friendly input, not Sage; `#14` tape references stay intact
/// until Casette's compile boundary.
public struct DerivativeFormulaIR: Equatable, Sendable {
    public var expression: String
    public var variable: String
    /// The derivative order — a digit string (e.g. "2"), or nil for first order.
    public var order: String?
    public var hasExplicitVariable: Bool

    public init(
        expression: String,
        variable: String = "",
        order: String? = nil,
        hasExplicitVariable: Bool = false
    ) {
        self.expression = expression
        self.variable = variable
        self.order = order
        self.hasExplicitVariable = hasExplicitVariable
    }

    public static func parse(_ rawInput: String) -> DerivativeFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .derivative
        else { return nil }

        // Peel the trailing `wrt v` clause first (the same order the lowering uses).
        var body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        var explicitVariable: String?
        if let wrt = FriendlyCompiler.trailingClause(in: body, keyword: "wrt") {
            explicitVariable = body[wrt.valueRange].trimmedShim
            body = String(body[body.startIndex..<wrt.clauseStart])
                .droppingFormulaTrailingComma
                .trimmedShim
        }

        // Optional trailing order: split on top-level commas; an all-digits last
        // part is the order, the remainder re-joins as the expression.
        var order: String?
        let parts = Scanner.splitTopLevelCommas(body)
        if parts.count >= 2,
           let last = parts.last?.trimmedShim,
           !last.isEmpty, last.allSatisfy({ $0.isNumber }) {
            order = last
            body = parts.dropLast().joined(separator: ",").trimmedShim
        }

        let expression = body.trimmedShim
        let freeVariables = Variables.freeVariables(in: expression)
        let inferredVariable = freeVariables.count == 1 ? freeVariables[0] : ""
        let variable = explicitVariable ?? inferredVariable

        return DerivativeFormulaIR(
            expression: expression,
            variable: variable,
            order: order,
            hasExplicitVariable: explicitVariable != nil)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? "derivative" : "derivative \(trimmedExpression)"

        if let order = order?.trimmedShim, !order.isEmpty {
            input += ", \(order)"
        }
        if hasExplicitVariable, !variable.trimmedShim.isEmpty {
            input += " wrt \(variable.trimmedShim)"
        }

        return input
    }
}

extension String {
    fileprivate var droppingFormulaTrailingComma: String {
        let trimmed = trimmedShim
        guard trimmed.last == "," else { return trimmed }
        return String(trimmed.dropLast())
    }
}
