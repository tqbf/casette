// The friendly input compiler — a COMMAND SHIM, not a language.
//
// Input is one line. If it begins with a known command word followed by a space
// (or is exactly a command word), we treat it as friendly and rewrite it to Sage
// source. Simple assignments are also rewritten to echo their assigned value in
// the tape. Otherwise input BYPASSES untouched as raw Sage. We never
// build a full math parser: expression payloads pass through structurally; we
// tokenize only enough to find the command, the expression, and the clauses
// (ranges `x=0..1`, `wrt x`, `->`, `order=7`, `for x`). We DO validate balanced
// parens/brackets and emit useful, position-bearing errors.
//
// Pure: String in → CompileResult out. No I/O, no globals.

import Foundation

public enum FriendlyCompiler {

    /// Compile one line of friendly/raw input.
    public static func compile(_ rawInput: String) -> CompileResult {
        // Normalize: strip a trailing newline and surrounding spaces. Internal
        // spacing is preserved for the payload (we don't reflow user math).
        let input = rawInput.replacingOccurrences(of: "\n", with: " ").trimmedShim

        guard !input.isEmpty else {
            return .bypass(rawSage: "")
        }

        // Identify a leading command word (longest match first: "double integral"
        // before "integral" never applies, but multi-word commands are handled).
        guard let cmd = leadingCommand(input) else {
            if let matrixShorthand = matlabMatrixShorthand(input) {
                return matrixShorthand
            }
            if let assignment = simpleAssignmentEcho(input) {
                return assignment
            }
            // No known command word → raw Sage. Pass through untouched.
            return .bypass(rawSage: input)
        }

        // The remainder after the command word(s).
        let rest = String(input.dropFirst(cmd.matchedPrefix.count)).trimmedShim

        // A bare command word with no argument: nothing to compile. Treat as raw
        // (the user may have a variable named `factor`, however unlikely) — but
        // more usefully, a structured error guides them.
        if rest.isEmpty {
            return .error(CompileError(
                message: "`\(cmd.keyword.canonical)` needs an expression.",
                position: input.utf8.count,
                suggestion: cmd.keyword.exampleUsage
            ))
        }

        // Balance check on the whole remainder before clause parsing, so bracket
        // errors are reported precisely against the original input.
        if let bal = Scanner.balanceError(in: rest) {
            // Offset the balance position back into the full input coordinate space.
            let base = input.utf8.count - rest.utf8.count
            return .error(balanceCompileError(bal, baseOffset: base, input: input))
        }

        switch cmd.keyword {
        case .factor:       return wrapCall("factor", rest)
        case .expand:       return wrapCall("expand", rest)
        case .simplify:     return simplify(rest)
        case .solve:        return solve(rest)
        case .derivative:   return derivative(rest)
        case .integral:     return integral(rest, double: false)
        case .doubleIntegral: return integral(rest, double: true)
        case .limit:        return limitForm(rest)
        case .taylor:       return taylor(rest)
        case .plot:         return plot(rest)
        case .implicitPlot: return implicitPlot(rest)
        case .parametricPlot: return parametricPlot(rest)
        case .sum:          return seriesRange(rest, sage: "sum", command: "sum")
        case .product:      return seriesRange(rest, sage: "product", command: "product")
        case .matrix:       return matrixForm(rest)
        case .vector:       return vectorForm(rest)
        case .eigenvalues:  return matrixMethod(rest, method: "eigenvalues")
        case .rref:         return matrixMethod(rest, method: "rref")
        case .det:          return matrixMethod(rest, method: "det")
        case .inverse:      return matrixMethod(rest, method: "inverse")
        case .transpose:    return matrixMethod(rest, method: "transpose")
        case .rank:         return matrixMethod(rest, method: "rank")
        case .eigenvectors: return matrixMethod(rest, method: "eigenvectors_right")
        case .gradient:     return gradient(rest)
        case .hessian:      return hessian(rest)
        case .jacobian:     return jacobian(rest)
        case .subs:         return subs(rest)
        case .numeric:      return numeric(rest)
        case .latex:        return latexForm(rest)
        }
    }

    // MARK: - Command keywords

    enum Keyword: CaseIterable {
        case factor, expand, simplify, solve, derivative
        case integral, doubleIntegral, limit, taylor, plot
        case implicitPlot, parametricPlot
        case sum, product
        case matrix, vector, eigenvalues, rref
        case det, inverse, transpose, rank, eigenvectors
        case gradient, hessian, jacobian, subs, numeric, latex

        /// The phrase(s) that introduce this command. Multi-word first so the
        /// matcher prefers "double integral" over "integral".
        var phrases: [String] {
            switch self {
            case .factor: return ["factor"]
            case .expand: return ["expand"]
            case .simplify: return ["simplify"]
            case .solve: return ["solve"]
            case .derivative: return ["derivative", "diff"]
            case .integral: return ["integral", "integrate"]
            case .doubleIntegral: return ["double integral", "double integrate"]
            case .limit: return ["limit"]
            case .taylor: return ["taylor"]
            case .plot: return ["plot"]
            case .implicitPlot: return ["implicit_plot", "implicit plot"]
            case .parametricPlot: return ["parametric_plot", "parametric plot"]
            case .sum: return ["sum"]
            case .product: return ["product"]
            case .matrix: return ["matrix"]
            case .vector: return ["vector"]
            case .eigenvalues: return ["eigenvalues", "eigenvalue"]
            case .rref: return ["rref"]
            case .det: return ["det", "determinant"]
            case .inverse: return ["inverse"]
            case .transpose: return ["transpose"]
            case .rank: return ["rank"]
            case .eigenvectors: return ["eigenvectors", "eigenvector"]
            case .gradient: return ["gradient", "grad"]
            case .hessian: return ["hessian"]
            case .jacobian: return ["jacobian"]
            case .subs: return ["subs", "substitute"]
            case .numeric: return ["numeric", "approx", "decimal"]
            case .latex: return ["latex"]
            }
        }

        var canonical: String { phrases[0] }

        var exampleUsage: String {
            switch self {
            case .factor: return "Try: factor x^4 - 1"
            case .expand: return "Try: expand (x + 1)^5"
            case .simplify: return "Try: simplify sin(x)^2 + cos(x)^2"
            case .solve: return "Try: solve x^2 + 5*x + 6 = 0  (optionally: ... for x)"
            case .derivative: return "Try: derivative sin(x^2)  (optionally: ... wrt x)"
            case .integral: return "Try: integral x^2  or  integral x^2, x=0..1"
            case .doubleIntegral: return "Try: double integral x*y, x=0..1, y=0..x"
            case .limit: return "Try: limit sin(x)/x, x->0"
            case .taylor: return "Try: taylor sin(x), x=0, order=7"
            case .plot: return "Try: plot sin(x), x=-pi..pi"
            case .implicitPlot: return "Try: implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2"
            case .parametricPlot: return "Try: parametric_plot (cos(t), sin(t)), t=0..2*pi"
            case .sum: return "Try: sum k^2, k=1..n"
            case .product: return "Try: product 1 + 1/k, k=1..n"
            case .matrix: return "Try: matrix [1,2; 3,4]"
            case .vector: return "Try: vector [1,2,3]"
            case .eigenvalues: return "Try: eigenvalues [1,2; 3,4]"
            case .rref: return "Try: rref [1,2; 3,4]"
            case .det: return "Try: det [1,2; 3,4]"
            case .inverse: return "Try: inverse [1,2; 3,4]"
            case .transpose: return "Try: transpose [1,2; 3,4]"
            case .rank: return "Try: rank [1,2; 3,4]"
            case .eigenvectors: return "Try: eigenvectors [1,2; 3,4]"
            case .gradient: return "Try: gradient x^2 + y^2  or  gradient x^2 + y^2, [x,y]"
            case .hessian: return "Try: hessian x^2 + y^2"
            case .jacobian: return "Try: jacobian [x^2+y, sin(x*y)], [x,y]"
            case .subs: return "Try: subs x^2 + y, x=3"
            case .numeric: return "Try: numeric pi  or  numeric pi, 50"
            case .latex: return "Try: latex integral(sin(x), x)"
            }
        }
    }

    struct CommandMatch {
        let keyword: Keyword
        /// The exact prefix consumed from the input (e.g. "double integral ").
        let matchedPrefix: String
    }

    /// Find the leading command word, if any. A command is recognized only when
    /// the input is exactly the command word, OR the command word is followed by
    /// whitespace — so `factor x^4-1` is friendly but `factorial(5)` and
    /// `factor(x^4-1)` (already a call) bypass.
    static func leadingCommand(_ input: String) -> CommandMatch? {
        let lower = input.lowercased()
        // Collect all (keyword, phrase) candidates that match, pick the longest
        // phrase (so "double integral" wins over "integral").
        var best: (Keyword, String)?
        for kw in Keyword.allCases {
            for phrase in kw.phrases {
                if matchesCommand(lower, phrase: phrase, original: input) {
                    if best == nil || phrase.count > best!.1.count {
                        best = (kw, phrase)
                    }
                }
            }
        }
        guard let (kw, phrase) = best else { return nil }
        // Recover the matched prefix in the original casing/length: the phrase
        // length plus any phrase-internal spacing is fixed; we consumed exactly
        // `phrase.count` characters (phrases are lowercase ASCII words+spaces).
        let prefix = String(input.prefix(phrase.count))
        return CommandMatch(keyword: kw, matchedPrefix: prefix)
    }

    private static func matchesCommand(_ lower: String, phrase: String, original: String) -> Bool {
        guard lower.hasPrefix(phrase) else { return false }
        // Exact match: the whole input is the command word.
        if lower.count == phrase.count { return true }
        // Otherwise the char right after the phrase must be whitespace, so
        // `factor ...` matches but `factorial`/`factor(` do not.
        let idx = original.index(original.startIndex, offsetBy: phrase.count)
        let next = original[idx]
        return next == " " || next == "\t"
    }

    // MARK: - Form: factor / expand (simple function wrap)

    private static func wrapCall(_ fn: String, _ payload: String) -> CompileResult {
        let expr = payload.trimmedShim
        let sage = "\(fn)(\(expr))"
        return .success(generatedSage: sage, requiredVariables: Variables.freeVariables(in: expr))
    }

    // MARK: - Form: simplify

    private static func simplify(_ payload: String) -> CompileResult {
        // Use `.simplify_full()` so trig identities collapse (sin^2+cos^2 -> 1).
        // Wrap the payload in parens so method binds to the whole expression.
        let expr = payload.trimmedShim
        let sage = "(\(expr)).simplify_full()"
        return .success(generatedSage: sage, requiredVariables: Variables.freeVariables(in: expr))
    }

    // MARK: - Form: solve

    private static func solve(_ payload: String) -> CompileResult {
        // Optional trailing "for VAR". Split that off first.
        var body = payload
        var forVar: String?
        if let range = trailingClause(in: body, keyword: "for") {
            forVar = body[range.valueRange].trimmedShim
            body = String(body[body.startIndex..<range.clauseStart]).trimmedShim
        }

        // The body must contain an equation `LHS = RHS` (single '='), or be a bare
        // expression (solved == 0 by convention is NOT assumed; require the '=').
        // We translate `=` (not `==`, `<=`, `>=`, `!=`) into Sage `==`.
        guard let eq = splitEquation(body) else {
            return .error(CompileError(
                message: "`solve` needs an equation with `=`.",
                position: nil,
                suggestion: "Try: solve x^2 + 5*x + 6 = 0  (optionally: ... for x)"
            ))
        }
        let relation = "\(eq.lhs) == \(eq.rhs)"

        var vars = Variables.freeVariables(in: "\(eq.lhs) \(eq.rhs)")
        if let v = forVar, !v.isEmpty {
            if !Variables.isPlausibleVariable(v) {
                return .error(CompileError(
                    message: "`for \(v)` is not a valid variable name.",
                    position: nil,
                    suggestion: "Try: solve x^2 + 5*x + 6 = 0 for x"
                ))
            }
            // Ensure the solve var is among required (it always should be).
            if !vars.contains(v) { vars.insert(v, at: 0) }
            return .success(generatedSage: "solve(\(relation), \(v))", requiredVariables: vars)
        }

        // No explicit variable. If exactly one free variable, use it. If more than
        // one, it's ambiguous which to solve for — surface candidates.
        switch vars.count {
        case 0:
            // No variable at all (e.g. `solve 1 = 2`). Let Sage handle the bare
            // relation; nothing to declare.
            return .success(generatedSage: "solve(\(relation), [])", requiredVariables: [])
        case 1:
            return .success(generatedSage: "solve(\(relation), \(vars[0]))", requiredVariables: vars)
        default:
            let candidates = vars.map { "solve(\(relation), \($0))" }
            return .ambiguous(candidates: candidates)
        }
    }

    // MARK: - Form: derivative

    private static func derivative(_ payload: String) -> CompileResult {
        // Peel the trailing `wrt v` clause first (as before), so the comma split
        // below sees only the body (+ an optional trailing order).
        var body = payload
        var wrtVar: String?
        if let range = trailingClause(in: body, keyword: "wrt") {
            wrtVar = body[range.valueRange].trimmedShim
            body = String(body[body.startIndex..<range.clauseStart]).trimmedShim
        }

        // Optional trailing order, comma form ONLY: split on top-level commas and
        // if the LAST part is all digits, peel it off as the order. The remainder
        // re-joins as the differentiation body and flows through the UNCHANGED
        // wrt/inference logic — so a payload with no trailing digit clause is
        // byte-identical to before (the single-part split returns the body intact).
        var order: String?
        let parts = Scanner.splitTopLevelCommas(body)
        if parts.count >= 2,
           let last = parts.last?.trimmedShim,
           !last.isEmpty, last.allSatisfy({ $0.isNumber }) {
            order = last
            body = parts.dropLast().joined(separator: ",").trimmedShim
        }

        let expr = body.trimmedShim
        let vars = Variables.freeVariables(in: expr)

        // Build the Sage call for a chosen variable, with the order appended when
        // present: derivative(expr, v) or derivative(expr, v, N).
        func call(_ v: String) -> String {
            if let order { return "derivative(\(expr), \(v), \(order))" }
            return "derivative(\(expr), \(v))"
        }

        if let v = wrtVar, !v.isEmpty {
            guard Variables.isPlausibleVariable(v) else {
                return .error(CompileError(
                    message: "`wrt \(v)` is not a valid variable name.",
                    suggestion: "Try: derivative sin(x^2) wrt x"
                ))
            }
            var req = vars
            if !req.contains(v) { req.insert(v, at: 0) }
            return .success(generatedSage: call(v), requiredVariables: req)
        }

        switch vars.count {
        case 0:
            return .error(CompileError(
                message: "`derivative` has no variable to differentiate by.",
                suggestion: "Add one: derivative \(expr) wrt x"
            ))
        case 1:
            return .success(generatedSage: call(vars[0]), requiredVariables: vars)
        default:
            let candidates = vars.map { call($0) }
            return .ambiguous(candidates: candidates)
        }
    }

    // MARK: - Form: integral / double integral

    private static func integral(_ payload: String, double: Bool) -> CompileResult {
        var payload = payload
        var wrtVar: String?
        if let wrt = trailingClause(in: payload, keyword: "wrt") {
            wrtVar = payload[wrt.valueRange].trimmedShim
            payload = String(payload[payload.startIndex..<wrt.clauseStart])
                .droppingIntegralTrailingComma
                .trimmedShim
        }
        // Split on top-level commas: first piece = integrand, rest = ranges.
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let integrand = parts.first?.trimmedShim, !integrand.isEmpty else {
            return .error(CompileError(
                message: "`integral` needs an expression.",
                suggestion: double ? "Try: double integral x*y, x=0..1, y=0..x"
                                    : "Try: integral x^2  or  integral x^2, x=0..1"
            ))
        }
        let rangeClauses = Array(parts.dropFirst())

        if double {
            // Need exactly two ranges. The reference translation binds the INNER
            // integral to the LAST range and the outer to the FIRST:
            //   double integral x*y, x=0..1, y=0..x
            //     -> integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))
            guard rangeClauses.count == 2 else {
                return .error(CompileError(
                    message: "`double integral` needs two ranges (outer first, inner last).",
                    suggestion: "Try: double integral x*y, x=0..1, y=0..x"
                ))
            }
            guard let outer = parseRange(rangeClauses[0]) else {
                return .error(rangeError(rangeClauses[0], example: "x=0..1"))
            }
            guard let inner = parseRange(rangeClauses[1]) else {
                return .error(rangeError(rangeClauses[1], example: "y=0..x"))
            }
            let innerSage = "integrate(\(integrand), (\(inner.variable), \(inner.lower), \(inner.upper)))"
            let sage = "integrate(\(innerSage), (\(outer.variable), \(outer.lower), \(outer.upper)))"
            // Required vars: both bound vars + any free symbols in integrand/bounds.
            var req = Variables.freeVariables(
                in: "\(integrand) \(inner.lower) \(inner.upper) \(outer.lower) \(outer.upper)",
                bound: [outer.variable, inner.variable]
            )
            // outer/inner variables guaranteed present via `bound`; keep order outer,inner.
            req = orderedUnique([outer.variable, inner.variable] + req)
            return .success(generatedSage: sage, requiredVariables: req)
        }

        // Single integral. Zero ranges → indefinite; one range → definite.
        switch rangeClauses.count {
        case 0:
            // Indefinite: integrate(expr, var). Need the variable.
            let vars = Variables.freeVariables(in: integrand)
            if let wrtVar, !wrtVar.isEmpty {
                guard Variables.isPlausibleVariable(wrtVar) else {
                    return .error(CompileError(
                        message: "`wrt \(wrtVar)` is not a valid variable name.",
                        suggestion: "Try: integral \(integrand), wrt x"
                    ))
                }
                return .success(
                    generatedSage: "integrate(\(integrand), \(wrtVar))",
                    requiredVariables: orderedUnique([wrtVar] + vars))
            }
            switch vars.count {
            case 0:
                return .error(CompileError(
                    message: "`integral` has no variable to integrate by.",
                    suggestion: "Add one: integral \(integrand), x=0..1  (or give a variable)"
                ))
            case 1:
                return .success(generatedSage: "integrate(\(integrand), \(vars[0]))", requiredVariables: vars)
            default:
                let candidates = vars.map { "integrate(\(integrand), \($0))" }
                return .ambiguous(candidates: candidates)
            }
        case 1:
            guard let r = parseRange(rangeClauses[0]) else {
                return .error(rangeError(rangeClauses[0], example: "x=0..1"))
            }
            let sage = "integrate(\(integrand), (\(r.variable), \(r.lower), \(r.upper)))"
            let req = orderedUnique([r.variable] + Variables.freeVariables(
                in: "\(integrand) \(r.lower) \(r.upper)", bound: [r.variable]))
            return .success(generatedSage: sage, requiredVariables: req)
        default:
            return .error(CompileError(
                message: "`integral` takes at most one range (got \(rangeClauses.count)).",
                suggestion: "For a nested integral use: double integral x*y, x=0..1, y=0..x"
            ))
        }
    }

    // MARK: - Form: limit

    private static func limitForm(_ payload: String) -> CompileResult {
        // `limit EXPR, VAR->VAL` with an optional third clause `left`/`right`.
        let parts = Scanner.splitTopLevelCommas(payload)
        guard parts.count >= 2 else {
            return .error(CompileError(
                message: "`limit` needs an approach clause `var->value`.",
                suggestion: "Try: limit sin(x)/x, x->0"
            ))
        }
        let expr = parts[0].trimmedShim

        // An optional trailing `left`/`right` clause names the one-sided direction.
        // It is recognized only as a standalone third part (not a fragment of the
        // approach), so the two-clause form is unchanged.
        var dir: String?
        var approachParts = Array(parts[1...])
        if approachParts.count >= 2 {
            let tail = approachParts[approachParts.count - 1].trimmedShim.lowercased()
            switch tail {
            case "left": dir = "-"
            case "right": dir = "+"
            default:
                return .error(CompileError(
                    message: "`limit` direction must be `left` or `right`.",
                    suggestion: "Try: limit sin(x)/x, x->0, right"
                ))
            }
            approachParts.removeLast()
        }
        let approach = approachParts.joined(separator: ", ").trimmedShim
        // Split on `->`.
        guard let arrowRange = approach.range(of: "->") else {
            return .error(CompileError(
                message: "`limit` approach must use `->`, e.g. `x->0`.",
                suggestion: "Try: limit sin(x)/x, x->0"
            ))
        }
        let v = String(approach[approach.startIndex..<arrowRange.lowerBound]).trimmedShim
        let point = String(approach[arrowRange.upperBound...]).trimmedShim
        guard Variables.isPlausibleVariable(v) else {
            return .error(CompileError(
                message: "`limit` approach variable `\(v)` is not valid.",
                suggestion: "Try: limit sin(x)/x, x->0"
            ))
        }
        guard !point.isEmpty else {
            return .error(CompileError(
                message: "`limit` approach point is missing after `->`.",
                suggestion: "Try: limit sin(x)/x, x->0"
            ))
        }
        let sage: String
        if let dir {
            sage = "limit(\(expr), \(v)=\(point), dir='\(dir)')"
        } else {
            sage = "limit(\(expr), \(v)=\(point))"
        }
        let req = orderedUnique([v] + Variables.freeVariables(in: "\(expr) \(point)", bound: [v]))
        return .success(generatedSage: sage, requiredVariables: req)
    }

    // MARK: - Form: taylor

    private static func taylor(_ payload: String) -> CompileResult {
        // `taylor EXPR, VAR=PT, order=N`
        let parts = Scanner.splitTopLevelCommas(payload)
        guard parts.count >= 3 else {
            return .error(CompileError(
                message: "`taylor` needs an expansion point and order: `expr, var=pt, order=n`.",
                suggestion: "Try: taylor sin(x), x=0, order=7"
            ))
        }
        let expr = parts[0].trimmedShim
        // Second clause: var=pt (an assignment, not a range — no `..`).
        let center = parts[1].trimmedShim
        guard let eqIdx = center.firstIndex(of: "="), !center.contains("..") else {
            return .error(CompileError(
                message: "`taylor` expansion point must be `var=value`.",
                suggestion: "Try: taylor sin(x), x=0, order=7"
            ))
        }
        let v = String(center[center.startIndex..<eqIdx]).trimmedShim
        let pt = String(center[center.index(after: eqIdx)...]).trimmedShim
        guard Variables.isPlausibleVariable(v), !pt.isEmpty else {
            return .error(CompileError(
                message: "`taylor` expansion point `\(center)` is malformed.",
                suggestion: "Try: taylor sin(x), x=0, order=7"
            ))
        }
        // Third clause: order=N.
        let orderClause = parts[2].trimmedShim
        guard let oeq = orderClause.firstIndex(of: "="),
              orderClause[orderClause.startIndex..<oeq].trimmedShim.lowercased() == "order" else {
            return .error(CompileError(
                message: "`taylor` needs `order=n` as the last clause.",
                suggestion: "Try: taylor sin(x), x=0, order=7"
            ))
        }
        let order = String(orderClause[orderClause.index(after: oeq)...]).trimmedShim
        guard !order.isEmpty, order.allSatisfy({ $0.isNumber }) else {
            return .error(CompileError(
                message: "`taylor` order must be a whole number (got `\(order)`).",
                suggestion: "Try: taylor sin(x), x=0, order=7"
            ))
        }
        // Sage: taylor(expr, var, pt, order).
        let sage = "taylor(\(expr), \(v), \(pt), \(order))"
        let req = orderedUnique([v] + Variables.freeVariables(in: "\(expr) \(pt)", bound: [v]))
        return .success(generatedSage: sage, requiredVariables: req)
    }

    // MARK: - Form: sum / product

    /// `sum EXPR, VAR=LO..HI` → `sum(EXPR, VAR, LO, HI)`; same shape for product.
    /// Mirrors the definite-integral branch: split on top-level commas, first part
    /// is the summand/factor, then exactly one range clause. Lowercase symbolic
    /// `sum`/`product` are the correct Sage forms (sum(k^2, k, 1, n) → ...).
    private static func seriesRange(_ payload: String, sage fn: String, command: String) -> CompileResult {
        let example = "Try: \(command) k^2, k=1..n"
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let expr = parts.first?.trimmedShim, !expr.isEmpty else {
            return .error(CompileError(
                message: "`\(command)` needs an expression.",
                suggestion: example
            ))
        }
        let rangeClauses = Array(parts.dropFirst())
        guard rangeClauses.count <= 1 else {
            return .error(CompileError(
                message: "`\(command)` takes one range `k=1..n` (got \(rangeClauses.count)).",
                suggestion: example
            ))
        }
        guard let clause = rangeClauses.first else {
            return .error(CompileError(
                message: "`\(command)` needs a range `k=1..n`.",
                suggestion: example
            ))
        }
        guard let r = parseRange(clause) else {
            return .error(rangeError(clause, example: "k=1..n"))
        }
        let generated = "\(fn)(\(expr), \(r.variable), \(r.lower), \(r.upper))"
        let req = orderedUnique([r.variable] + Variables.freeVariables(
            in: "\(expr) \(r.lower) \(r.upper)", bound: [r.variable]))
        return .success(generatedSage: generated, requiredVariables: req)
    }

    // MARK: - Form: plot

    private static func plot(_ payload: String) -> CompileResult {
        // `plot EXPR, VAR=A..B`
        let parts = Scanner.splitTopLevelCommas(payload)
        let expr = parts.first?.trimmedShim ?? ""
        guard !expr.isEmpty else {
            return .error(CompileError(
                message: "`plot` needs an expression.",
                suggestion: "Try: plot sin(x), x=-pi..pi"
            ))
        }
        guard parts.count >= 2 else {
            return .error(CompileError(
                message: "`plot` needs a range `var=a..b`.",
                suggestion: "Try: plot sin(x), x=-pi..pi"
            ))
        }
        guard let r = parseRange(parts[1]) else {
            return .error(rangeError(parts[1], example: "x=-pi..pi"))
        }
        let sage = "plot(\(expr), (\(r.variable), \(r.lower), \(r.upper)))"
        let req = orderedUnique([r.variable] + Variables.freeVariables(
            in: "\(expr) \(r.lower) \(r.upper)", bound: [r.variable]))
        return .success(generatedSage: sage, requiredVariables: req)
    }

    // MARK: - Form: implicit_plot

    /// `implicit_plot EQUATION, X=LO..HI, Y=LO..HI`
    ///   → `implicit_plot(LHS == RHS, (x, xlo, xhi), (y, ylo, yhi))`
    /// The equation translates a single top-level `=` to `==`; a bare expression
    /// (no equals at all) normalizes to `EXPR == 0`. Exactly two ranges required;
    /// the per-range errors mirror the double-integral branch.
    private static func implicitPlot(_ payload: String) -> CompileResult {
        let example = "Try: implicit_plot x^2 + y^2 = 1, x=-2..2, y=-2..2"
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let rawEquation = parts.first?.trimmedShim, !rawEquation.isEmpty else {
            return .error(CompileError(
                message: "`implicit_plot` needs an equation.",
                suggestion: example
            ))
        }
        // Normalize the equation: `=` → `==`, `==` passes through, no equals →
        // `EXPR == 0`.
        let relation: String
        if rawEquation.contains("==") {
            relation = rawEquation
        } else if let eq = splitEquation(rawEquation) {
            relation = "\(eq.lhs) == \(eq.rhs)"
        } else {
            relation = "\(rawEquation) == 0"
        }

        let rangeClauses = Array(parts.dropFirst())
        guard rangeClauses.count == 2 else {
            return .error(CompileError(
                message: "`implicit_plot` needs two ranges (`x=...`, then `y=...`).",
                suggestion: example
            ))
        }
        guard let xRange = parseRange(rangeClauses[0]) else {
            return .error(rangeError(rangeClauses[0], example: "x=-2..2"))
        }
        guard let yRange = parseRange(rangeClauses[1]) else {
            return .error(rangeError(rangeClauses[1], example: "y=-2..2"))
        }
        let sage = "implicit_plot(\(relation), "
            + "(\(xRange.variable), \(xRange.lower), \(xRange.upper)), "
            + "(\(yRange.variable), \(yRange.lower), \(yRange.upper)))"
        var req = Variables.freeVariables(
            in: "\(relation) \(xRange.lower) \(xRange.upper) \(yRange.lower) \(yRange.upper)",
            bound: [xRange.variable, yRange.variable]
        )
        req = orderedUnique([xRange.variable, yRange.variable] + req)
        return .success(generatedSage: sage, requiredVariables: req)
    }

    // MARK: - Form: parametric_plot

    /// `parametric_plot (XEXPR, YEXPR), VAR=LO..HI`
    ///   → `parametric_plot((XEXPR, YEXPR), (VAR, LO, HI))`
    /// The parenthesized pair is one top-level unit; exactly one range required.
    private static func parametricPlot(_ payload: String) -> CompileResult {
        let example = "Try: parametric_plot (cos(t), sin(t)), t=0..2*pi"
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let pairText = parts.first?.trimmedShim, !pairText.isEmpty else {
            return .error(CompileError(
                message: "`parametric_plot` needs a coordinate pair `(x(t), y(t))`.",
                suggestion: example
            ))
        }
        // Validate the parenthesized pair: outer parens, exactly two non-empty
        // top-level pieces inside.
        guard pairText.hasPrefix("("), pairText.hasSuffix(")") else {
            return .error(CompileError(
                message: "`parametric_plot` needs a coordinate pair `(x(t), y(t))`.",
                suggestion: example
            ))
        }
        let inner = String(pairText.dropFirst().dropLast())
        let coords = Scanner.splitTopLevelCommas(inner).map { $0.trimmedShim }
        guard coords.count == 2, coords.allSatisfy({ !$0.isEmpty }) else {
            return .error(CompileError(
                message: "`parametric_plot` needs a coordinate pair `(x(t), y(t))`.",
                suggestion: example
            ))
        }
        let xExpr = coords[0]
        let yExpr = coords[1]

        let rangeClauses = Array(parts.dropFirst())
        guard rangeClauses.count == 1 else {
            return .error(CompileError(
                message: "`parametric_plot` needs one range `var=a..b`.",
                suggestion: example
            ))
        }
        guard let r = parseRange(rangeClauses[0]) else {
            return .error(rangeError(rangeClauses[0], example: "t=0..2*pi"))
        }
        let sage = "parametric_plot((\(xExpr), \(yExpr)), (\(r.variable), \(r.lower), \(r.upper)))"
        let req = orderedUnique([r.variable] + Variables.freeVariables(
            in: "\(xExpr) \(yExpr) \(r.lower) \(r.upper)", bound: [r.variable]))
        return .success(generatedSage: sage, requiredVariables: req)
    }

    // MARK: - Form: matrix / eigenvalues / rref

    private static func matrixForm(_ payload: String) -> CompileResult {
        guard let body = normalizeMatrixPayload(payload) else {
            return .error(CompileError(
                message: "`matrix` needs a bracketed list of rows.",
                suggestion: "Try: matrix [1,2; 3,4]"
            ))
        }
        return .success(generatedSage: "matrix(\(body))", requiredVariables: [])
    }

    /// A matrix method like `det`/`eigenvalues`/`rref`. Two payload shapes:
    ///
    ///   * A bracketed literal (`[1,2; 3,4]` or `[[1,2],[3,4]]`) normalizes into
    ///     Sage's row-list form and binds the method to a fresh `matrix(...)`:
    ///     `matrix([[1,2],[3,4]]).det()`. (The frozen V0.7 contract.)
    ///   * Anything else — a variable `A`, an expression `A*B`, or a tape ref
    ///     already expanded to `__casette_tape_refs[3]` — is an existing matrix
    ///     value: it binds directly, parenthesized, with its free variables
    ///     reported: `(A).det()`. A `#ROW` reference reaches us already expanded
    ///     to an identifier-shaped `__casette_tape_refs[N]` (starts with `_`,
    ///     not `[`), so it takes this path naturally — no `#` special-case.
    private static func matrixMethod(_ payload: String, method: String) -> CompileResult {
        let body = payload.trimmedShim
        if body.hasPrefix("[") {
            guard let normalized = normalizeMatrixPayload(body) else {
                return .error(CompileError(
                    message: "`\(method)` needs a bracketed list of rows.",
                    suggestion: "Try: \(method) [1,2; 3,4]"
                ))
            }
            return .success(generatedSage: "matrix(\(normalized)).\(method)()", requiredVariables: [])
        }
        return .success(
            generatedSage: "(\(body)).\(method)()",
            requiredVariables: Variables.freeVariables(in: body))
    }

    private static func vectorForm(_ payload: String) -> CompileResult {
        // A vector is a flat bracketed list (`[1,2,3]`) — it passes through
        // verbatim inside the call (no row normalization; vectors aren't nested).
        let body = payload.trimmedShim
        guard body.hasPrefix("["), body.hasSuffix("]"), singleOuterBracketBody(body) != nil else {
            return .error(CompileError(
                message: "`vector` needs a bracketed list of entries.",
                suggestion: "Try: vector [1,2,3]"
            ))
        }
        return .success(
            generatedSage: "vector(\(body))",
            requiredVariables: Variables.freeVariables(in: body))
    }

    // MARK: - Form: gradient

    /// `gradient EXPR` → `(EXPR).gradient()`; `gradient EXPR, [x,y]` →
    /// `(EXPR).gradient([x, y])`. A symbolic expression's `.gradient()`
    /// differentiates over all free variables with no args; an explicit
    /// bracketed var list orders and restricts that. The list entries are each
    /// validated as plausible variables.
    private static func gradient(_ payload: String) -> CompileResult {
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let expr = parts.first?.trimmedShim, !expr.isEmpty else {
            return .error(CompileError(
                message: "`gradient` needs an expression.",
                suggestion: "Try: gradient x^2 + y^2  or  gradient x^2 + y^2, [x,y]"
            ))
        }
        let rest = Array(parts.dropFirst())
        guard !rest.isEmpty else {
            // No var list: gradient over all free variables.
            return .success(
                generatedSage: "(\(expr)).gradient()",
                requiredVariables: Variables.freeVariables(in: expr))
        }
        // A single bracketed var-list clause follows the expression.
        let listText = rest.joined(separator: ", ").trimmedShim
        guard let vars = bracketedVariableList(listText) else {
            return .error(CompileError(
                message: "`gradient` variables must be a bracketed list like `[x, y]`.",
                suggestion: "Try: gradient x^2 + y^2, [x,y]"
            ))
        }
        let req = orderedUnique(vars + Variables.freeVariables(in: expr, bound: vars))
        return .success(
            generatedSage: "(\(expr)).gradient([\(vars.joined(separator: ", "))])",
            requiredVariables: req)
    }

    // MARK: - Form: hessian

    /// `hessian EXPR` → `(EXPR).hessian()`. Sage's symbolic `.hessian()` takes
    /// no reliable argument list, so ONLY the bare form is accepted; a second
    /// clause is a structured error rather than an invented lowering.
    private static func hessian(_ payload: String) -> CompileResult {
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let expr = parts.first?.trimmedShim, !expr.isEmpty else {
            return .error(CompileError(
                message: "`hessian` needs an expression.",
                suggestion: "Try: hessian x^2 + y^2"
            ))
        }
        guard parts.count == 1 else {
            return .error(CompileError(
                message: "`hessian` takes just an expression.",
                suggestion: "Try: hessian x^2 + y^2"
            ))
        }
        return .success(
            generatedSage: "(\(expr)).hessian()",
            requiredVariables: Variables.freeVariables(in: expr))
    }

    // MARK: - Form: jacobian

    /// `jacobian [F1, F2], [x, y]` → `jacobian([F1, F2], [x, y])` (Sage's
    /// global `jacobian(functions, vars)`). Both clauses are required and
    /// bracketed; the var-list entries are validated.
    private static func jacobian(_ payload: String) -> CompileResult {
        let example = "Try: jacobian [x^2+y, sin(x*y)], [x,y]"
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let functionsText = parts.first?.trimmedShim, !functionsText.isEmpty else {
            return .error(CompileError(
                message: "`jacobian` needs a bracketed list of functions.",
                suggestion: example
            ))
        }
        guard functionsText.hasPrefix("["), functionsText.hasSuffix("]"),
              singleOuterBracketBody(functionsText) != nil else {
            return .error(CompileError(
                message: "`jacobian` functions must be a bracketed list like `[x^2+y, sin(x*y)]`.",
                suggestion: example
            ))
        }
        let rest = Array(parts.dropFirst())
        guard !rest.isEmpty else {
            return .error(CompileError(
                message: "`jacobian` needs a bracketed variable list.",
                suggestion: example
            ))
        }
        let listText = rest.joined(separator: ", ").trimmedShim
        guard let vars = bracketedVariableList(listText) else {
            return .error(CompileError(
                message: "`jacobian` variables must be a bracketed list like `[x, y]`.",
                suggestion: example
            ))
        }
        let req = orderedUnique(
            vars + Variables.freeVariables(in: functionsText, bound: vars))
        return .success(
            generatedSage: "jacobian(\(functionsText), [\(vars.joined(separator: ", "))])",
            requiredVariables: req)
    }

    // MARK: - Form: subs

    /// `subs EXPR, V1=VAL1, V2=VAL2, ...` → `(EXPR).subs(V1=VAL1, V2=VAL2)`.
    /// Each binding clause splits on its FIRST top-level `=`; the name must be
    /// a plausible variable and the value non-empty (and not a range).
    private static func subs(_ payload: String) -> CompileResult {
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let expr = parts.first?.trimmedShim, !expr.isEmpty else {
            return .error(CompileError(
                message: "`subs` needs an expression.",
                suggestion: "Try: subs x^2 + y, x=3"
            ))
        }
        let bindingClauses = Array(parts.dropFirst())
        guard !bindingClauses.isEmpty else {
            return .error(CompileError(
                message: "`subs` needs at least one binding `var=value`.",
                suggestion: "Try: subs x^2 + y, x=3"
            ))
        }
        var bindings: [(name: String, value: String)] = []
        for clause in bindingClauses {
            let c = clause.trimmedShim
            guard let eqIdx = c.firstIndex(of: "="), !c.contains("..") else {
                return .error(CompileError(
                    message: "`subs` binding `\(c)` must be `var=value`.",
                    suggestion: "Try: subs x^2 + y, x=3"
                ))
            }
            let name = String(c[c.startIndex..<eqIdx]).trimmedShim
            let value = String(c[c.index(after: eqIdx)...]).trimmedShim
            guard Variables.isPlausibleVariable(name), !value.isEmpty else {
                return .error(CompileError(
                    message: "`subs` binding `\(c)` must be `var=value`.",
                    suggestion: "Try: subs x^2 + y, x=3"
                ))
            }
            bindings.append((name, value))
        }
        let bindingSage = bindings.map { "\($0.name)=\($0.value)" }.joined(separator: ", ")
        let bindingVars = bindings.map(\.name)
        let bindingValues = bindings.map(\.value).joined(separator: " ")
        let req = orderedUnique(
            bindingVars + Variables.freeVariables(in: "\(expr) \(bindingValues)"))
        return .success(
            generatedSage: "(\(expr)).subs(\(bindingSage))",
            requiredVariables: req)
    }

    // MARK: - Form: numeric

    /// `numeric EXPR` → `N(EXPR)`; `numeric EXPR, DIGITS` →
    /// `N(EXPR, digits=DIGITS)` (the last clause must be all digits).
    private static func numeric(_ payload: String) -> CompileResult {
        let parts = Scanner.splitTopLevelCommas(payload)
        guard let expr = parts.first?.trimmedShim, !expr.isEmpty else {
            return .error(CompileError(
                message: "`numeric` needs an expression.",
                suggestion: "Try: numeric pi  or  numeric pi, 50"
            ))
        }
        let rest = Array(parts.dropFirst())
        guard !rest.isEmpty else {
            return .success(
                generatedSage: "N(\(expr))",
                requiredVariables: Variables.freeVariables(in: expr))
        }
        guard rest.count == 1 else {
            return .error(CompileError(
                message: "`numeric` takes at most a digit count after the expression.",
                suggestion: "Try: numeric pi, 50"
            ))
        }
        let digits = rest[0].trimmedShim
        guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }) else {
            return .error(CompileError(
                message: "`numeric` digits must be a whole number (got `\(digits)`).",
                suggestion: "Try: numeric pi, 50"
            ))
        }
        return .success(
            generatedSage: "N(\(expr), digits=\(digits))",
            requiredVariables: Variables.freeVariables(in: expr))
    }

    // MARK: - Form: latex

    /// `latex EXPR` → `latex(EXPR)`.
    private static func latexForm(_ payload: String) -> CompileResult {
        let expr = payload.trimmedShim
        return .success(
            generatedSage: "latex(\(expr))",
            requiredVariables: Variables.freeVariables(in: expr))
    }

    /// Parse a bracketed variable list `[x, y]`, validating each entry as a
    /// plausible variable. Returns the trimmed names, or nil if the text isn't
    /// a single bracketed list or any entry is not a valid variable.
    private static func bracketedVariableList(_ text: String) -> [String]? {
        let body = text.trimmedShim
        guard body.hasPrefix("["), body.hasSuffix("]"),
              let inside = singleOuterBracketBody(body) else { return nil }
        let entries = Scanner.splitTopLevelCommas(inside).map { $0.trimmedShim }
        guard !entries.isEmpty, entries.allSatisfy({ Variables.isPlausibleVariable($0) })
        else { return nil }
        return entries
    }

    private static func matlabMatrixShorthand(_ input: String) -> CompileResult? {
        if let assignment = splitEquation(input),
           Variables.isPlausibleVariable(assignment.lhs),
           let generated = matlabMatrixGeneratedSage(
               payload: assignment.rhs,
               baseOffset: utf8Offset(of: assignment.rhs, in: input),
               wrap: { "\(assignment.lhs) = matrix(\($0))\n\(assignment.lhs)" }) {
            return generated
        }

        return matlabMatrixGeneratedSage(
            payload: input,
            baseOffset: 0,
            wrap: { "matrix(\($0))" })
    }

    private static func matlabMatrixGeneratedSage(
        payload: String,
        baseOffset: Int,
        wrap: (String) -> String
    ) -> CompileResult? {
        let body = payload.trimmedShim
        guard body.hasPrefix("["), body.contains(";") else { return nil }

        if let bal = Scanner.balanceError(in: body) {
            return .error(balanceCompileError(bal, baseOffset: baseOffset, input: body))
        }

        guard let normalized = normalizeMatrixPayload(body, requiresTopLevelSemicolon: true) else {
            return .error(CompileError(
                message: "MATLAB-style matrix literal is malformed.",
                position: nil,
                suggestion: "Try: [1,2; 3,4] or A = [1,2; 3,4]"
            ))
        }

        return .success(
            generatedSage: wrap(normalized),
            requiredVariables: Variables.freeVariables(in: normalized))
    }

    private static func simpleAssignmentEcho(_ input: String) -> CompileResult? {
        guard let assignment = splitEquation(input),
              Variables.isPlausibleVariable(assignment.lhs) else { return nil }
        return .success(
            generatedSage: "\(assignment.lhs) = \(assignment.rhs)\n\(assignment.lhs)",
            requiredVariables: Variables.freeVariables(in: assignment.rhs))
    }

    /// Accept both Sage's row-list form (`[[1,2],[3,4]]`) and MATLAB-style
    /// matrix literals (`[1,2; 3,4]`). The latter is normalized into Sage's
    /// list-of-rows form while preserving the text of each cell expression.
    private static func normalizeMatrixPayload(
        _ payload: String,
        requiresTopLevelSemicolon: Bool = false
    ) -> String? {
        let body = payload.trimmedShim
        guard body.hasPrefix("[") else { return nil }
        guard let inside = singleOuterBracketBody(body) else {
            return requiresTopLevelSemicolon ? nil : body
        }

        let inner = inside.trimmedShim
        guard !inner.hasPrefix("[") else {
            return requiresTopLevelSemicolon ? nil : body
        }

        let rows = Scanner.splitTopLevelSemicolons(inside)
        guard !requiresTopLevelSemicolon || rows.count > 1 else { return nil }
        guard !rows.isEmpty, rows.allSatisfy({ !$0.isEmpty }) else { return nil }

        let sageRows = rows.map { row in
            let cells = Scanner.splitTopLevelCommas(row)
            guard !cells.isEmpty, cells.allSatisfy({ !$0.isEmpty }) else { return "" }
            return "[\(cells.joined(separator: ","))]"
        }
        guard sageRows.allSatisfy({ !$0.isEmpty }) else { return nil }
        return "[\(sageRows.joined(separator: ","))]"
    }

    private static func singleOuterBracketBody(_ body: String) -> String? {
        guard body.first == "[", body.last == "]" else { return nil }
        var depth = 0
        for (offset, ch) in body.enumerated() {
            if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth == 0, offset != body.count - 1 { return nil }
            }
        }
        return String(body.dropFirst().dropLast())
    }

    // MARK: - Range / clause parsing helpers

    struct Range {
        let variable: String
        let lower: String
        let upper: String
    }

    /// Parse `var=lower..upper`. Returns nil if malformed (missing `=`, missing
    /// `..`, empty bound, etc.) so the caller can emit a precise error.
    static func parseRange(_ clause: String) -> Range? {
        let c = clause.trimmedShim
        guard let eqIdx = c.firstIndex(of: "=") else { return nil }
        let v = String(c[c.startIndex..<eqIdx]).trimmedShim
        let rangePart = String(c[c.index(after: eqIdx)...]).trimmedShim
        guard Variables.isPlausibleVariable(v) else { return nil }
        guard let dotRange = rangePart.range(of: "..") else { return nil }
        let lower = String(rangePart[rangePart.startIndex..<dotRange.lowerBound]).trimmedShim
        let upper = String(rangePart[dotRange.upperBound...]).trimmedShim
        guard !lower.isEmpty, !upper.isEmpty else { return nil }
        return Range(variable: v, lower: lower, upper: upper)
    }

    private static func rangeError(_ clause: String, example: String) -> CompileError {
        let c = clause.trimmedShim
        if c.contains("..") && c.hasSuffix("..") {
            return CompileError(
                message: "Range `\(c)` is incomplete — missing the upper bound after `..`.",
                suggestion: "Complete it, e.g. `\(example)`."
            )
        }
        if !c.contains("..") {
            return CompileError(
                message: "Range `\(c)` is missing `..` between the bounds.",
                suggestion: "Use `var=lo..hi`, e.g. `\(example)`."
            )
        }
        return CompileError(
            message: "Range `\(c)` is malformed.",
            suggestion: "Use `var=lo..hi`, e.g. `\(example)`."
        )
    }

    /// A trailing keyword-introduced clause like `for x` / `wrt x`: returns the
    /// range of the clause start (so the body can be trimmed) and the value range.
    struct TrailingClause {
        let clauseStart: String.Index
        let valueRange: Swift.Range<String.Index>
    }

    /// Find a trailing ` KEYWORD value` clause (space-delimited keyword). The
    /// keyword must appear at top level (not nested) and be followed by a value.
    static func trailingClause(in s: String, keyword: String) -> TrailingClause? {
        // Search for " keyword " (case-insensitive) as a whole word near the end.
        let lower = s.lowercased()
        let needle = " \(keyword) "
        // Find the LAST occurrence so `for x` at the very end is matched.
        guard let r = lower.range(of: needle, options: .backwards) else {
            // Also allow keyword at exact end with no trailing space? No — needs a value.
            return nil
        }
        // Map back into `s` (same indices: lowercasing ASCII keeps length here for
        // our inputs; to be safe, compute offset).
        let startOffset = lower.distance(from: lower.startIndex, to: r.lowerBound)
        let endOffset = lower.distance(from: lower.startIndex, to: r.upperBound)
        let clauseStart = s.index(s.startIndex, offsetBy: startOffset)
        let valueStart = s.index(s.startIndex, offsetBy: endOffset)
        let value = String(s[valueStart...]).trimmedShim
        guard !value.isEmpty else { return nil }
        return TrailingClause(clauseStart: clauseStart, valueRange: valueStart..<s.endIndex)
    }

    // MARK: - Equation split

    struct Equation { let lhs: String; let rhs: String }

    /// Split `LHS = RHS` on a single top-level `=` that is NOT part of
    /// `==`, `<=`, `>=`, `!=`. Returns nil if there is no such `=`.
    static func splitEquation(_ s: String) -> Equation? {
        let chars = Array(s)
        var depth = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            switch ch {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case "=" where depth == 0:
                let prev = i > 0 ? chars[i - 1] : " "
                let next = i + 1 < chars.count ? chars[i + 1] : " "
                // Skip ==, <=, >=, !=
                if next == "=" { i += 2; continue }
                if prev == "=" || prev == "<" || prev == ">" || prev == "!" {
                    i += 1; continue
                }
                let lhs = String(chars[0..<i]).trimmedShim
                let rhs = String(chars[(i + 1)...]).trimmedShim
                guard !lhs.isEmpty, !rhs.isEmpty else { return nil }
                return Equation(lhs: lhs, rhs: rhs)
            default: break
            }
            i += 1
        }
        return nil
    }

    // MARK: - Balance error → CompileError

    private static func balanceCompileError(_ bal: Scanner.BalanceError, baseOffset: Int, input: String) -> CompileError {
        let pos = baseOffset + bal.position
        switch bal.kind {
        case let .unclosed(ch):
            let close = ch == "(" ? ")" : ch == "[" ? "]" : "}"
            return CompileError(
                message: "Unbalanced `\(ch)` — it is never closed.",
                position: pos,
                suggestion: "Add a matching `\(close)`."
            )
        case let .unexpectedClose(ch):
            return CompileError(
                message: "Unexpected `\(ch)` — there is no matching opener.",
                position: pos,
                suggestion: "Remove it or add the missing opener."
            )
        case let .mismatched(open, close):
            let want = open == "(" ? ")" : open == "[" ? "]" : "}"
            return CompileError(
                message: "Bracket mismatch — `\(open)` is closed by `\(close)`.",
                position: pos,
                suggestion: "Close it with `\(want)` instead."
            )
        }
    }

    // MARK: - Small utilities

    private static func orderedUnique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for i in items where !i.isEmpty {
            if !seen.contains(i) { seen.insert(i); out.append(i) }
        }
        return out
    }

    private static func utf8Offset(of needle: String, in haystack: String) -> Int {
        guard let range = haystack.range(of: needle, options: .backwards) else { return 0 }
        return haystack[haystack.startIndex..<range.lowerBound].utf8.count
    }
}

extension String {
    fileprivate var droppingIntegralTrailingComma: String {
        let trimmed = trimmedShim
        guard trimmed.last == "," else { return trimmed }
        return String(trimmed.dropLast())
    }
}
