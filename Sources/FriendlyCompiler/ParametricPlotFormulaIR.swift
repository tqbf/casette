import Foundation

/// The small user-editable shape behind Casette's parametric-plot formula bar.
///
/// `parametric_plot (XEXPR, YEXPR), VAR=LO..HI`. The coordinate pair is always
/// rendered parenthesized; the range (`lower .. upper`) is ONE optional semantic
/// group, defaulting the variable to `t` when the bounds are present but the
/// variable is empty (mirroring `IntegralFormulaIR`'s defaulting of `x`).
/// Parsing is tolerant — a half-typed pair or range leaves the affected fields
/// empty so the bar stays visible while the user types. Like the other formula
/// IRs this renders back to friendly input, not Sage; `#14` tape references stay
/// intact until the app's compile boundary.
public struct ParametricPlotFormulaIR: Equatable, Sendable {
    public var xExpression: String
    public var yExpression: String
    public var variable: String
    public var lowerBound: String?
    public var upperBound: String?
    public var hasExplicitVariable: Bool

    public init(
        xExpression: String,
        yExpression: String = "",
        variable: String = "",
        lowerBound: String? = nil,
        upperBound: String? = nil,
        hasExplicitVariable: Bool = false
    ) {
        self.xExpression = xExpression
        self.yExpression = yExpression
        self.variable = variable
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.hasExplicitVariable = hasExplicitVariable
    }

    public static func parse(_ rawInput: String) -> ParametricPlotFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .parametricPlot
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        // splitTopLevelCommas respects parens, so the coordinate pair stays one
        // unit: parts[0] = "(X, Y)", parts[1] = the range clause.
        let parts = Scanner.splitTopLevelCommas(body)
        let pairText = parts.first?.trimmedShim ?? ""

        // Pull the two coordinate expressions out of the parenthesized pair.
        // Tolerate a half-typed pair (missing closing paren, only one piece) by
        // leaving the missing field empty.
        var xExpression = ""
        var yExpression = ""
        if pairText.hasPrefix("(") {
            var inner = String(pairText.dropFirst())
            if inner.hasSuffix(")") { inner = String(inner.dropLast()) }
            let coords = Scanner.splitTopLevelCommas(inner)
            xExpression = coords.first?.trimmedShim ?? ""
            if coords.count >= 2 { yExpression = coords[1].trimmedShim }
        } else {
            // No parens yet: treat the whole first part as the nascent x(t).
            xExpression = pairText
        }

        let range = parts.dropFirst().compactMap { FriendlyCompiler.parseRange($0) }.first

        return ParametricPlotFormulaIR(
            xExpression: xExpression,
            yExpression: yExpression,
            variable: range?.variable ?? "",
            lowerBound: range?.lower,
            upperBound: range?.upper,
            hasExplicitVariable: range != nil)
    }

    public var friendlyInput: String {
        let x = xExpression.trimmedShim
        let y = yExpression.trimmedShim
        var input = "parametric_plot (\(x), \(y))"

        let lo = lowerBound?.trimmedShim ?? ""
        let hi = upperBound?.trimmedShim ?? ""
        let v = variable.trimmedShim
        if lowerBound != nil || upperBound != nil || !v.isEmpty {
            let index = v.isEmpty ? "t" : v
            input += ", \(index)=\(lo)..\(hi)"
        }

        return input
    }
}
