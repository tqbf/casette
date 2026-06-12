import Foundation

/// The small user-editable shape behind Casette's plot formula bar.
///
/// `plot EXPR, VAR=LO..HI`. The range (`lower .. upper`) is ONE optional
/// semantic group, mirroring `IntegralFormulaIR`'s bounds: when the bounds are
/// present but the variable is empty, the variable defaults to `x`. Parsing is
/// tolerant — a half-typed range leaves the bound fields empty so the bar stays
/// visible while the user types. Like the other formula IRs this renders back
/// to friendly input, not Sage; `#14` tape references stay intact until the
/// app's compile boundary.
public struct PlotFormulaIR: Equatable, Sendable {
    public var expression: String
    public var variable: String
    public var lowerBound: String?
    public var upperBound: String?
    public var hasExplicitVariable: Bool

    public init(
        expression: String,
        variable: String = "",
        lowerBound: String? = nil,
        upperBound: String? = nil,
        hasExplicitVariable: Bool = false
    ) {
        self.expression = expression
        self.variable = variable
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.hasExplicitVariable = hasExplicitVariable
    }

    public static func parse(_ rawInput: String) -> PlotFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .plot
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""

        // Tolerate a missing/malformed range by leaving the bound fields empty —
        // the bar still shows so the user can fill it in.
        let range = parts.dropFirst().compactMap { FriendlyCompiler.parseRange($0) }.first
        let freeVariables = Variables.freeVariables(in: expression)
        let inferredVariable = freeVariables.count == 1 ? freeVariables[0] : ""
        let variable = range?.variable ?? inferredVariable

        return PlotFormulaIR(
            expression: expression,
            variable: variable,
            lowerBound: range?.lower,
            upperBound: range?.upper,
            hasExplicitVariable: range != nil)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? "plot" : "plot \(trimmedExpression)"

        if lowerBound != nil || upperBound != nil {
            let v = variable.trimmedShim.isEmpty ? "x" : variable.trimmedShim
            input += ", \(v)=\(lowerBound?.trimmedShim ?? "")..\(upperBound?.trimmedShim ?? "")"
        }

        return input
    }
}
