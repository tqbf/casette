// App-side addition — NOT part of the verbatim v0/07 lift.
//
// The four library files (CompileResult / FriendlyCompiler / Scanner /
// Variables) are byte-identical to v0/07-friendly-compiler (the frozen
// proof). This file is the only Casette-side extension: V1.4 needs the
// library's free-variable heuristic for one extra case the frozen contract
// doesn't cover directly — when the user picks an `.ambiguous` candidate,
// the chosen Sage string needs its own `requiredVariables` so the app can
// emit the `var('V')` preludes (FRIENDLY-COMPILER.md variable policy).

import Foundation

extension FriendlyCompiler {
    /// Free variables of a Sage expression, by the same documented heuristic
    /// that fills `CompileResult.success`'s `requiredVariables` (bare
    /// identifiers not followed by `(`, not reserved). Used for `.ambiguous`
    /// candidates, whose strings carry no variable report of their own.
    public static func freeVariables(in expression: String) -> [String] {
        Variables.freeVariables(in: expression)
    }
}
