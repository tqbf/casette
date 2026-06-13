import Foundation

/// The small user-editable shape behind Casette's `assume` formula bar: a
/// single condition token (`x > 0`). Both grammar forms — a comparison
/// (`assume x > 0`) and a property (`assume x real`) — ride in the one token,
/// so the bar edits the assumption as one verbatim string.
///
/// Like the other formula IRs this renders back to friendly input, not Sage;
/// `#14` tape references stay intact until the app's compile boundary.
public struct AssumeFormulaIR: Equatable, Sendable {
    /// The verbatim condition text (`x > 0` or `x real`).
    public var condition: String

    public init(condition: String = "") {
        self.condition = condition
    }

    public static func parse(_ rawInput: String) -> AssumeFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .assume
        else { return nil }

        let condition = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        return AssumeFormulaIR(condition: condition)
    }

    public var friendlyInput: String {
        let trimmed = condition.trimmedShim
        return trimmed.isEmpty ? "assume" : "assume \(trimmed)"
    }
}
