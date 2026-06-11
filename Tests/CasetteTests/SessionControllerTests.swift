import Foundation
import Testing
@testable import Casette

/// Drives the V0.2 state machine, ID routing, and the SIGINT → hard-kill
/// escalation policy through a scripted fake transport — no Sage required.
/// (The real-process paths are covered by SageKernelIntegrationTests.)
@Suite("SessionController (state machine + routing, fake transport)")
struct SessionControllerTests {
    /// Fast polling so escalation tests run in milliseconds.
    private static func config(
        evalTimeout: Duration = .seconds(10),
        interruptGrace: Duration = .seconds(10),
        readyTimeout: Duration = .seconds(2)
    ) -> SessionController.Configuration {
        var configuration = SessionController.Configuration()
        configuration.evalTimeout = evalTimeout
        configuration.interruptGrace = interruptGrace
        configuration.readyTimeout = readyTimeout
        configuration.metadataTimeout = .seconds(2)
        configuration.pollInterval = .milliseconds(5)
        return configuration
    }

    // MARK: - Boot

    @Test("connect reaches idle and targets SIGINT at the banner pid")
    func connectReachesIdle() async {
        let fake = FakeKernelTransport()
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()
        #expect(await controller.state == .idle)
        #expect(await controller.issue == nil)
        #expect(fake.realPID == 4242)  // from the ready banner, not the wrapper
    }

    @Test("a setup failure (no Sage) surfaces an honest issue, no crash")
    func bootFailureWhenFactoryThrows() async {
        let controller = SessionController(configuration: Self.config()) {
            throw KernelSetupError.sageNotFound(searched: ["/opt/homebrew/bin/sage"])
        }
        await controller.connect()
        #expect(await controller.state == .notConnected)
        let issue = await controller.issue
        #expect(issue?.contains("SageMath") == true)
    }

    @Test("a worker that exits before its banner is reported, not hung on")
    func bootFailureWhenWorkerExitsEarly() async {
        let fake = FakeKernelTransport()
        fake.bannerOnSpawn = nil
        fake.eofOnSpawn = true
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()
        #expect(await controller.state == .notConnected)
        #expect(await controller.issue?.contains("before it finished starting") == true)
        #expect(fake.hardKillCount >= 1)
    }

    @Test("a hang at boot is hard-killed before reporting (no leaked wrapper)")
    func bootHangIsKilled() async {
        let fake = FakeKernelTransport()
        fake.bannerOnSpawn = nil  // never becomes ready
        let controller = SessionController(
            configuration: Self.config(readyTimeout: .milliseconds(150))) { fake }
        await controller.connect()
        #expect(await controller.state == .notConnected)
        #expect(await controller.issue?.contains("didn't finish starting") == true)
        #expect(fake.hardKillCount >= 1)  // the V0.9 hang-at-boot lesson
    }

    // MARK: - Evaluation routing + terminal states

    @Test("responses route by request ID; stray wire lines are dropped")
    func evaluateRoutesByID() async {
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            return [
                WireFixtures.okEnvelope(id: "someone-else", plain: "999"),
                WireFixtures.okEnvelope(id: id, plain: "4", approx: nil),
            ]
        }
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()

        let evaluation = await controller.evaluate("2 + 2")
        #expect(evaluation.status == .ok)
        #expect(evaluation.result?.plain == "4")
        #expect(evaluation.duration != nil)
        #expect(await controller.state == .completed)
        #expect(await controller.state.canAcceptWork)
    }

    @Test("a structured worker error lands as .error; the kernel stays usable")
    func evaluateError() async {
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            return [
                WireFixtures.errorEnvelope(
                    id: id, type: "ZeroDivisionError", message: "rational division by zero")
            ]
        }
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()

        let evaluation = await controller.evaluate("1/0")
        #expect(evaluation.status == .error)
        #expect(evaluation.result?.error?.type == "ZeroDivisionError")
        #expect(await controller.state == .error)
        #expect(await controller.state.canAcceptWork)
    }

    @Test("evaluate with no kernel is refused with a readable synthetic error")
    func evaluateRefusedWhenNotConnected() async {
        let controller = SessionController(configuration: Self.config()) { FakeKernelTransport() }
        // No connect() — the kernel was never booted.
        let evaluation = await controller.evaluate("2 + 2")
        #expect(evaluation.status == .error)
        #expect(evaluation.result?.error?.type == "Sage not running")
        #expect(await controller.state == .notConnected)
    }

    // MARK: - Interrupt / timeout / escalation (the V0.2 policy)

    @Test("interrupt: cancel signals, SIGINT honored → .interrupted, worker survives")
    func cancelHonored() async {
        let fake = FakeKernelTransport()
        fake.respondToInterrupt = { fake in
            // cysignals honors the SIGINT: the worker answers `interrupted`.
            if let id = fake.lastSentID {
                fake.enqueue(WireFixtures.interruptedEnvelope(id: id))
            }
        }
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()

        let evalTask = Task { await controller.evaluate("while True: pass") }
        #expect(await eventually { await controller.state == .running })
        await controller.interruptCurrent()

        let evaluation = await evalTask.value
        #expect(evaluation.status == .interrupted)
        #expect(fake.interruptCount == 1)
        #expect(fake.hardKillCount == 0)
        #expect(await controller.state == .interrupted)
        #expect(await controller.state.canAcceptWork)  // worker survived
    }

    @Test("timeout: deadline SIGINTs; honored → row .interrupted, state .timedOut")
    func timeoutHonored() async {
        let fake = FakeKernelTransport()
        fake.respondToInterrupt = { fake in
            if let id = fake.lastSentID {
                fake.enqueue(WireFixtures.interruptedEnvelope(id: id))
            }
        }
        let controller = SessionController(
            configuration: Self.config(evalTimeout: .milliseconds(100))) { fake }
        await controller.connect()

        let evaluation = await controller.evaluate("while True: pass")
        #expect(evaluation.status == .interrupted)
        #expect(fake.interruptCount == 1)
        #expect(await controller.state == .timedOut)
        #expect(await controller.state.canAcceptWork)  // SIGINT resolved it
    }

    @Test("escalation: a swallowed SIGINT is hard-killed after the grace window")
    func timeoutEscalatesToHardKill() async {
        let fake = FakeKernelTransport()
        fake.respondToInterrupt = nil  // SIGINT swallowed (SIG_IGN / tight C loop)
        let controller = SessionController(
            configuration: Self.config(
                evalTimeout: .milliseconds(100),
                interruptGrace: .milliseconds(100))) { fake }
        await controller.connect()

        let evaluation = await controller.evaluate("while True: pass")
        #expect(evaluation.status == .interrupted)
        #expect(evaluation.result?.error?.type == "Interrupted")
        #expect(fake.interruptCount == 1)
        #expect(fake.hardKillCount >= 1)
        // The worker is GONE — the state says so and offers recovery.
        #expect(await controller.state == .crashed)
        #expect(await controller.issue?.contains("force-stopped") == true)

        // Until a restart, further evals are refused readably.
        let refused = await controller.evaluate("1 + 1")
        #expect(refused.status == .error)
        #expect(refused.result?.error?.type == "Sage not running")
    }

    // MARK: - Crash detection

    @Test("a worker death mid-eval is visible: synthetic error + .crashed + issue")
    func crashMidEval() async {
        let fake = FakeKernelTransport()
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()

        let evalTask = Task { await controller.evaluate("factorial(10^8)") }
        #expect(await eventually { fake.sentIDs.count == 1 })
        fake.triggerEOF()  // the worker dies mid-eval

        let evaluation = await evalTask.value
        #expect(evaluation.status == .error)
        #expect(evaluation.result?.error?.type == "Sage crashed")
        #expect(await controller.state == .crashed)
        #expect(await controller.issue != nil)
    }

    @Test("a worker death while IDLE is detected (EOF callback, no eval in flight)")
    func idleCrashDetected() async {
        let fake = FakeKernelTransport()
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()
        #expect(await controller.state == .idle)

        fake.triggerEOF()
        #expect(await eventually { await controller.state == .crashed })
        #expect(await controller.issue?.contains("unexpectedly") == true)
    }

    // MARK: - Restart

    @Test("restart preempts an in-flight eval, swaps generations, and resets state")
    func restartSwapsGenerations() async {
        let firstFake = FakeKernelTransport()
        let secondFake = FakeKernelTransport()
        secondFake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            return [WireFixtures.okEnvelope(id: id, plain: "2")]
        }
        let factoryCalls = LockedBox(0)
        let controller = SessionController(configuration: Self.config()) {
            factoryCalls.value += 1
            return factoryCalls.value == 1 ? firstFake : secondFake
        }
        await controller.connect()

        // An eval the first worker never answers…
        let evalTask = Task { await controller.evaluate("while True: pass") }
        #expect(await eventually { firstFake.sentIDs.count == 1 })

        // …is preempted by an intentional restart.
        await controller.restart()
        let evaluation = await evalTask.value
        #expect(evaluation.status == .interrupted)
        #expect(evaluation.result?.error?.message.contains("restarted") == true)
        #expect(firstFake.hardKillCount >= 1)

        // The fresh generation works (a stale reader can't disturb it).
        #expect(await eventually { await controller.state == .idle })
        let fresh = await controller.evaluate("1 + 1")
        #expect(fresh.status == .ok)
        #expect(fresh.result?.plain == "2")
        #expect(factoryCalls.value == 2)
    }

    // MARK: - Symbols + status stream

    @Test("fetchSymbols maps the V0.6 symbols op into a snapshot")
    func fetchSymbolsMapsSnapshot() async {
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [
                    WireFixtures.symbolsResponse(
                        id: id,
                        entries: [
                            ("A", "matrix", "2×2 over Integer Ring"),
                            ("x", "symbolic variable", "x"),
                        ])
                ]
            }
            return [WireFixtures.okEnvelope(id: id, plain: "4")]
        }
        let controller = SessionController(configuration: Self.config()) { fake }
        await controller.connect()

        let snapshot = await controller.fetchSymbols()
        #expect(snapshot?.entries.map(\.name) == ["A", "x"])
        #expect(snapshot?.entries.first?.summary == "2×2 over Integer Ring")
        #expect(snapshot?.capturedAt != nil)
    }

    @Test("the status stream narrates the boot: restarting → idle")
    func statusStreamNarratesBoot() async {
        let fake = FakeKernelTransport()
        let controller = SessionController(configuration: Self.config()) { fake }
        let collector = Task {
            var states: [KernelState] = []
            for await status in controller.statusUpdates {
                states.append(status.state)
                if status.state == .idle { break }
            }
            return states
        }
        await controller.connect()
        let states = await collector.value
        #expect(states == [.restarting, .idle])
    }
}

/// Tiny lock-guarded box for counting factory calls from a @Sendable closure.
private final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int
    init(_ value: Int) { stored = value }
    var value: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }
}
