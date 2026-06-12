import Foundation

/// The small user-editable shape behind Casette's taylor formula bar.
///
/// Canonical grammar `taylor EXPR, VAR=PT, order=N`. Parsing is tolerant: a
/// half-typed form leaves later fields empty so the bar appears as the user
/// types. Like the other formula IRs this renders back to friendly input, not
/// Sage; `#14` tape references stay intact until the app's compile boundary.
public struct TaylorFormulaIR: Equatable, Sendable {
    public var expression: String
    public var variable: String
    public var center: String
    public var order: String

    public init(
        expression: String,
        variable: String = "",
        center: String = "",
        order: String = ""
    ) {
        self.expression = expression
        self.variable = variable
        self.center = center
        self.order = order
    }

    public static func parse(_ rawInput: String) -> TaylorFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .taylor
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""

        // Second clause: `var=pt` (an assignment, not a range — no `..`).
        var variable = ""
        var center = ""
        if parts.count >= 2 {
            let clause = parts[1].trimmedShim
            if let eq = clause.firstIndex(of: "="), !clause.contains("..") {
                variable = String(clause[clause.startIndex..<eq]).trimmedShim
                center = String(clause[clause.index(after: eq)...]).trimmedShim
            } else {
                // No `=` yet: show what's typed in the var token.
                variable = clause
            }
        }

        // Third clause: `order=N`.
        var order = ""
        if parts.count >= 3 {
            let clause = parts[2].trimmedShim
            if let eq = clause.firstIndex(of: "="),
               clause[clause.startIndex..<eq].trimmedShim.lowercased() == "order" {
                order = String(clause[clause.index(after: eq)...]).trimmedShim
            } else {
                order = clause
            }
        }

        return TaylorFormulaIR(
            expression: expression,
            variable: variable,
            center: center,
            order: order)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? "taylor" : "taylor \(trimmedExpression)"

        let v = variable.trimmedShim
        let c = center.trimmedShim
        let o = order.trimmedShim
        // The `var=pt` clause appears once anything past the expression is set —
        // including when only the order is set, so the clause positions stay valid
        // (the order is always the THIRD comma part).
        if !v.isEmpty || !c.isEmpty || !o.isEmpty {
            input += ", \(v)=\(c)"
        }
        if !o.isEmpty {
            input += ", order=\(o)"
        }

        return input
    }
}
