import Foundation

/// The small user-editable shape behind Casette's solve formula bar.
///
/// The equation is kept VERBATIM as one token (`LHS = RHS`, or a bare
/// expression) — solve's friendly grammar uses a trailing ` for v` clause to
/// name the variable, not a comma, so there is nothing to split here. Like the
/// other formula IRs this renders back to friendly input, not Sage; `#14` tape
/// references stay intact until Casette's compile boundary.
public struct SolveFormulaIR: Equatable, Sendable {
    public var equation: String
    public var variable: String
    public var hasExplicitVariable: Bool

    public init(
        equation: String,
        variable: String = "",
        hasExplicitVariable: Bool = false
    ) {
        self.equation = equation
        self.variable = variable
        self.hasExplicitVariable = hasExplicitVariable
    }

    public static func parse(_ rawInput: String) -> SolveFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .solve
        else { return nil }

        var body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        var explicitVariable: String?
        if let forClause = FriendlyCompiler.trailingClause(in: body, keyword: "for") {
            explicitVariable = body[forClause.valueRange].trimmedShim
            body = String(body[body.startIndex..<forClause.clauseStart]).trimmedShim
        }

        let equation = body.trimmedShim
        let freeVariables = Variables.freeVariables(in: equation)
        let inferredVariable = freeVariables.count == 1 ? freeVariables[0] : ""
        let variable = explicitVariable ?? inferredVariable

        return SolveFormulaIR(
            equation: equation,
            variable: variable,
            hasExplicitVariable: explicitVariable != nil)
    }

    public var friendlyInput: String {
        let trimmedEquation = equation.trimmedShim
        var input = trimmedEquation.isEmpty ? "solve" : "solve \(trimmedEquation)"

        if hasExplicitVariable, !variable.trimmedShim.isEmpty {
            input += " for \(variable.trimmedShim)"
        }

        return input
    }
}
