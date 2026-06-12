import Foundation
import Testing
@testable import Casette

/// A Sendable invocation counter for transport factories.
private final class FactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    private var _fakes: [FakeKernelTransport] = []

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calls
    }

    var fakes: [FakeKernelTransport] {
        lock.lock()
        defer { lock.unlock() }
        return _fakes
    }

    func record(_ fake: FakeKernelTransport? = nil) {
        lock.lock()
        defer { lock.unlock() }
        _calls += 1
        if let fake { _fakes.append(fake) }
    }
}

private final class EvalLog: @unchecked Sendable {
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

/// V1.9 end-to-end over fakes: incremental atomic saves after every row,
/// restore (with and without Sage), crash recovery, replay (order, preludes,
/// numeric honor, supersede), schema refusal, and the provenance marks.
@MainActor
@Suite("Session persistence flows (V1.9)")
struct SessionPersistenceFlowTests {
    private static func fastConfig() -> SessionController.Configuration {
        var configuration = SessionController.Configuration()
        configuration.pollInterval = .milliseconds(5)
        configuration.readyTimeout = .seconds(2)
        configuration.metadataTimeout = .seconds(2)
        return configuration
    }

    /// A fake worker answering every eval with `4` and empty symbols.
    /// nonisolated: it's built inside the (Sendable) transport factory.
    private nonisolated static func answeringFake() -> FakeKernelTransport {
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            if request["op"] as? String == "config" {
                return [WireFixtures.configResponse(
                    id: id, precisionDigits: request["precision_digits"] as? Int ?? 10)]
            }
            return [WireFixtures.okEnvelope(id: id, plain: "4", approx: nil)]
        }
        return fake
    }

    private func decodeSessionFile(_ store: SessionStore) throws -> Session {
        let data = try Data(contentsOf: store.sessionFileURL)
        return try SessionStore.makeDecoder().decode(Session.self, from: data)
    }

    // MARK: Save + crash recovery

    @Test("every completed row is on disk; a second model (the relaunch) restores them — crash recovery IS the per-row save")
    func incrementalSaveAndCrashRecovery() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }

        let model = ShellModel()
        model.restoreLastSession(from: store)  // empty dir → fresh, store attached
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { Self.answeringFake() })

        model.draft = "2 + 2"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        var onDisk = try decodeSessionFile(store)
        #expect(onDisk.rows.count == 1)
        #expect(onDisk.rows[0].result?.plain == "4")
        #expect(onDisk.rows[0].status == .ok)

        model.draft = "3 + 1"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.count == 2 && model.rows[1].status == .ok })
        onDisk = try decodeSessionFile(store)
        #expect(onDisk.rows.count == 2)

        // "Relaunch": a brand-new model over the same store. There is NO
        // quit-time save in the design — the per-row saves are everything a
        // crash leaves behind, and they're sufficient.
        let relaunched = ShellModel()
        relaunched.restoreLastSession(from: store)
        #expect(relaunched.rows.count == 2)
        #expect(relaunched.rows.map(\.id) == model.rows.map(\.id))
        #expect(relaunched.rows[0].result?.plain == "4")
        #expect(relaunched.provenanceMark(for: relaunched.rows[0]) == .cached)
    }

    @Test("a row persisted mid-eval (the crash case) restores as interrupted, not an eternal spinner")
    func staleRunningRowRestoresAsInterrupted() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        var session = fixtureSession()
        session.rows.append(SessionRow(
            input: "factorial(10^8)", sage: "factorial(10^8)",
            status: .running, timestamp: .now))
        try store.save(session)

        let model = ShellModel()
        model.restoreLastSession(from: store)
        let restored = model.rows.last
        #expect(restored?.status == .interrupted)
        #expect(restored?.result?.error?.type == "Interrupted")
        #expect(restored?.result?.plain.contains("quit before") == true)
        // And the honest state is back on disk too.
        let onDisk = try decodeSessionFile(store)
        #expect(onDisk.rows.last?.status == .interrupted)
    }

    // MARK: Restore without Sage

    @Test("restore needs NO worker: the tape is back, marked cached, with zero transport spawns")
    func restoreWithoutSageSpawnsNothing() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try store.save(fixtureSession(precisionDigits: 20))

        let recorder = FactoryRecorder()
        let model = ShellModel()
        model.restoreLastSession(from: store)

        // The tape restored render-ready BEFORE any kernel exists.
        #expect(recorder.calls == 0)
        #expect(model.rows.count == 4)
        #expect(model.rows[0].result?.latex == "{\\left(x^{2} + 1\\right)}")
        #expect(model.rows[3].result?.exactValue == "1/3")
        #expect(model.session.precisionDigits == 20)
        #expect(model.rows.allSatisfy { model.provenanceMark(for: $0) == .cached })
        // The restored plot's artifacts honestly read missing (V1.7's box).
        #expect(model.rows[1].result?.artifacts.allSatisfy { $0.status == .missing } == true)
        // Up-arrow history covers the restored inputs.
        #expect(model.inputHistory.entries.contains("factor x^4 - 1"))

        // Now Sage discovery fails (the V1.10 Doctor hook point): the banner
        // state arrives, the tape stays, and nothing was ever spawned.
        model.connectKernel(SessionController(configuration: Self.fastConfig()) {
            recorder.record()
            throw KernelSetupError.sageNotFound(searched: ["/nowhere/sage"])
        })
        #expect(await eventually { @MainActor in model.kernelIssue != nil })
        #expect(model.kernelState == .notConnected)
        #expect(recorder.calls == 1)  // attempted once, threw — no transport, no spawn
        #expect(model.rows.count == 4)
        #expect(model.rows[0].result?.plain == "(x^2 + 1)*(x + 1)*(x - 1)")
        #expect(model.canReplaySession == false)  // replay honestly disabled
    }

    @Test("a restored non-default precision is re-applied to the worker at boot")
    func restoredPrecisionIsReappliedAtBoot() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try store.save(fixtureSession(precisionDigits: 20))

        let fake = Self.answeringFake()
        let model = ShellModel()
        model.restoreLastSession(from: store)
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        #expect(await eventually { @MainActor in
            fake.sentObjects.contains { $0["op"] as? String == "config" }
        })
        let config = fake.sentObjects.first { $0["op"] as? String == "config" }
        #expect(config?["precision_digits"] as? Int == 20)
    }

    // MARK: Header + UI-state changes persist

    @Test("setPrecision and toggleExpanded reach the file (header and row UI state)")
    func headerAndExpandedChangesPersist() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }

        let model = ShellModel()
        model.restoreLastSession(from: store)  // fresh, attaches the store
        let rowID = model.append(CompiledInput.bypass("1 + 1"))
        model.complete(rowID: rowID, with: Evaluation(
            status: .ok,
            result: PersistedEnvelope(kind: "integer", plain: "2"),
            duration: 0.001))
        model.setPrecision(15)
        model.toggleExpanded(rowID: rowID)

        let onDisk = try decodeSessionFile(store)
        #expect(onDisk.precisionDigits == 15)
        #expect(onDisk.rows.count == 1)
        #expect(onDisk.rows[0].expanded == true)
        #expect(onDisk.rows[0].result?.plain == "2")
    }

    // MARK: Provenance marks

    @Test("marks: restored rows read cached, fresh rows read nothing, an edited restored row loses its mark")
    func provenanceMarksAreTransientAndHonest() throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try store.save(fixtureSession())

        let model = ShellModel()
        model.restoreLastSession(from: store)
        let restoredID = model.rows[0].id
        #expect(model.provenanceMark(for: model.rows[0]) == .cached)

        // A fresh row this run: no mark (fresh is the unmarked default).
        let freshID = model.append(CompiledInput.bypass("2 + 2"))
        model.complete(rowID: freshID, with: Evaluation(
            status: .ok, result: PersistedEnvelope(kind: "integer", plain: "4"),
            duration: 0.001))
        let fresh = model.rows.first { $0.id == freshID }!
        #expect(model.provenanceMark(for: fresh) == nil)
        // (Even though its PERSISTED provenance is `cached` — that's what a
        // later restore will load; the mark is about THIS run.)
        #expect(fresh.provenance.kind == .cached)

        // Editing a restored row discards its restored content — and mark.
        model.edit(rowID: restoredID, input: "9 * 9")
        let edited = model.rows.first { $0.id == restoredID }!
        #expect(model.provenanceMark(for: edited) == nil)
    }

    @Test("restored cached rows are visible but not live command sources until replayed")
    func cachedRowsAreNotLiveCommandSourcesUntilReplay() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try store.save(fixtureSession())

        let order = EvalLog()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            order.record(request["code"] as? String ?? "?")
            return [WireFixtures.okEnvelope(id: id, plain: "4", kind: "integer")]
        }

        let model = ShellModel()
        model.restoreLastSession(from: store)
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })
        #expect(await eventually { @MainActor in model.kernelState.isConnected })

        let restoredID = model.rows[0].id
        #expect(model.provenanceMark(for: model.rows[0]) == .cached)
        #expect(!model.rowIsLiveInKernel(model.rows[0]))

        model.rerun(rowID: restoredID)
        model.approximateNumerically(rowID: restoredID)
        model.evaluateActionCommand("(x^2 + 1).factor()", sourceRowID: restoredID)

        #expect(model.rows.count == 4)
        #expect(order.values == [ShellModel.bootPrelude])

        model.replaySession()
        #expect(await eventually { @MainActor in
            !model.isReplaying && model.rows.allSatisfy { $0.provenance.kind == .replayed }
        })
        #expect(model.provenanceMark(for: model.rows[0]) == .replayed)
        #expect(model.rowIsLiveInKernel(model.rows[0]))
    }

    // MARK: Replay

    @Test("replay: fresh worker, tape order, preludes, recorded numeric honored, provenance flips, no spurious supersession")
    func replayReplaysInOrderHonoringNumeric() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }

        // A state-dependent pair + a friendly row needing a prelude + a
        // numeric row. Cached envelopes match what the fake will answer, so
        // a correct replay shows NO supersession (the deterministic case).
        let cachedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let session = Session(
            created: cachedAt, updated: cachedAt, precisionDigits: 10,
            rows: [
                SessionRow(
                    input: "A = matrix([[1,2],[3,4]])", sage: "A = matrix([[1,2],[3,4]])",
                    result: PersistedEnvelope(kind: "none", plain: "", latex: "", repr: ""),
                    status: .ok, timestamp: cachedAt,
                    provenance: Provenance(kind: .cached, cachedAt: cachedAt)),
                SessionRow(
                    input: "A.eigenvalues()", sage: "A.eigenvalues()",
                    result: PersistedEnvelope(
                        kind: "list", plain: "[-0.3722813232690143?, 5.372281323269014?]",
                        latex: "[-0.3722813232690143?, 5.372281323269014?]",
                        repr: "[-0.3722813232690143?, 5.372281323269014?]"),
                    status: .ok, timestamp: cachedAt,
                    provenance: Provenance(kind: .cached, cachedAt: cachedAt)),
                SessionRow(
                    input: "integral t^2, t=0..2", sage: "integrate(t^2, (t, 0, 2))",
                    result: PersistedEnvelope(
                        kind: "rational", plain: "8/3", latex: "8/3", repr: "8/3"),
                    status: .ok, timestamp: cachedAt,
                    provenance: Provenance(kind: .cached, cachedAt: cachedAt)),
                SessionRow(
                    input: "1/3", sage: "1/3",
                    result: PersistedEnvelope(
                        kind: "rational", plain: "0.3333333333", latex: "1/3",
                        exact: true, primaryIsApprox: true, exactValue: "1/3"),
                    status: .ok, timestamp: cachedAt,
                    provenance: Provenance(kind: .cached, cachedAt: cachedAt),
                    numeric: true),
            ])
        try store.save(session)

        // Scripted per-code answers (replay spawns a SECOND fake generation).
        let recorder = FactoryRecorder()
        let makeFake: @Sendable () -> FakeKernelTransport = {
            let fake = FakeKernelTransport()
            fake.respondToSend = { request in
                guard let id = request["id"] as? String else { return [] }
                if request["op"] as? String == "symbols" {
                    return [WireFixtures.symbolsResponse(id: id, entries: [])]
                }
                switch request["code"] as? String {
                case "A = matrix([[1,2],[3,4]])":
                    return [WireFixtures.okEnvelope(id: id, plain: "", kind: "none")]
                case "A.eigenvalues()":
                    return [WireFixtures.okEnvelope(
                        id: id, plain: "[-0.3722813232690143?, 5.372281323269014?]", kind: "list")]
                case "integrate(t^2, (t, 0, 2))":
                    return [WireFixtures.okEnvelope(id: id, plain: "8/3", kind: "rational")]
                case "1/3":
                    return [WireFixtures.numericEnvelope(
                        id: id, decimal: "0.3333333333", exactValue: "1/3")]
                default:  // boot prelude, var('t'), …
                    return [WireFixtures.okEnvelope(id: id, plain: "", kind: "none")]
                }
            }
            return fake
        }

        let model = ShellModel()
        model.restoreLastSession(from: store)
        model.connectKernel(SessionController(configuration: Self.fastConfig()) {
            let fake = makeFake()
            recorder.record(fake)
            return fake
        })
        #expect(await eventually { @MainActor in model.kernelState.isConnected })
        #expect(model.canReplaySession)

        model.replaySession()
        #expect(model.isReplaying)
        #expect(await eventually { @MainActor in
            !model.isReplaying && model.rows.allSatisfy { $0.provenance.kind == .replayed }
        })

        // Replay restarted into a FRESH worker (a second transport).
        #expect(recorder.calls == 2)
        let replayWire = recorder.fakes[1].sentObjects
        let codes = replayWire.compactMap { $0["code"] as? String }
        #expect(codes.filter { !$0.contains("__casette_tape_refs") } == [
            ShellModel.bootPrelude,
            "A = matrix([[1,2],[3,4]])",
            "A.eigenvalues()",
            "var('t')",  // the friendly row's prelude, re-emitted
            "integrate(t^2, (t, 0, 2))",
            "1/3",
        ])
        // The numeric row replayed with its RECORDED request shape.
        let numericRequest = replayWire.first { $0["code"] as? String == "1/3" }
        #expect(numericRequest?["numeric"] as? Bool == true)
        // No other eval carried the numeric flag.
        #expect(replayWire.filter { $0["numeric"] as? Bool == true }.count == 1)

        // Provenance: replayed, original cachedAt RETAINED, replayedAt fresh.
        for row in model.rows {
            #expect(row.provenance.kind == .replayed)
            #expect(row.provenance.cachedAt == cachedAt)
            #expect(row.provenance.replayedAt != nil)
            #expect(model.provenanceMark(for: row) == .replayed)
        }
        // Deterministic results → ZERO spurious supersession.
        #expect(model.rows.allSatisfy { $0.supersededCache == nil })
        // The numeric row still displays numerically after replay.
        #expect(model.rows[3].result?.primaryIsApprox == true)
        #expect(model.rows[3].result?.exactValue == "1/3")
        // And the replayed tape is on disk.
        let onDisk = try decodeSessionFile(store)
        #expect(onDisk.rows.allSatisfy { $0.provenance.kind == .replayed })
    }

    @Test("replay: a DIFFERING result supersedes — replaced, with the cached envelope retained + a reason")
    func replayDifferenceSupersedesKeepingCache() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        let cachedAt = Date(timeIntervalSince1970: 1_700_000_100)
        var session = fixtureSession()
        session.rows = [SessionRow(
            input: "random()", sage: "random()",
            result: PersistedEnvelope(kind: "real", plain: "0.111", latex: "0.111", repr: "0.111"),
            status: .ok, timestamp: cachedAt,
            provenance: Provenance(kind: .cached, cachedAt: cachedAt))]
        try store.save(session)

        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            if request["code"] as? String == "random()" {
                return [WireFixtures.okEnvelope(id: id, plain: "0.999", kind: "real")]
            }
            return [WireFixtures.okEnvelope(id: id, plain: "", kind: "none")]
        }
        let model = ShellModel()
        model.restoreLastSession(from: store)
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })
        #expect(await eventually { @MainActor in model.kernelState.isConnected })

        model.replaySession()
        #expect(await eventually { @MainActor in
            !model.isReplaying && model.rows[0].provenance.kind == .replayed
        })

        let row = model.rows[0]
        #expect(row.result?.plain == "0.999")  // replayed value is CURRENT
        #expect(row.supersededCache?.envelope.plain == "0.111")  // old one KEPT
        #expect(row.supersededCache?.reason == "plain changed")
        #expect(row.supersededCache?.cachedAt == cachedAt)
        let onDisk = try decodeSessionFile(store)
        #expect(onDisk.rows[0].supersededCache?.envelope.plain == "0.111")
    }

    // MARK: Schema refusal must not clobber

    @Test("a refused (newer) schema disables saving — this run NEVER overwrites the future's file")
    func refusedSchemaNeverClobbersTheFile() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }
        try FileManager.default.createDirectory(
            at: store.directory, withIntermediateDirectories: true)
        let future = #"{"schemaVersion": 99, "somethingNew": true}"#
        try Data(future.utf8).write(to: store.sessionFileURL)

        let model = ShellModel()
        model.restoreLastSession(from: store)
        #expect(model.rows.isEmpty)  // fresh in memory

        // Work normally — completions must NOT write the file.
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { Self.answeringFake() })
        model.draft = "2 + 2"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })

        let after = try String(contentsOf: store.sessionFileURL, encoding: .utf8)
        #expect(after == future)
    }
}
