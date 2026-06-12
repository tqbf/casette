import Foundation
import Testing
@testable import Casette

/// The app-side compile boundary: `CompiledInput.compile` outcome mapping,
/// the frozen prelude-emission policy (`var('V')` per required variable,
/// never inside the displayed Sage), and the multiline raw-Sage rule.
@Suite("CompiledInput compile boundary")
struct CompiledInputTests {
    @Test("a friendly form compiles: raw and generated Sage split, origin friendly")
    func friendlyCompiles() {
        guard case let .ready(compiled) = CompiledInput.compile("factor x^4 - 1") else {
            Issue.record("expected .ready")
            return
        }
        #expect(compiled.raw == "factor x^4 - 1")
        #expect(compiled.sage == "factor(x^4 - 1)")
        #expect(compiled.origin == .friendly)
        #expect(compiled.requiredVariables == ["x"])
    }

    @Test("raw Sage bypasses untouched, no preludes")
    func bypassUntouched() {
        guard case let .ready(compiled) = CompiledInput.compile("factorial(5)") else {
            Issue.record("expected .ready")
            return
        }
        #expect(compiled.raw == "factorial(5)")
        #expect(compiled.sage == "factorial(5)")
        #expect(compiled.origin == .bypass)
        #expect(compiled.preludes.isEmpty)
    }

    @Test("prelude policy: one var('V') per required variable, command-bound order, NOT in the displayed Sage")
    func preludeEmission() {
        guard case let .ready(compiled) =
            CompiledInput.compile("double integral u*v, u=0..1, v=0..u")
        else {
            Issue.record("expected .ready")
            return
        }
        #expect(compiled.sage == "integrate(integrate(u*v, (v, 0, u)), (u, 0, 1))")
        // Outer bound variable first, then inner — the frozen V0.7 order.
        #expect(compiled.requiredVariables == ["u", "v"])
        #expect(compiled.preludes == ["var('u')", "var('v')"])
        // The generated Sage stays a single clean expression — the preludes
        // are what's SENT, never what's displayed.
        #expect(!compiled.sage.contains("var("))
    }

    @Test("multiline input is raw Sage by definition — newlines survive intact")
    func multilineBypasses() {
        let code = "factor = 7\nfactor + 1"
        guard case let .ready(compiled) = CompiledInput.compile(code) else {
            Issue.record("expected .ready")
            return
        }
        #expect(compiled.origin == .bypass)
        #expect(compiled.sage == code)  // NOT flattened to one line
    }

    @Test("a malformed friendly input is an error outcome with a suggestion")
    func errorOutcome() {
        guard case let .error(error) = CompiledInput.compile("integral x^2, x=0..") else {
            Issue.record("expected .error")
            return
        }
        #expect(error.message.contains("incomplete"))
        #expect(error.suggestion != nil)
    }

    @Test("an ambiguous input surfaces the candidate readings")
    func ambiguousOutcome() {
        guard case let .ambiguous(candidates) = CompiledInput.compile("solve x*y = 1") else {
            Issue.record("expected .ambiguous")
            return
        }
        #expect(candidates == ["solve(x*y == 1, x)", "solve(x*y == 1, y)"])
    }

    @Test("a chosen ambiguity candidate re-derives its required variables")
    func chosenCandidateVariables() {
        let compiled = CompiledInput.chosenCandidate(
            raw: "solve x*y = 1", sage: "solve(x*y == 1, y)")
        #expect(compiled.origin == .friendly)
        #expect(compiled.requiredVariables == ["x", "y"])
        #expect(compiled.preludes == ["var('x')", "var('y')"])
    }
}
