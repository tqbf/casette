import Foundation
import Testing
@testable import Casette

/// The V1.6 sidebar flows at the model seam, over the fake transport:
/// forget goes through the kernel as a real row and refreshes symbols,
/// rerun re-submits through the normal path (preludes included, draft
/// untouched), inspect selects + lands on the Inspector, and action
/// commands insert or evaluate.
@MainActor
@Suite("ShellModel sidebar flows (fake transport)")
struct SidebarFlowTests {
    private static func fastConfig() -> SessionController.Configuration {
        var configuration = SessionController.Configuration()
        configuration.pollInterval = .milliseconds(5)
        configuration.readyTimeout = .seconds(2)
        configuration.metadataTimeout = .seconds(2)
        return configuration
    }

    /// A fake worker holding one symbol `n` until it sees `del n`, after
    /// which the symbol table reports empty — the forget round-trip.
    private static func forgettingFake(order: OrderLog) -> FakeKernelTransport {
        let fake = FakeKernelTransport()
        let deleted = LockedFlag()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                let entries: [(name: String, kind: String, summary: String)] =
                    deleted.value ? [] : [("n", "integer", "5")]
                return [WireFixtures.symbolsResponse(id: id, entries: entries)]
            }
            let code = request["code"] as? String ?? "?"
            order.record(code)
            if code == "del n" { deleted.set() }
            return [WireFixtures.okEnvelope(id: id, plain: "", kind: "none")]
        }
        return fake
    }

    @Test("forget evaluates `del name` through the kernel as a visible row and refreshes symbols")
    func forgetFlowsThroughKernel() async {
        let model = ShellModel()
        let order = OrderLog()
        let fake = Self.forgettingFake(order: order)
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })
        // Boot settles: prelude evaluated, the symbol table shows n.
        #expect(await eventually { @MainActor in model.symbols.entries.map(\.name) == ["n"] })

        model.draft = "untouched draft"
        model.forgetSymbol("n")

        // The del is a REGULAR tape row through the normal submit path…
        #expect(model.rows.count == 1)
        #expect(model.rows[0].input == "del n")
        #expect(await eventually { @MainActor in model.rows[0].status == .ok })
        // …the kernel really evaluated it…
        #expect(order.values.contains("del n"))
        // …the symbol table refreshed (n is gone)…
        #expect(await eventually { @MainActor in model.symbols.entries.isEmpty })
        // …and the draft was never touched.
        #expect(model.draft == "untouched draft")
    }

    @Test("rerun re-evaluates a prior row through the normal path; draft and original untouched")
    func rerunReevaluates() async {
        let model = ShellModel()
        let order = OrderLog()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            order.record(request["code"] as? String ?? "?")
            return [WireFixtures.okEnvelope(id: id, plain: "4")]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.draft = "2 + 2"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        let originalID = model.rows[0].id

        model.draft = "half-typed draft"
        model.rerun(rowID: originalID)

        #expect(model.rows.count == 2)
        #expect(model.rows[1].input == "2 + 2")
        #expect(model.rows[1].id != originalID)  // a FRESH row; the original stands
        #expect(await eventually { @MainActor in model.rows[1].status == .ok })
        #expect(order.values.filter { $0 == "2 + 2" }.count == 2)
        #expect(model.draft == "half-typed draft")
    }

    @Test("rerunning a friendly row regenerates its var() preludes")
    func rerunRegeneratesPreludes() async {
        let model = ShellModel()
        let order = OrderLog()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            order.record(request["code"] as? String ?? "?")
            return [WireFixtures.okEnvelope(id: id, plain: "8/3", kind: "symbolic")]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.draft = "integral t^2, t=0..2"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })

        model.rerun(rowID: model.rows[0].id)
        #expect(await eventually { @MainActor in model.rows.count == 2 && model.rows[1].status == .ok })
        // Boot prelude, then BOTH submissions each led by var('t').
        #expect(order.values == [
            ShellModel.bootPrelude,
            "var('t')", "integrate(t^2, (t, 0, 2))",
            "var('t')", "integrate(t^2, (t, 0, 2))",
        ])
        #expect(model.rows[1].sage == "integrate(t^2, (t, 0, 2))")
    }

    @Test("inspect evaluates the bare name, selects the new row, lands on the Inspector tab")
    func inspectSelectsAndSwitchesTab() async {
        let model = ShellModel()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [("n", "integer", "5")])]
            }
            return [WireFixtures.okEnvelope(id: id, plain: "5")]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })
        #expect(model.sidebarTab == .symbols)

        model.inspectSymbol("n")
        #expect(model.rows.count == 1)
        #expect(model.rows[0].input == "n")
        #expect(model.selectedRowID == model.rows[0].id)
        #expect(model.sidebarTab == .inspector)
        #expect(await eventually { @MainActor in model.rows[0].status == .ok })
        #expect(model.rows[0].result?.plain == "5")
    }

    @Test("evaluateActionCommand submits the command and selects the fresh row")
    func evaluateActionCommandSubmitsAndSelects() async {
        let model = ShellModel()
        let order = OrderLog()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            order.record(request["code"] as? String ?? "?")
            return [WireFixtures.okEnvelope(id: id, plain: "-2")]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.draft = "keep me"
        model.evaluateActionCommand("(matrix([[1,2],[3,4]])).det()")
        #expect(model.rows.count == 1)
        #expect(model.selectedRowID == model.rows[0].id)
        #expect(await eventually { @MainActor in model.rows[0].status == .ok })
        #expect(order.values.contains("(matrix([[1,2],[3,4]])).det()"))
        #expect(model.rows[0].result?.plain == "-2")
        #expect(model.draft == "keep me")  // evaluate-now never clobbers the draft
    }

    @Test("insertSymbolIntoDraft separates identifiers, never merges names")
    func insertSymbolSpacing() {
        let model = ShellModel()
        model.insertSymbolIntoDraft("n")
        #expect(model.draft == "n")  // empty draft → just the name
        model.draft = "1 + "
        model.insertSymbolIntoDraft("n")
        #expect(model.draft == "1 + n")  // after a space: no extra space
        model.draft = "2*"
        model.insertSymbolIntoDraft("n")
        #expect(model.draft == "2*n")  // after an operator: tight
        model.draft = "foo"
        model.insertSymbolIntoDraft("n")
        #expect(model.draft == "foo n")  // identifier boundary protected
    }

    @Test("Actions-tab insert is the plain draft replacement (previewable before Return)")
    func insertActionCommandReplacesDraft() {
        let model = ShellModel()
        model.draft = "old"
        model.insertIntoDraft("(8/15).n()")
        #expect(model.draft == "(8/15).n()")
    }
}

/// Records eval order across the fake's @Sendable responder.
private final class OrderLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ value: String) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(value)
    }
}

/// A tiny thread-safe boolean for scripting the fake across @Sendable hops.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        stored = true
    }
}
