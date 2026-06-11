// Free-variable inference for the `requiredVariables` field.
//
// This is a heuristic, documented as such. We scan an expression for identifiers
// that are NOT immediately followed by '(' (so they are not function calls), are
// NOT known Sage constants (pi, e, I, ...), and are plausible symbolic variables.
// V1.4 uses `requiredVariables` to decide whether to emit `var('x')` preludes or
// trust the session — the compiler only *reports* them; it never injects.

import Foundation

enum Variables {

    /// Sage names that are predefined and must NOT be treated as free variables
    /// to declare. Constants + the most common builtins that can appear bare.
    private static let reserved: Set<String> = [
        "pi", "e", "I", "i", "oo", "infinity", "Infinity", "NaN", "euler_gamma",
        "True", "False", "None",
        // Common function names that might appear without parens in odd input;
        // belt-and-suspenders (the '(' check already excludes called functions).
        "sqrt", "sin", "cos", "tan", "exp", "log", "ln", "abs",
    ]

    /// Identifiers that are explicitly bound by the command (e.g. the integration
    /// variable) are passed in `bound` so they are reported even though we'd
    /// otherwise also find them in the body — and so a plain `x` bound variable is
    /// always required even if it only appears in the range.
    static func freeVariables(in expression: String, bound: [String] = []) -> [String] {
        var found: [String] = []
        var seen = Set<String>()

        func add(_ name: String) {
            guard !seen.contains(name) else { return }
            seen.insert(name)
            found.append(name)
        }

        // First, the explicitly bound variables (stable, command-driven order).
        for b in bound where isPlausibleVariable(b) { add(b) }

        // Then scan the expression for bare identifiers not followed by '('.
        let chars = Array(expression)
        var idx = 0
        while idx < chars.count {
            let ch = chars[idx]
            if isIdentStart(ch) {
                var j = idx + 1
                while j < chars.count && isIdentContinue(chars[j]) { j += 1 }
                let name = String(chars[idx..<j])
                // Skip if it's a call: next non-space char is '('.
                var k = j
                while k < chars.count && (chars[k] == " " || chars[k] == "\t") { k += 1 }
                let isCall = k < chars.count && chars[k] == "("
                if !isCall && !reserved.contains(name) && isPlausibleVariable(name) {
                    add(name)
                }
                idx = j
            } else {
                idx += 1
            }
        }
        return found
    }

    /// A plausible symbolic variable: a letter-led identifier that is not a pure
    /// number and not reserved. We accept multi-char names (e.g. `theta`) so the
    /// shim is forgiving, but exclude anything reserved.
    static func isPlausibleVariable(_ name: String) -> Bool {
        guard let first = name.first, isIdentStart(first) else { return false }
        return !reserved.contains(name)
    }

    private static func isIdentStart(_ ch: Character) -> Bool {
        ch == "_" || ch.isLetter
    }

    private static func isIdentContinue(_ ch: Character) -> Bool {
        ch == "_" || ch.isLetter || ch.isNumber
    }
}
