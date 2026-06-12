// The structured output of the friendly compiler.
//
// Pure data — `String in → structured result out`. The library never does I/O;
// V1.4 owns deciding what to *do* with each case (show the Sage, pass it to the
// worker, surface the error inline, or offer the ambiguity candidates).

import Foundation

/// The outcome of compiling one line of input.
public enum CompileResult: Equatable, Sendable {
    /// Input matched a friendly command form and was rewritten to Sage source.
    ///
    /// - `generatedSage`: Sage source the UI can display verbatim ("Generated
    ///   Sage") and the worker can `eval`. Most forms are a single expression;
    ///   simple assignments use `name = value\nname` so the tape echoes the
    ///   assigned value.
    /// - `requiredVariables`: free variables the expression needs declared in the
    ///   session (e.g. `x` for `integral x^2`). V1.4 decides how to satisfy these
    ///   (emit `var('x')` preludes, or rely on the session). See the README /
    ///   plans/FRIENDLY-COMPILER.md for the policy.
    case success(generatedSage: String, requiredVariables: [String])

    /// Input did not match any friendly form — it is treated as **raw Sage** and
    /// passed through untouched. This is the deliberate escape hatch: anything the
    /// shim doesn't recognize is the user's own Sage.
    case bypass(rawSage: String)

    /// Input matched (or began to match) a friendly form but is malformed.
    case error(CompileError)

    /// Input is genuinely ambiguous between two or more readings; the UI should
    /// offer the candidate interpretations rather than guess.
    case ambiguous(candidates: [String])
}

/// A structured, position-bearing parse error with a human suggestion.
public struct CompileError: Equatable, Sendable {
    /// Human-readable description of what went wrong.
    public let message: String
    /// 0-based UTF-8 offset into the original input where the problem is, if known.
    public let position: Int?
    /// A concrete "did you mean" / "try this" hint.
    public let suggestion: String?

    public init(message: String, position: Int? = nil, suggestion: String? = nil) {
        self.message = message
        self.position = position
        self.suggestion = suggestion
    }
}

extension CompileResult {
    /// Convenience for tests / tooling: the generated Sage if this is a
    /// `.success` or `.bypass`, else nil.
    public var sage: String? {
        switch self {
        case let .success(sage, _): return sage
        case let .bypass(sage): return sage
        case .error, .ambiguous: return nil
        }
    }
}
