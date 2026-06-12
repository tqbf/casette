import Foundation

/// The dispatch point for Casette's completion UIs: one case per formula
/// family, each wrapping that family's small typed IR (docs/COMPLETION-UI.md
/// Extension Rule). `parse` tries each family against the draft; families
/// are keyed by their leading friendly command, so at most one matches.
///
/// Like the member IRs, this renders back to friendly input, never Sage.
/// `#ROW` tape references stay intact until the app's compile boundary.
public enum FormulaIR: Equatable, Sendable {
    case integral(IntegralFormulaIR)
    case unary(UnaryFormulaIR)
    case solve(SolveFormulaIR)
    case derivative(DerivativeFormulaIR)
    case limit(LimitFormulaIR)
    case taylor(TaylorFormulaIR)
    case seriesRange(SeriesRangeFormulaIR)

    public static func parse(_ draft: String) -> FormulaIR? {
        // Families are keyed by disjoint leading commands, so order is cosmetic.
        if let ir = IntegralFormulaIR.parse(draft) { return .integral(ir) }
        if let ir = UnaryFormulaIR.parse(draft) { return .unary(ir) }
        if let ir = SolveFormulaIR.parse(draft) { return .solve(ir) }
        if let ir = DerivativeFormulaIR.parse(draft) { return .derivative(ir) }
        if let ir = LimitFormulaIR.parse(draft) { return .limit(ir) }
        if let ir = TaylorFormulaIR.parse(draft) { return .taylor(ir) }
        if let ir = SeriesRangeFormulaIR.parse(draft) { return .seriesRange(ir) }
        return nil
    }

    public var friendlyInput: String {
        switch self {
        case let .integral(ir): return ir.friendlyInput
        case let .unary(ir): return ir.friendlyInput
        case let .solve(ir): return ir.friendlyInput
        case let .derivative(ir): return ir.friendlyInput
        case let .limit(ir): return ir.friendlyInput
        case let .taylor(ir): return ir.friendlyInput
        case let .seriesRange(ir): return ir.friendlyInput
        }
    }
}
