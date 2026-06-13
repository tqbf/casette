import Foundation

/// The small user-editable shape behind Casette's two-argument number-theory
/// bars: `choose`, `gcd`, and `lcm`. Each takes a first and second clause
/// (`choose 10, 3`). For `gcd`/`lcm` the second clause re-joins any extra
/// comma clauses verbatim, so a three-value list (`gcd 12, 18, 24`) round-trips
/// without loss.
///
/// Like the other formula IRs this renders back to friendly input, not Sage;
/// `#14` tape references stay intact until the app's compile boundary.
public struct BinaryFormulaIR: Equatable, Sendable {
    /// Which two-argument command this bar represents.
    public enum Kind: Equatable, Sendable, CaseIterable {
        case choose
        case gcd
        case lcm

        /// The canonical friendly command word (also the rendered prefix).
        public var command: String {
            switch self {
            case .choose: return "choose"
            case .gcd: return "gcd"
            case .lcm: return "lcm"
            }
        }

        /// The uppercase chip title shown in the formula bar.
        public var title: String {
            switch self {
            case .choose: return "CHOOSE"
            case .gcd: return "GCD"
            case .lcm: return "LCM"
            }
        }

        fileprivate init?(_ keyword: FriendlyCompiler.Keyword) {
            switch keyword {
            case .choose: self = .choose
            case .gcd: self = .gcd
            case .lcm: self = .lcm
            default: return nil
            }
        }
    }

    public var kind: Kind
    public var first: String
    public var second: String

    public init(kind: Kind, first: String = "", second: String = "") {
        self.kind = kind
        self.first = first
        self.second = second
    }

    public static func parse(_ rawInput: String) -> BinaryFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              let kind = Kind(command.keyword)
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body).map { $0.trimmedShim }
        let first = parts.first ?? ""
        // Extra clauses re-join into `second` verbatim so nothing is lost.
        let second = parts.dropFirst().joined(separator: ", ")

        return BinaryFormulaIR(kind: kind, first: first, second: second)
    }

    public var friendlyInput: String {
        let trimmedFirst = first.trimmedShim
        let trimmedSecond = second.trimmedShim
        if trimmedFirst.isEmpty, trimmedSecond.isEmpty {
            return kind.command
        }
        var input = "\(kind.command) \(trimmedFirst)"
        if !trimmedSecond.isEmpty {
            input += ", \(trimmedSecond)"
        }
        return input
    }
}
