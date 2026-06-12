import Foundation

/// The small user-editable shape behind Casette's implicit-plot formula bar.
///
/// `implicit_plot EQ, x=LO..HI, y=LO..HI`. The equation is kept VERBATIM as one
/// token (`LHS = RHS`, `LHS == RHS`, or a bare expression — the compile boundary
/// normalizes a bare expression to `== 0`). Each axis range (`lower .. upper`)
/// is ONE semantic group, defaulting the variable to `x`/`y` respectively when
/// the bounds are present but the variable is empty. Parsing is tolerant — a
/// half-typed range leaves the affected bound fields empty so the bar stays
/// visible while the user types. Like the other formula IRs this renders back to
/// friendly input, not Sage; `#14` tape references stay intact until the app's
/// compile boundary.
public struct ImplicitPlotFormulaIR: Equatable, Sendable {
    public var equation: String
    public var xVariable: String
    public var xLower: String?
    public var xUpper: String?
    public var yVariable: String
    public var yLower: String?
    public var yUpper: String?

    public init(
        equation: String,
        xVariable: String = "",
        xLower: String? = nil,
        xUpper: String? = nil,
        yVariable: String = "",
        yLower: String? = nil,
        yUpper: String? = nil
    ) {
        self.equation = equation
        self.xVariable = xVariable
        self.xLower = xLower
        self.xUpper = xUpper
        self.yVariable = yVariable
        self.yLower = yLower
        self.yUpper = yUpper
    }

    public static func parse(_ rawInput: String) -> ImplicitPlotFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .implicitPlot
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let equation = parts.first?.trimmedShim ?? ""

        // Tolerate missing/malformed ranges by leaving the bound fields empty.
        // The two ranges are positional: the first parseable range is x, the
        // second is y.
        let ranges = parts.dropFirst().map { FriendlyCompiler.parseRange($0) }
        let xRange = ranges.count >= 1 ? ranges[0] : nil
        let yRange = ranges.count >= 2 ? ranges[1] : nil

        return ImplicitPlotFormulaIR(
            equation: equation,
            xVariable: xRange?.variable ?? "",
            xLower: xRange?.lower,
            xUpper: xRange?.upper,
            yVariable: yRange?.variable ?? "",
            yLower: yRange?.lower,
            yUpper: yRange?.upper)
    }

    /// Whether the x-axis range group carries any content.
    private var xHasContent: Bool {
        !xVariable.trimmedShim.isEmpty || xLower != nil || xUpper != nil
    }

    /// Whether the y-axis range group carries any content.
    private var yHasContent: Bool {
        !yVariable.trimmedShim.isEmpty || yLower != nil || yUpper != nil
    }

    public var friendlyInput: String {
        let trimmedEquation = equation.trimmedShim
        var input = trimmedEquation.isEmpty ? "implicit_plot" : "implicit_plot \(trimmedEquation)"

        // Clause positions matter: if either axis group has content, render BOTH
        // so the x-range stays the first clause and y stays the second.
        if xHasContent || yHasContent {
            let xVar = xVariable.trimmedShim.isEmpty ? "x" : xVariable.trimmedShim
            let yVar = yVariable.trimmedShim.isEmpty ? "y" : yVariable.trimmedShim
            input += ", \(xVar)=\(xLower?.trimmedShim ?? "")..\(xUpper?.trimmedShim ?? "")"
            input += ", \(yVar)=\(yLower?.trimmedShim ?? "")..\(yUpper?.trimmedShim ?? "")"
        }

        return input
    }
}
