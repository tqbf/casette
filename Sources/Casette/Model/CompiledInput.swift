import Foundation
import FriendlyCompiler

/// The compiled form of one user input: the raw text the user typed and the
/// Sage that will actually be evaluated — the FRIENDLY-COMPILER.md
/// input-vs-sage split that `SessionRow` stores as `input` / `sage`.
///
/// V1.4: produced by the real `FriendlyCompiler` via `compile(_:)` —
/// `.success` → `.friendly` (with `requiredVariables` driving the `var('V')`
/// preludes), `.bypass` → `.bypass`. Compile errors and ambiguity never
/// become a `CompiledInput`; they surface through `Outcome` so the UI can
/// show them without submitting a row.
struct CompiledInput: Equatable, Sendable {
    /// How the Sage was produced.
    enum Origin: Equatable, Sendable {
        /// A friendly command form was compiled to Sage.
        case friendly
        /// The input is raw Sage, passed through untouched (the bypass rule).
        case bypass
    }

    /// What compiling an input yields: something submittable, or a reason
    /// it isn't (inline error / ambiguity choice). The view-facing shape of
    /// the frozen `CompileResult`.
    enum Outcome: Equatable {
        case ready(CompiledInput)
        case error(CompileError)
        case ambiguous(candidates: [String])
    }

    /// The raw text the user typed (`factor x^4 - 1`).
    var raw: String
    /// The Sage to evaluate (`factor(x^4 - 1)`); equal to `raw` for a bypass.
    /// This is what the row displays as "Generated Sage" — preludes are
    /// session plumbing and deliberately NOT part of it (FRIENDLY-COMPILER.md
    /// variable policy: the generated Sage stays a single clean expression).
    var sage: String
    /// Free variables the compiler says need `var('V')` preludes (V0.7 policy:
    /// the compiler reports, never injects). Empty for a bypass.
    var requiredVariables: [String]
    var origin: Origin

    /// The `var('V')` declarations to send BEFORE `sage` (the frozen V1.4
    /// prelude policy: the worker's star-import predefines only `x`, so every
    /// required variable is declared; re-declaring is idempotent and cheap).
    var preludes: [String] {
        requiredVariables.map { "var('\($0)')" }
    }

    /// Compiles one submission through the lifted `FriendlyCompiler`.
    ///
    /// Multiline input is raw Sage by definition: the friendly forms are
    /// single-line commands, and the V0.7 compiler (written for one line)
    /// flattens newlines — which would corrupt newline-sensitive raw Sage
    /// statements. So anything containing a newline bypasses untouched
    /// (except smart-quote normalization, which applies to everything —
    /// see `normalizingSmartQuotes`).
    static func compile(_ rawInput: String) -> Outcome {
        let input = normalizingSmartQuotes(rawInput)
        guard !input.contains("\n") else { return .ready(.bypass(input)) }
        switch FriendlyCompiler.compile(input) {
        case let .success(generatedSage, requiredVariables):
            return .ready(CompiledInput(
                raw: input,
                sage: generatedSage,
                requiredVariables: requiredVariables,
                origin: .friendly))
        case .bypass:
            return .ready(.bypass(input))
        case let .error(error):
            return .error(error)
        case let .ambiguous(candidates):
            return .ambiguous(candidates: candidates)
        }
    }

    /// Raw Sage passed through untouched (the bypass rule).
    static func bypass(_ raw: String) -> CompiledInput {
        CompiledInput(raw: raw, sage: raw, requiredVariables: [], origin: .bypass)
    }

    /// A chosen `.ambiguous` candidate: the candidate string becomes the
    /// generated Sage, and its required variables are re-derived with the
    /// library's own heuristic (candidates carry no variable report). The
    /// raw input is quote-normalized like every compiled input, so the row
    /// always records what was actually evaluated.
    static func chosenCandidate(raw: String, sage: String) -> CompiledInput {
        CompiledInput(
            raw: normalizingSmartQuotes(raw),
            sage: sage,
            requiredVariables: FriendlyCompiler.freeVariables(in: sage),
            origin: .friendly)
    }

    // MARK: - Smart-quote normalization

    /// Typographic ("curly") quotes mapped to their ASCII equivalents.
    private static let smartQuotes: [Character: Character] = [
        "\u{201C}": "\"", "\u{201D}": "\"",  // “ ” → "
        "\u{2018}": "'", "\u{2019}": "'",    // ‘ ’ → '
    ]

    /// Replaces curly double/single quotes with their ASCII equivalents.
    /// macOS smart-quote substitution and styled-text pastes turn
    /// `print("hello")` into `print(\u{201C}hello\u{201D})`, which Python
    /// rejects with a SyntaxError. Normalizing at the compile boundary —
    /// before the bypass/friendly decision — means the recorded `raw` input
    /// is exactly the text that was evaluated (honest), at the documented
    /// cost that a pasted string literal CONTAINING curly quotes is altered
    /// too. Acceptable for a calculator input field.
    static func normalizingSmartQuotes(_ input: String) -> String {
        guard input.contains(where: { smartQuotes[$0] != nil }) else { return input }
        return String(input.map { smartQuotes[$0] ?? $0 })
    }
}
