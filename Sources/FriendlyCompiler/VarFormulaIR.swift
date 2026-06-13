import Foundation

/// The small user-editable shape behind Casette's `var` formula bar: a
/// space/comma list of symbolic names to declare (`var x y z`).
///
/// Like the other formula IRs this renders back to friendly input, not Sage.
/// A draft whose payload begins with `=` is an assignment to a variable named
/// `var` (`var = 3`), NOT the declaration command, so `parse` declines it.
public struct VarFormulaIR: Equatable, Sendable {
    /// The verbatim names text (`x y z`), or empty for a bare `var`.
    public var names: String

    public init(names: String = "") {
        self.names = names
    }

    public static func parse(_ rawInput: String) -> VarFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              command.keyword == .varDeclaration
        else { return nil }

        let names = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        // `var = 3` is an assignment, not the declaration command.
        guard names.first != "=" else { return nil }

        return VarFormulaIR(names: names)
    }

    public var friendlyInput: String {
        let trimmed = names.trimmedShim
        return trimmed.isEmpty ? "var" : "var \(trimmed)"
    }
}
