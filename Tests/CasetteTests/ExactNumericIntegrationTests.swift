import Foundation
import Testing
@testable import Casette

/// V1.8 exact/numeric controls against REAL Sage, through the same seams the
/// UI uses: the V0.8 force-numeric request (decimal primary + preserved
/// `exact_value`, namespace NEVER polluted), the session `config` precision
/// (including the per-request override), and the model-level journey the
/// input pane's controls drive. Skipped (not failed) without Sage.
@MainActor
@Suite(
    "Exact/numeric integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct ExactNumericIntegrationTests {
    @Test("force-numeric: decimal primary + exact_value, and the namespace stays exact", .timeLimit(.minutes(5)))
    func forceNumericNamespacePurity() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        // Store y = 1/3 exactly, then force-numeric the display of y.
        _ = await controller.evaluate("y = 1/3")
        let numeric = await controller.evaluate("y", numeric: true)
        #expect(numeric.status == .ok)
        #expect(numeric.result?.plain.hasPrefix("0.3333333333") == true)
        #expect(numeric.result?.primaryIsApprox == true)
        #expect(numeric.result?.exactValue == "1/3")
        #expect(numeric.result?.approx == nil)  // primary already carries the number

        // The NEXT plain eval is exact again — numeric was display-only.
        let plain = await controller.evaluate("y")
        #expect(plain.result?.plain == "1/3")
        #expect(plain.result?.kind == "rational")
        #expect(plain.result?.exact == true)
        #expect(plain.result?.exactValue == nil)

        // Namespace purity, proven structurally (the V0.8 harness case):
        // the stored y is still a Rational, not a float.
        let parent = await controller.evaluate("parent(y)")
        #expect(parent.result?.plain == "Rational Field")

        // Per-request precision override applies in numeric mode and does
        // NOT change the session (the next default approx is 10 digits).
        let five = await controller.evaluate("y", numeric: true, precisionDigits: 5)
        #expect(five.result?.plain == "0.33333")
        let sessionDefault = await controller.evaluate("1/3 + 1/5")
        #expect(sessionDefault.result?.approx == "0.5333333333")
        #expect(sessionDefault.result?.approxDigits == 10)

        await controller.shutdown()
    }

    @Test("config precision: 20 digits on subsequent approx, back to 10, invalid rejected", .timeLimit(.minutes(5)))
    func sessionPrecisionConfig() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        // Default 10 (the spec's 0.5333333333).
        let ten = await controller.evaluate("1/3 + 1/5")
        #expect(ten.result?.approx == "0.5333333333")

        // Session precision 20 → subsequent approx carries 20 digits.
        #expect(await controller.configure(precisionDigits: 20))
        let twenty = await controller.evaluate("1/3 + 1/5")
        #expect(twenty.result?.approx == "0.53333333333333333333")
        #expect(twenty.result?.approxDigits == 20)

        // An exact symbolic constant honors it too (sqrt(2) to 20 digits).
        let root = await controller.evaluate("sqrt(2)")
        #expect(root.result?.plain == "sqrt(2)")
        #expect(root.result?.exact == true)
        #expect(root.result?.approx == "1.4142135623730950488")

        // Back to 10; an invalid precision is rejected and changes nothing.
        #expect(await controller.configure(precisionDigits: 10))
        #expect(await controller.configure(precisionDigits: 0) == false)
        let backToTen = await controller.evaluate("1/3 + 1/5")
        #expect(backToTen.result?.approx == "0.5333333333")

        await controller.shutdown()
    }

    @Test("the model journey: numeric toggle scope, precision through the UI seam, restart re-applies", .timeLimit(.minutes(5)))
    func modelJourney() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        // Numeric mode ON: 1/3 shows the decimal, keeps the exact form,
        // and the row records the request flag.
        model.numericMode = true
        model.draft = "1/3"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        #expect(model.rows[0].numeric == true)
        #expect(model.rows[0].result?.plain.hasPrefix("0.3333333333") == true)
        #expect(model.rows[0].result?.exactValue == "1/3")

        // Toggle OFF: the very next 1/3 is exact again (numeric never
        // pollutes global behavior).
        model.numericMode = false
        model.draft = "1/3"
        model.submitDraft()
        #expect(await eventually { @MainActor in
            model.rows.count == 2 && model.rows[1].status == .ok
        })
        #expect(model.rows[1].numeric == nil)
        #expect(model.rows[1].result?.plain == "1/3")
        #expect(model.rows[1].result?.exact == true)

        // Precision through the UI seam: 20 digits on the next approx.
        model.setPrecision(20)
        model.draft = "1/3 + 1/5"
        model.submitDraft()
        #expect(await eventually { @MainActor in
            model.rows.count == 3 && model.rows[2].status == .ok
        })
        #expect(model.rows[2].result?.approx == "0.53333333333333333333")

        // Restart resets the worker (fresh namespace AND precision 10);
        // the model re-applies the session's 20 along with the boot prelude.
        // A sentinel binding makes "the restart pipeline finished" honestly
        // observable: the restart Task's FINAL step is the symbols refresh,
        // so the sentinel vanishing proves the prelude AND the config op
        // already went through (no race against the next submission).
        model.draft = "sentinel = 5"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(60)) { @MainActor in
            model.symbols.entries.contains { $0.name == "sentinel" }
        })
        model.restartKernel()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            !model.symbols.entries.isEmpty
                && !model.symbols.entries.contains { $0.name == "sentinel" }
        })
        model.draft = "1/3 + 1/5"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(60)) { @MainActor in
            model.rows.count == 5 && model.rows[4].status == .ok
        })
        #expect(model.rows[4].result?.approx == "0.53333333333333333333")

        // The card's one-click approx on an exact result: a fresh, selected
        // `(…).n()` row.
        model.approximateNumerically(rowID: model.rows[4].id)
        #expect(await eventually(timeout: .seconds(60)) { @MainActor in
            model.rows.count == 6 && model.rows[5].status == .ok
        })
        #expect(model.rows[5].input == "(1/3 + 1/5).n()")
        #expect(model.rows[5].result?.plain.hasPrefix("0.533333333333333") == true)
        #expect(model.selectedRowID == model.rows[5].id)

        await controller.shutdown()
    }
}
