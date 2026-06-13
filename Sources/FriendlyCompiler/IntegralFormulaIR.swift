import Foundation

/// The small user-editable shape behind Casette's integral formula bar.
///
/// This renders back to friendly input, not Sage. App-specific source forms
/// such as `#14` tape references remain intact here; Casette expands them at
/// its compile boundary before calling the friendly compiler.
public struct IntegralFormulaIR: Equatable, Sendable {
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

    public static func parse(_ rawInput: String) -> IntegralFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .integral
        else { return nil }

        var body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        var explicitVariable: String?
        if let wrt = FriendlyCompiler.trailingClause(in: body, keyword: "wrt") {
            explicitVariable = body[wrt.valueRange].trimmedShim
            body = String(body[body.startIndex..<wrt.clauseStart])
                .droppingFormulaTrailingComma
                .trimmedShim
        }

        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""
        // Tolerant: a half-typed range keeps whatever the user typed (e.g.
        // `x=0..` keeps the lower bound) instead of being dropped by the strict
        // compiler-grade parser.
        let range = parts.dropFirst().compactMap { FriendlyCompiler.parsePartialRange($0) }.first
        let freeVariables = Variables.freeVariables(in: expression)
        let inferredVariable = freeVariables.count == 1 ? freeVariables[0] : ""
        let rangeVariable = range.map { $0.variable.isEmpty ? nil : $0.variable } ?? nil
        let variable = rangeVariable ?? explicitVariable ?? inferredVariable

        return IntegralFormulaIR(
            expression: expression,
            variable: variable,
            lowerBound: range?.lower,
            upperBound: range?.upper,
            hasExplicitVariable: explicitVariable != nil || range != nil)
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? "integral" : "integral \(trimmedExpression)"

        if lowerBound != nil || upperBound != nil {
            let v = variable.trimmedShim.isEmpty ? "x" : variable.trimmedShim
            input += ", \(v)=\(lowerBound?.trimmedShim ?? "")..\(upperBound?.trimmedShim ?? "")"
        } else if hasExplicitVariable, !variable.trimmedShim.isEmpty {
            input += ", wrt \(variable.trimmedShim)"
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
