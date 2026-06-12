import Foundation
import Testing
@testable import Casette

/// The UI seam end-to-end over a fake transport: submit → pending row →
/// completed envelope in place → symbols refreshed, with the kernel state
/// stream driving `kernelState`/`kernelIssue`.
@MainActor
@Suite("ShellModel kernel wiring (fake transport)")
struct ShellModelKernelTests {
    private static func fastConfig() -> SessionController.Configuration {
        var configuration = SessionController.Configuration()
        configuration.pollInterval = .milliseconds(5)
        configuration.readyTimeout = .seconds(2)
        configuration.metadataTimeout = .seconds(2)
        return configuration
    }

    /// A fake worker that answers every eval with `4` and reports one symbol.
    private static func answeringFake() -> FakeKernelTransport {
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [("n", "integer", "4")])]
            }
            return [WireFixtures.okEnvelope(id: id, plain: "4", approx: nil)]
        }
        return fake
    }

    @Test("submit evaluates: pending → completed in place, symbols refresh, state streams")
    func submitEvaluatesThroughKernel() async {
        let model = ShellModel()
        let fake = Self.answeringFake()
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.draft = "2 + 2"
        model.submitDraft()
        #expect(model.rows.count == 1)
        let rowID = model.rows[0].id

        #expect(await eventually { @MainActor in model.rows[0].status == .ok })
        #expect(model.rows[0].id == rowID)  // completed IN PLACE, identity stable
        #expect(model.rows[0].result?.plain == "4")
        #expect(model.rows[0].duration != nil)
        // The sidebar refreshed from the real symbols op.
        #expect(await eventually { @MainActor in model.symbols.entries.map(\.name) == ["n"] })
        // The status stream drove the model's kernel state.
        #expect(await eventually { @MainActor in model.kernelState == .completed })
        #expect(model.kernelIssue == nil)
    }

    @Test("rapid submissions evaluate strictly in tape order (serial queue)")
    func rapidSubmissionsStayOrdered() async {
        let model = ShellModel()
        let order = OrderRecorder()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            order.record(request["code"] as? String ?? "?")
            return [WireFixtures.okEnvelope(id: id, plain: "ok", kind: "text")]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        for input in ["a = 1", "b = 2", "a + b"] {
            model.draft = input
            model.submitDraft()
        }
        #expect(await eventually { @MainActor in model.rows.allSatisfy { $0.status == .ok } })
        // The boot prelude (the calculator variables var('x, y, z, t'))
        // leads, then the submissions strictly in tape order.
        #expect(order.values == [ShellModel.bootPrelude, "a = 1", "b = 2", "a + b"])
    }

    @Test("boot and restart each apply the var('x, y, z, t') prelude — the calculator-variables contract")
    func bootPreludeAppliedAtBootAndRestart() async {
        let model = ShellModel()
        let order = OrderRecorder()
        // The factory mints a FRESH transport per generation (boot, restart),
        // all recording into one shared order log.
        let makeFake: @Sendable () -> FakeKernelTransport = {
            let fake = FakeKernelTransport()
            fake.respondToSend = { request in
                guard let id = request["id"] as? String else { return [] }
                if request["op"] as? String == "symbols" {
                    return [WireFixtures.symbolsResponse(id: id, entries: [
                        ("t", "symbolic", "t"), ("x", "symbolic", "x"),
                        ("y", "symbolic", "y"), ("z", "symbolic", "z"),
                    ])]
                }
                order.record(request["code"] as? String ?? "?")
                return [WireFixtures.okEnvelope(id: id, plain: "x", kind: "symbolic")]
            }
            return fake
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { makeFake() })

        // Boot: the prelude is the FIRST eval, before any submission, and
        // the sidebar refreshes — all four calculator variables are visible
        // from boot.
        #expect(await eventually { @MainActor in order.values == ["var('x, y, z, t')"] })
        #expect(await eventually { @MainActor in
            model.symbols.entries.map(\.name) == ["t", "x", "y", "z"]
        })

        // Raw-Sage bypass (no friendly preludes) rides on the boot prelude.
        model.draft = "expand((x+1)^8)"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        #expect(order.values == ["var('x, y, z, t')", "expand((x+1)^8)"])

        // Restart boots a fresh namespace — the prelude must be re-applied.
        model.restartKernel()
        #expect(await eventually { @MainActor in
            order.values == ["var('x, y, z, t')", "expand((x+1)^8)", "var('x, y, z, t')"]
        })
    }

    @Test("curly quotes are normalized at submit: the wire and the row both see ASCII")
    func smartQuotesNormalizedOnTheWire() async {
        let model = ShellModel()
        let order = OrderRecorder()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            order.record(request["code"] as? String ?? "?")
            return [WireFixtures.okEnvelope(id: id, plain: "", kind: "none")]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.draft = "print(\u{201C}hello\u{201D})"  // smart-quoted paste
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        // Sage received Python-valid ASCII quotes…
        #expect(order.values.last == "print(\"hello\")")
        // …and the row honestly records exactly what was evaluated.
        #expect(model.rows[0].input == "print(\"hello\")")
        #expect(model.rows[0].sage == "print(\"hello\")")
    }

    @Test("a boot failure surfaces as an honest issue on the model")
    func bootFailureSurfacesIssue() async {
        let model = ShellModel()
        model.connectKernel(
            SessionController(configuration: Self.fastConfig()) {
                throw KernelSetupError.sageNotFound(searched: [])
            })
        #expect(await eventually { @MainActor in model.kernelState == .notConnected && model.kernelIssue != nil })
        #expect(model.kernelIssue?.contains("SageMath") == true)
        #expect(model.kernelSetupFailed == true)
        model.openDoctor()
        #expect(model.isDoctorPresented == true)

        // Submitting against the dead kernel yields a readable error row,
        // not a forever-spinner.
        model.draft = "2 + 2"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows[0].status == .error })
        #expect(model.rows[0].errorType == "Sage not running")
    }
}

/// Records eval order across the fake's @Sendable responder.
private final class OrderRecorder: @unchecked Sendable {
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
