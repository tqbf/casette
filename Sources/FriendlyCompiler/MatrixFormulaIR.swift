import Foundation

/// The small user-editable shape behind Casette's matrix-shaped formula bars:
/// `matrix`, `vector`, `det`, `inverse`, `transpose`, `rank`, `rref`,
/// `eigenvalues`, and `eigenvectors`. Each wraps a single payload — the matrix
/// literal, a variable name, an expression, or a `#ROW` tape reference.
///
/// Like the other formula IRs, this renders back to friendly input, not Sage.
/// App-specific source forms such as `#14` tape references remain intact here;
/// Casette expands them at its compile boundary before calling the compiler.
public struct MatrixFormulaIR: Equatable, Sendable {
    /// Which matrix-shaped command this bar represents. The cases mirror the
    /// matching `FriendlyCompiler.Keyword`s so the bar's chip and lowering agree.
    public enum Kind: Equatable, Sendable, CaseIterable {
        case matrix
        case vector
        case det
        case inverse
        case transpose
        case rank
        case rref
        case eigenvalues
        case eigenvectors

        /// The canonical friendly command word (also the rendered prefix).
        public var command: String {
            switch self {
            case .matrix: return "matrix"
            case .vector: return "vector"
            case .det: return "det"
            case .inverse: return "inverse"
            case .transpose: return "transpose"
            case .rank: return "rank"
            case .rref: return "rref"
            case .eigenvalues: return "eigenvalues"
            case .eigenvectors: return "eigenvectors"
            }
        }

        /// The uppercase chip title shown in the formula bar.
        public var title: String {
            switch self {
            case .matrix: return "MATRIX"
            case .vector: return "VECTOR"
            case .det: return "DET"
            case .inverse: return "INVERSE"
            case .transpose: return "TRANSPOSE"
            case .rank: return "RANK"
            case .rref: return "RREF"
            case .eigenvalues: return "EIGENVALUES"
            case .eigenvectors: return "EIGENVECTORS"
            }
        }

        fileprivate init?(_ keyword: FriendlyCompiler.Keyword) {
            switch keyword {
            case .matrix: self = .matrix
            case .vector: self = .vector
            case .det: self = .det
            case .inverse: self = .inverse
            case .transpose: self = .transpose
            case .rank: self = .rank
            case .rref: self = .rref
            case .eigenvalues: self = .eigenvalues
            case .eigenvectors: self = .eigenvectors
            default: return nil
            }
        }
    }

    public var kind: Kind
    public var payload: String

    public init(kind: Kind, payload: String) {
        self.kind = kind
        self.payload = payload
    }

    public static func parse(_ rawInput: String) -> MatrixFormulaIR? {
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim
        guard let command = FriendlyCompiler.leadingCommand(input),
              let kind = Kind(command.keyword)
        else { return nil }

        let payload = String(input.dropFirst(command.matchedPrefix.count)).trimmedShim
        return MatrixFormulaIR(kind: kind, payload: payload)
    }

    public var friendlyInput: String {
        let trimmedPayload = payload.trimmedShim
        return trimmedPayload.isEmpty
            ? kind.command
            : "\(kind.command) \(trimmedPayload)"
    }
}
