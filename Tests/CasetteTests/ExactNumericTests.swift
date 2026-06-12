import Foundation
import Testing
@testable import Casette

/// V1.8 exact/numeric controls over the fake transport: the kernel API's
/// V0.8 request fields (`numeric`, `precision_digits`), the `config` op's
/// wire shape, the model's numeric-mode scope (typed submissions only,
/// recorded on the row, never sticky on sidebar flows), and the
/// precision-reapply-after-restart contract.
@MainActor
@Suite("Exact/numeric controls (fake transport)")
struct ExactNumericTests {
    private static func fastConfig() -> SessionController.Configuration {
        var configuration = SessionController.Configuration()
        configuration.pollInterval = .milliseconds(5)
        configuration.readyTimeout = .seconds(2)
        configuration.metadataTimeout = .seconds(2)
        return configuration
    }

    /// A fake worker that answers evals/config/symbols with protocol-shaped
    /// envelopes; a request carrying `numeric:true` gets the V0.8
    /// force-numeric envelope (decimal primary + `exact_value`).
    private nonisolated static func protocolFake() -> FakeKernelTransport {
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            switch request["op"] as? String {
            case "symbols":
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            case "config":
                let digits = request["precision_digits"] as? Int ?? 0
                return [WireFixtures.configResponse(
                    id: id, precisionDigits: digits, ok: digits > 0)]
            default:
                if request["numeric"] as? Bool == true {
                    return [WireFixtures.numericEnvelope(
                        id: id, decimal: "0.3333333333", exactValue: "1/3")]
                }
                return [WireFixtures.okEnvelope(id: id, plain: "1/3", kind: "rational")]
            }
        }
        return fake
    }

    // MARK: - SessionController wire shapes

    @Test("evaluate sends the V0.8 fields only when asked: numeric:true and precision_digits")
    func evaluateWireShape() async {
        let fake = Self.protocolFake()
        let controller = SessionController(configuration: Self.fastConfig()) { fake }
        await controller.connect()

        _ = await controller.evaluate("1/3")
        _ = await controller.evaluate("1/3", numeric: true)
        _ = await controller.evaluate("1/3", precisionDigits: 20)
        _ = await controller.evaluate("1/3", numeric: true, precisionDigits: 5)

        let evals = fake.sentObjects.filter { $0["code"] != nil }
        #expect(evals.count == 4)
        // A plain eval carries NEITHER field (the frozen V1.3 wire shape).
        #expect(evals[0]["numeric"] == nil)
        #expect(evals[0]["precision_digits"] == nil)
        // numeric:true rides only the request that asked for it.
        #expect(evals[1]["numeric"] as? Bool == true)
        #expect(evals[1]["precision_digits"] == nil)
        // A per-request precision override, alone and combined.
        #expect(evals[2]["numeric"] == nil)
        #expect(evals[2]["precision_digits"] as? Int == 20)
        #expect(evals[3]["numeric"] as? Bool == true)
        #expect(evals[3]["precision_digits"] as? Int == 5)

        await controller.shutdown()
    }

    @Test("configure sends the config op and reports the worker's verdict")
    func configureWireShape() async {
        let fake = Self.protocolFake()
        let controller = SessionController(configuration: Self.fastConfig()) { fake }
        await controller.connect()

        let accepted = await controller.configure(precisionDigits: 20)
        #expect(accepted)
        let config = fake.sentObjects.first { $0["op"] as? String == "config" }
        #expect(config?["precision_digits"] as? Int == 20)
        #expect(config?["code"] == nil)  // a config op carries no code

        // The worker rejects an invalid precision (ok:false) — reported.
        let rejected = await controller.configure(precisionDigits: 0)
        #expect(rejected == false)

        await controller.shutdown()
    }

    @Test("configure with no kernel reports failure, never hangs")
    func configureWithoutKernel() async {
        let controller = SessionController(configuration: Self.fastConfig()) {
            let fake = FakeKernelTransport()
            fake.bannerOnSpawn = nil
            fake.eofOnSpawn = true
            return fake
        }
        // Never connected: not connected → false immediately.
        #expect(await controller.configure(precisionDigits: 20) == false)
    }

    // MARK: - ShellModel: the numeric-mode scope

    @Test("numeric mode scopes typed submissions: flag on the wire + recorded on the row, off again after toggle")
    func numericModeScope() async {
        let model = ShellModel()
        let fake = Self.protocolFake()
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        // Numeric ON: the eval carries numeric:true and the row records it.
        model.numericMode = true
        model.draft = "1/3"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        #expect(model.rows[0].numeric == true)
        #expect(model.rows[0].result?.plain == "0.3333333333")
        #expect(model.rows[0].result?.exactValue == "1/3")
        #expect(model.rows[0].result?.primaryIsApprox == true)

        // Numeric OFF: the very next submission is a plain eval again and
        // the row records NO flag (nil, not false — the persisted shape is
        // unchanged for normal rows).
        model.numericMode = false
        model.draft = "1/3"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.count == 2 && model.rows[1].status == .ok })
        #expect(model.rows[1].numeric == nil)
        #expect(model.rows[1].result?.plain == "1/3")
        #expect(model.rows[1].result?.exactValue == nil)

        let numericFlags = fake.sentObjects
            .filter { $0["code"] as? String == "1/3" }
            .map { $0["numeric"] as? Bool }
        #expect(numericFlags == [true, nil])
    }

    @Test("numeric mode never leaks onto sidebar flows; rerun reproduces the row's recorded flag")
    func numericModeSidebarScopeAndRerun() async {
        let model = ShellModel()
        let fake = Self.protocolFake()
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        // A numeric row on the tape…
        model.numericMode = true
        model.draft = "1/3"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })

        // …then the toggle goes OFF. A sidebar inspect is a plain eval.
        model.numericMode = false
        model.inspectSymbol("x")
        #expect(await eventually { @MainActor in model.rows.count == 2 && model.rows[1].status == .ok })
        #expect(model.rows[1].numeric == nil)

        // Rerun of the NUMERIC row is numeric again — the recorded flag,
        // not the toggle's current (off) state.
        model.rerun(rowID: model.rows[0].id)
        #expect(await eventually { @MainActor in model.rows.count == 3 && model.rows[2].status == .ok })
        #expect(model.rows[2].numeric == true)
        #expect(model.rows[2].result?.exactValue == "1/3")

        let numericByCode = fake.sentObjects
            .filter { $0["code"] != nil }
            .map { ($0["code"] as? String ?? "?", $0["numeric"] as? Bool) }
        // Boot prelude plain, 1/3 numeric, x (inspect) plain, 1/3 rerun numeric.
        #expect(numericByCode.map(\.1) == [nil, true, nil, true])
    }

    @Test("numeric mode ON leaves sidebar evaluations plain too (inspect while toggled)")
    func numericModeOnNeverAffectsSidebar() async {
        let model = ShellModel()
        let fake = Self.protocolFake()
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.numericMode = true
        model.inspectSymbol("x")
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        #expect(model.rows[0].numeric == nil)
        let inspect = fake.sentObjects.first { $0["code"] as? String == "x" }
        #expect(inspect?["numeric"] == nil)
    }

    // MARK: - ShellModel: session precision

    @Test("setPrecision updates the session header and sends the config op in queue order")
    func setPrecisionFlow() async {
        let model = ShellModel()
        let fake = Self.protocolFake()
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })
        #expect(model.precisionDigits == 10)
        // Let the boot item finish first — a precision change BEFORE boot
        // completes would (correctly) be re-applied by the boot path itself,
        // which is the other test's subject.
        await model.kernelQueue?.value

        model.draft = "1/3"
        model.submitDraft()
        model.setPrecision(20)
        #expect(model.precisionDigits == 20)
        #expect(model.session.precisionDigits == 20)

        #expect(await eventually { @MainActor in
            fake.sentObjects.contains { $0["op"] as? String == "config" }
        })
        await model.kernelQueue?.value
        // Queue order: boot prelude, the eval, THEN the config op (a
        // precision change never reorders ahead of submitted work).
        let meaningful = fake.sentObjects.compactMap { request -> String? in
            if let code = request["code"] as? String { return code }
            if request["op"] as? String == "config" { return "config" }
            return nil
        }
        #expect(meaningful == [ShellModel.bootPrelude, "1/3", "config"])

        // No-ops and invalid values send nothing and change nothing.
        model.setPrecision(20)
        model.setPrecision(0)
        model.setPrecision(-3)
        #expect(model.precisionDigits == 20)
        await model.kernelQueue?.value
        let configCount = fake.sentObjects.filter { $0["op"] as? String == "config" }.count
        #expect(configCount == 1)
    }

    @Test("boot at the worker default sends NO config op; restart re-applies a changed precision")
    func precisionReappliedAfterRestart() async {
        let model = ShellModel()
        let recorder = SentRecorder()
        let makeFake: @Sendable () -> FakeKernelTransport = {
            let fake = Self.protocolFake()
            recorder.attach(fake)
            return fake
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { makeFake() })

        // Boot with the default 10: the wire carries no config op at all.
        model.draft = "1/3"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        #expect(recorder.meaningful().contains("config") == false)

        // Change the session precision, then restart: the fresh worker
        // resets to 10, so the model must re-apply 20 (after the boot
        // prelude, like the calculator variables).
        model.setPrecision(20)
        await model.kernelQueue?.value
        model.restartKernel()
        #expect(await eventually { @MainActor in
            recorder.meaningful().suffix(2) == [ShellModel.bootPrelude, "config:20"]
        })
        #expect(model.precisionDigits == 20)  // the session setting survived
    }

    // MARK: - Approximate Numerically (the card's one-click approx)

    @Test("approximateNumerically evaluates (expr).n() as a fresh selected row; rows without the approx action offer nothing")
    func approximateNumericallyFlow() async {
        let model = ShellModel()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            var envelope = WireFixtures.okEnvelope(id: id, plain: "8/15", kind: "rational")
            envelope["actions"] = ["numerator", "denominator", "approx", "continued_fraction"]
            return [envelope]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.draft = "1/3 + 1/5"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        #expect(model.rows[0].approximateCommand == "(1/3 + 1/5).n()")

        model.draft = "half-typed next input"
        model.approximateNumerically(rowID: model.rows[0].id)
        #expect(await eventually { @MainActor in model.rows.count == 2 && model.rows[1].status == .ok })
        #expect(model.rows[1].input == "(1/3 + 1/5).n()")
        #expect(model.rows[1].sage == "(1/3 + 1/5).n()")
        #expect(model.selectedRowID == model.rows[1].id)  // selected — Inspector follows
        #expect(model.draft == "half-typed next input")  // the draft is never touched

        // A row whose envelope lists no `approx` action offers no command.
        var statement = model.rows[1]
        statement.result?.actions = ["det", "rank"]
        #expect(statement.approximateCommand == nil)
    }

    // MARK: - SessionRow.numeric (the V1.8 additive schema field)

    @Test("SessionRow.numeric round-trips, is omitted when nil, and legacy rows decode")
    func numericFieldCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // A numeric row encodes the flag and round-trips.
        let numericRow = SessionRow(
            input: "1/3", sage: "1/3", status: .ok, timestamp: .now, numeric: true)
        let encoded = try encoder.encode(numericRow)
        #expect(String(data: encoded, encoding: .utf8)?.contains("\"numeric\"") == true)
        let decoded = try decoder.decode(SessionRow.self, from: encoded)
        #expect(decoded.numeric == true)

        // A normal row OMITS the key entirely — schema v1 files unchanged.
        let plainRow = SessionRow(input: "1/3", sage: "1/3", status: .ok, timestamp: .now)
        let plainEncoded = try encoder.encode(plainRow)
        #expect(String(data: plainEncoded, encoding: .utf8)?.contains("\"numeric\"") == false)

        // A legacy (pre-V1.8) row without the key decodes to nil.
        let legacy = try decoder.decode(SessionRow.self, from: plainEncoded)
        #expect(legacy.numeric == nil)
    }
}

/// Collects the meaningful wire traffic across worker GENERATIONS (each
/// restart mints a fresh transport, so one fake's log isn't enough).
private final class SentRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var fakes: [FakeKernelTransport] = []

    func attach(_ fake: FakeKernelTransport) {
        lock.lock()
        defer { lock.unlock() }
        fakes.append(fake)
    }

    /// Eval codes and config ops, in send order across all generations.
    func meaningful() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return fakes.flatMap { fake in
            fake.sentObjects.compactMap { request -> String? in
                if let code = request["code"] as? String { return code }
                if request["op"] as? String == "config" {
                    return "config:\(request["precision_digits"] as? Int ?? -1)"
                }
                return nil
            }
        }
    }
}
