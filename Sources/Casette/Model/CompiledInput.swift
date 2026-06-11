import Foundation

/// The compiled form of one user input: the raw text the user typed and the
/// Sage that will actually be evaluated — the FRIENDLY-COMPILER.md
/// input-vs-sage split that `SessionRow` stores as `input` / `sage`.
///
/// V1.4 produces these from the real `FriendlyCompiler` (`.success` →
/// `.friendly`, `.bypass` → `.bypass`, with `requiredVariables` driving the
/// `var('V')` preludes). Until then every input is honestly treated as a
/// raw-Sage bypass via `CompiledInput.bypass(_:)`.
struct CompiledInput: Equatable, Sendable {
    /// How the Sage was produced.
    enum Origin: Equatable, Sendable {
        /// A friendly command form was compiled to Sage (V1.4).
        case friendly
        /// The input is raw Sage, passed through untouched (the bypass rule).
        case bypass
    }

    /// The raw text the user typed (`factor x^4 - 1`).
    var raw: String
    /// The Sage to evaluate (`factor(x^4 - 1)`); equal to `raw` for a bypass.
    var sage: String
    /// Free variables the compiler says need `var('V')` preludes (V0.7 policy:
    /// the compiler reports, never injects). Empty for a bypass.
    var requiredVariables: [String]
    var origin: Origin

    /// Raw Sage passed through untouched — the only path until V1.4 wires the
    /// compiler in.
    static func bypass(_ raw: String) -> CompiledInput {
        CompiledInput(raw: raw, sage: raw, requiredVariables: [], origin: .bypass)
    }
}
