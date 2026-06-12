import Foundation
import Testing
@testable import Casette

/// The V1.6 sidebar journey against REAL Sage, through the same seam the UI
/// uses: define a symbol → it's live in the table → forget it through the
/// kernel → it's gone; evaluate a matrix → the det action's built command
/// evaluates to the right determinant. Skipped (not failed) without Sage.
@MainActor
@Suite(
    "Sidebar integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct SidebarIntegrationTests {
    @Test("forget round-trip: n appears in symbols, `del n` removes it", .timeLimit(.minutes(5)))
    func forgetRoundTrip() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "n = 104729"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.symbols.entries.contains { $0.name == "n" && $0.summary == "104729" }
        })

        model.forgetSymbol("n")
        // The forget is a visible tape row that really evaluated…
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.last?.input == "del n" && model.rows.last?.status == .ok
        })
        // …and the refreshed symbol table no longer lists n.
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            !model.symbols.entries.contains { $0.name == "n" }
        })

        await controller.shutdown()
    }

    @Test("matrix det action: the built command evaluates to the determinant", .timeLimit(.minutes(5)))
    func matrixDetAction() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "matrix([[1,2],[3,4]])"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        let row = model.rows[0]
        #expect(row.result?.kind == "matrix")
        // The envelope's own action list drives the tab…
        #expect(row.result?.actions.contains("det") == true)
        // …and the command built from the row's reusable expression
        // evaluates to the real determinant.
        guard let expression = row.reusableExpression,
              let command = ResultAction(name: "det").command(wrapping: expression)
        else {
            Issue.record("matrix row should offer a reusable expression + det command")
            await controller.shutdown()
            return
        }
        #expect(command == "(matrix([[1,2],[3,4]])).det()")
        model.evaluateActionCommand(command)
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.count == 2 && model.rows[1].status == .ok
        })
        #expect(model.rows[1].result?.plain == "-2")
        #expect(model.selectedRowID == model.rows[1].id)

        await controller.shutdown()
    }
}
