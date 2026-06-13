import Foundation

/// The small user-editable shape behind Casette's `sum` and `product` formula
/// bars. Both share one indexed-range grammar (`sum EXPR, K=LO..HI`), so one IR
/// covers both kinds — the way `UnaryFormulaIR` covers expand/factor/simplify.
///
/// The bounds (`lower .. upper`) are ONE semantic group, defaulting the index
/// variable to `k` when bounds are present but the variable is empty (mirroring
/// `IntegralFormulaIR`'s defaulting of `x`). Like the other formula IRs this
/// renders back to friendly input, not Sage; `#14` tape references stay intact
/// until the app's compile boundary.
public struct SeriesRangeFormulaIR: Equatable, Sendable {
    /// Which indexed-range command this bar represents. The cases mirror the
    /// matching `FriendlyCompiler.Keyword`s so the chip and lowering agree.
    public enum Kind: Equatable, Sendable, CaseIterable {
        case sum
        case product

        /// The canonical friendly command word (also the rendered prefix).
        public var command: String {
            switch self {
            case .sum: return "sum"
            case .product: return "product"
            }
        }

        /// The uppercase chip title shown in the formula bar.
        public var title: String {
            switch self {
            case .sum: return "SUM"
            case .product: return "PRODUCT"
            }
        }

        fileprivate init?(_ keyword: FriendlyCompiler.Keyword) {
            switch keyword {
            case .sum: self = .sum
            case .product: self = .product
            default: return nil
            }
        }
    }

    public var kind: Kind
    public var expression: String
    public var indexVariable: String
    public var lowerBound: String
    public var upperBound: String

    public init(
        kind: Kind,
        expression: String,
        indexVariable: String = "",
        lowerBound: String = "",
        upperBound: String = ""
    ) {
        self.kind = kind
        self.expression = expression
        self.indexVariable = indexVariable
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    public static func parse(_ rawInput: String) -> SeriesRangeFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              let kind = Kind(command.keyword)
        else { return nil }

        let body = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        let parts = Scanner.splitTopLevelCommas(body)
        let expression = parts.first?.trimmedShim ?? ""

        // Tolerate a half-typed range without losing typed bounds: `k=1..` keeps
        // the lower bound rather than dropping the whole range.
        let range = parts.dropFirst().compactMap { FriendlyCompiler.parsePartialRange($0) }.first

        return SeriesRangeFormulaIR(
            kind: kind,
            expression: expression,
            indexVariable: range?.variable ?? "",
            lowerBound: range?.lower ?? "",
            upperBound: range?.upper ?? "")
    }

    public var friendlyInput: String {
        let trimmedExpression = expression.trimmedShim
        var input = trimmedExpression.isEmpty ? kind.command : "\(kind.command) \(trimmedExpression)"

        let v = indexVariable.trimmedShim
        let lo = lowerBound.trimmedShim
        let hi = upperBound.trimmedShim
        if !v.isEmpty || !lo.isEmpty || !hi.isEmpty {
            let index = v.isEmpty ? "k" : v
            input += ", \(index)=\(lo)..\(hi)"
        }

        return input
    }
}
