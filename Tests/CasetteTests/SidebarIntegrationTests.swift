import Foundation
import Testing
@testable import Casette

/// The V1.6 sidebar journey against REAL Sage, through the same seam the UI
/// uses: define a symbol → it's live in the table → forget it through the
/// kernel → it's gone; evaluate a matrix → action-built commands evaluate.
/// Skipped (not failed) without Sage.
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

    @Test("matrix actions: built commands evaluate", .timeLimit(.minutes(5)))
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
        #expect(row.result?.actions.contains("change_ring_RDF") == true)
        #expect(row.result?.actions.contains("svd") == false)
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

        guard let columnSpace = ResultAction(name: "column_space").command(wrapping: expression),
              let rightKernel = ResultAction(name: "right_kernel")
                .command(wrapping: "matrix([[1,2],[2,4]])")
        else {
            Issue.record("matrix row should offer basis commands")
            await controller.shutdown()
            return
        }
        #expect(columnSpace == "(matrix([[1,2],[3,4]])).column_space().basis()")
        model.evaluateActionCommand(columnSpace)
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.count == 3 && model.rows[2].status == .ok
        })
        #expect(model.rows[2].result?.kind == "list")
        #expect(model.rows[2].result?.plain.contains("(1, 1)") == true)

        #expect(rightKernel == "(matrix([[1,2],[2,4]])).right_kernel().basis()")
        model.evaluateActionCommand(rightKernel)
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.count == 4 && model.rows[3].status == .ok
        })
        #expect(model.rows[3].result?.plain.contains("(2, -1)") == true)

        guard let changeRing = ResultAction(name: "change_ring_RDF").command(wrapping: expression)
        else {
            Issue.record("matrix row should offer an RDF conversion command")
            await controller.shutdown()
            return
        }
        #expect(changeRing == "(matrix([[1,2],[3,4]])).change_ring(RDF)")
        model.evaluateActionCommand(changeRing)
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.count == 5 && model.rows[4].status == .ok
        })
        #expect(model.rows[4].result?.kind == "matrix")
        #expect(model.rows[4].result?.actions.contains("svd") == true)

        guard let rdfExpression = model.rows[4].reusableExpression,
              let svd = ResultAction(name: "svd").command(wrapping: rdfExpression)
        else {
            Issue.record("RDF matrix row should offer SVD")
            await controller.shutdown()
            return
        }
        model.evaluateActionCommand(svd)
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.count == 6 && model.rows[5].status == .ok
        })
        #expect(model.rows[5].result?.plain.contains("U =") == true)
        #expect(model.rows[5].result?.plain.contains("S =") == true)
        #expect(model.rows[5].result?.plain.contains("V =") == true)
        #expect(model.rows[5].result?.latex?.contains("U =") == true)
        #expect(model.rows[5].result?.latex?.contains("S =") == true)
        #expect(model.rows[5].result?.latex?.contains("V =") == true)

        await controller.shutdown()
    }
}
