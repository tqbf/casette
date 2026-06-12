import Foundation
import Testing
@testable import Casette

/// The V1.6 action→command mapping: every command action builds the honest
/// stateless follow-up (`(<expr>).det()` — no `ans` variable exists), copy
/// actions copy, plot actions stay inert until V1.7, and only rows whose
/// Sage is reusable as one expression offer commands at all.
@Suite("ResultAction mapping")
struct ResultActionTests {
    @Test("matrix det wraps the row's generated Sage — the headline strategy")
    func matrixDeterminantCommand() {
        let det = ResultAction(name: "det")
        #expect(det.behavior == .command)
        #expect(det.title == "Determinant")
        #expect(
            det.command(wrapping: "matrix([[1,2],[3,4]])")
                == "(matrix([[1,2],[3,4]])).det()")
    }

    @Test("the spec's expression actions all build commands")
    func expressionCommands() {
        let expression = "(x + 1)^2"
        #expect(ResultAction(name: "simplify").command(wrapping: expression)
            == "((x + 1)^2).simplify_full()")
        #expect(ResultAction(name: "expand").command(wrapping: expression)
            == "expand((x + 1)^2)")
        #expect(ResultAction(name: "factor").command(wrapping: expression)
            == "factor((x + 1)^2)")
        #expect(ResultAction(name: "approx").command(wrapping: expression)
            == "((x + 1)^2).n()")
    }

    @Test("diff/integrate/solve name the expression's own free variable")
    func variableAwareCommands() {
        #expect(ResultAction(name: "diff").command(wrapping: "t^2 + 1")
            == "diff(t^2 + 1, t)")
        #expect(ResultAction(name: "integrate").command(wrapping: "t^2 + 1")
            == "integrate(t^2 + 1, t)")
        // No free variable (a constant) falls back to x — visible and
        // editable in the input before evaluating.
        #expect(ResultAction(name: "diff").command(wrapping: "8/15")
            == "diff(8/15, x)")
    }

    @Test("the remaining matrix actions build their methods")
    func matrixCommands() {
        let m = "matrix([[1,2],[3,4]])"
        #expect(ResultAction(name: "rank").command(wrapping: m) == "(\(m)).rank()")
        #expect(ResultAction(name: "rref").command(wrapping: m) == "(\(m)).rref()")
        #expect(ResultAction(name: "inverse").command(wrapping: m) == "(\(m)).inverse()")
        #expect(ResultAction(name: "eigenvalues").command(wrapping: m) == "(\(m)).eigenvalues()")
        #expect(ResultAction(name: "transpose").command(wrapping: m) == "(\(m)).transpose()")
    }

    @Test("copy actions copy; plot actions are inert until V1.7; unknown degrades visibly")
    func nonCommandBehaviors() {
        #expect(ResultAction(name: "copy").behavior == .copyPlain)
        #expect(ResultAction(name: "copy_traceback").behavior == .copyTraceback)
        if case .unavailable = ResultAction(name: "save_png").behavior {} else {
            Issue.record("save_png should be unavailable until V1.7")
        }
        if case .unavailable = ResultAction(name: "frobulate").behavior {} else {
            Issue.record("an unknown wire name must degrade to unavailable, never crash")
        }
        #expect(ResultAction(name: "frobulate").title == "frobulate")  // visible as itself
    }

    @Test("actions(for:) preserves the worker's order")
    func actionsPreserveOrder() {
        let envelope = PersistedEnvelope(
            kind: "matrix", plain: "[1 2]\n[3 4]",
            actions: ["det", "rank", "rref", "eigenvalues", "transpose", "inverse"])
        #expect(ResultAction.actions(for: envelope).map(\.name)
            == ["det", "rank", "rref", "eigenvalues", "transpose", "inverse"])
    }

    @Test("reusableExpression: ok value rows yes; statements, errors, multiline no")
    func reusableExpression() {
        func row(
            sage: String, status: RowStatus, kind: String = "integer", plain: String = "4"
        ) -> SessionRow {
            SessionRow(
                input: sage, sage: sage,
                result: status == .running ? nil : PersistedEnvelope(kind: kind, plain: plain),
                status: status, timestamp: .now)
        }
        #expect(row(sage: "2 + 2", status: .ok).reusableExpression == "2 + 2")
        // A statement (assignment, del) echoes no value — nothing to reuse.
        #expect(row(sage: "a = 5", status: .ok, kind: "none", plain: "").reusableExpression == nil)
        // Multiline raw Sage is a statement sequence, not an expression.
        #expect(row(sage: "a = 5\na * 9", status: .ok, plain: "45").reusableExpression == nil)
        // Errors and pending rows have no reusable value.
        #expect(row(sage: "1/0", status: .error, kind: "error", plain: "div").reusableExpression == nil)
        #expect(row(sage: "2 + 2", status: .running).reusableExpression == nil)
    }

    @Test("Copy Sage snippet: name = value for scalar kinds, bare name otherwise")
    func symbolSageSnippet() {
        #expect(SymbolEntry(name: "n", kind: "integer", summary: "104729").sageSnippet
            == "n = 104729")
        #expect(SymbolEntry(name: "q", kind: "rational", summary: "8/15").sageSnippet
            == "q = 8/15")
        // A matrix summary is a description, not a value — the name is the
        // only honest Sage.
        #expect(SymbolEntry(name: "A", kind: "matrix", summary: "2×2 over Integer Ring").sageSnippet
            == "A")
        #expect(SymbolEntry(name: "x", kind: "symbolic variable", summary: "x").sageSnippet == "x")
        // A truncated summary is not the whole value — don't paste half.
        #expect(SymbolEntry(name: "big", kind: "integer", summary: "12345 …").sageSnippet == "big")
    }
}
