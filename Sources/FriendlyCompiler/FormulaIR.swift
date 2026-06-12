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

    public static func parse(_ draft: String) -> FormulaIR? {
        if let ir = IntegralFormulaIR.parse(draft) { return .integral(ir) }
        return nil
    }

    public var friendlyInput: String {
        switch self {
        case let .integral(ir): return ir.friendlyInput
        }
    }
}
