import Foundation
import Testing
@testable import Casette

/// The friendly pipeline end-to-end against REAL Sage, through the same
/// seam the UI uses (`ShellModel` → `SessionController` → `SageKernel`):
/// friendly forms compile, their `var('V')` preludes declare what the worker
/// doesn't predefine, the generated Sage evaluates, and the row records the
/// honest input-vs-sage split. Skipped (not failed) without Sage.
@MainActor
@Suite(
    "Friendly compiler integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct FriendlyEvaluationIntegrationTests {
    @Test("factor x^4 - 1: compiles, evaluates, sane kind/plain", .timeLimit(.minutes(5)))
    func factorEndToEnd() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "factor x^4 - 1"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        let row = model.rows[0]
        #expect(row.input == "factor x^4 - 1")
        #expect(row.sage == "factor(x^4 - 1)")
        // Sage 9.5 orders factors its own way — assert content, not order
        // (PROBLEMS.md: don't hard-code string equality on factor output).
        #expect(row.result?.plain.contains("x^2 + 1") == true)
        #expect(row.result?.plain.contains("x + 1") == true)
        #expect(row.result?.kind == "symbolic")

        await controller.shutdown()
    }

    @Test("double integral x*y, x=0..1, y=0..x == 1/8 (the load-bearing nesting)", .timeLimit(.minutes(5)))
    func doubleIntegralEndToEnd() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "double integral x*y, x=0..1, y=0..x"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        #expect(model.rows[0].result?.plain == "1/8")
        #expect(model.rows[0].sage == "integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))")

        await controller.shutdown()
    }

    @Test("preludes work for variables NOTHING predefines (u)", .timeLimit(.minutes(5)))
    func preludeDeclaresNonX() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        // The worker's star-import predefines no variables (PROBLEMS.md
        // V0.5) and the V1.7 boot prelude covers only x/y/z/t — so `u` is
        // declared by the friendly compiler's var('u') prelude alone;
        // without it this NameErrors.
        model.draft = "integral u^2, u=0..2"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        #expect(model.rows[0].result?.plain == "8/3")
        // The symbol table now shows u — declared by the prelude, visibly.
        #expect(await eventually { @MainActor in
            model.symbols.entries.contains { $0.name == "u" }
        })

        await controller.shutdown()
    }

    @Test("ambiguous solve: the chosen candidate evaluates to a solution list", .timeLimit(.minutes(5)))
    func ambiguousChoiceEvaluates() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "solve x*y = 1"
        model.submitDraft()
        guard let pending = model.pendingAmbiguity else {
            Issue.record("expected a pending ambiguity")
            await controller.shutdown()
            return
        }
        #expect(pending.candidates == ["solve(x*y == 1, x)", "solve(x*y == 1, y)"])
        model.resolveAmbiguity(choosing: pending.candidates[0])
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        #expect(model.rows[0].result?.kind == "list")
        // Sage 9.5 prints the solution as `x == (1/y)` inside a list.
        #expect(model.rows[0].result?.plain.contains("x == (1/y)") == true)

        await controller.shutdown()
    }

    @Test("a compile error never reaches Sage; raw Sage still works after", .timeLimit(.minutes(5)))
    func errorNeverSubmitsAndRawSageSurvives() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "integral x^2, x=0.."
        model.submitDraft()
        #expect(model.rows.isEmpty)
        #expect(model.draft == "integral x^2, x=0..")

        // Raw Sage bypasses and evaluates exactly as in V1.3.
        model.draft = "factorial(5)"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        #expect(model.rows[0].sage == "factorial(5)")  // bypass untouched
        #expect(model.rows[0].result?.plain == "120")

        await controller.shutdown()
    }
}
