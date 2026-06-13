import Foundation
import Testing
@testable import Casette

/// Where the real Sage lives for integration runs: the V0.9 discovery search
/// plus the canonical worker from the repo (the same file build.sh bundles).
/// The whole suite is skipped, not failed, on a machine without Sage.
enum SageTestEnvironment {
    static let workerPath: String = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CasetteTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appending(path: "v0/01-worker-protocol/worker.py")
        .path

    static let sagePath: String? =
        SageDiscovery().discover(storedPath: SageConfigStore().storedPath()).selected?.path

    static var available: Bool {
        sagePath != nil && FileManager.default.fileExists(atPath: workerPath)
    }

    static let factory: SessionController.TransportFactory = {
        guard let sage = sagePath else { throw KernelSetupError.sageNotFound(searched: []) }
        return SageKernel(sagePath: sage, workerPath: workerPath, stderrLogURL: nil)
    }
}

/// End-to-end against REAL Sage: boot, raw evals, namespace persistence,
/// structured errors, the exact/approx envelope, live symbols, interrupt,
/// restart-to-fresh-namespace, and the timeout/escalation policy. Serialized:
/// one live worker at a time, and every test tears its worker down.
@Suite(
    "SageKernel integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct SageKernelIntegrationTests {
    @Test("the full journey: boot, evals, state, errors, symbols, interrupt, restart", .timeLimit(.minutes(5)))
    func fullJourney() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        await controller.connect()
        #expect(await controller.state == .idle)
        #expect(await controller.issue == nil)

        // Raw Sage evaluates.
        let four = await controller.evaluate("2 + 2")
        #expect(four.status == .ok)
        #expect(four.result?.plain == "4")
        #expect(four.result?.kind == "integer")
        #expect(await controller.state == .completed)

        // The V0.8 exact/approx envelope comes through the mapping.
        let rational = await controller.evaluate("1/3 + 1/5")
        #expect(rational.result?.plain == "8/15")
        #expect(rational.result?.approx == "0.5333333333")
        #expect(rational.result?.exact == true)

        // State persists across evals (the exit criterion: x = 5 → x + 1 → 6).
        let assignment = await controller.evaluate("x = 5")
        #expect(assignment.status == .ok)
        #expect(assignment.result?.kind == "none")  // a statement echoes nothing
        let six = await controller.evaluate("x + 1")
        #expect(six.result?.plain == "6")

        // A structured error: readable, and the worker survives.
        let divide = await controller.evaluate("1/0")
        #expect(divide.status == .error)
        #expect(divide.result?.error?.type == "ZeroDivisionError")
        #expect(await controller.state == .error)
        #expect(await controller.state.canAcceptWork)

        // The live symbol table sees the user's x (and only user symbols).
        let symbols = await controller.fetchSymbols()
        #expect(symbols?.entries.contains { $0.name == "x" && $0.kind == "integer" } == true)

        // Interrupt: SIGINT to the real banner pid; cysignals yields promptly.
        let runaway = Task { await controller.evaluate("while True: pass") }
        #expect(await eventually { await controller.state == .running })
        try? await Task.sleep(for: .milliseconds(300))
        await controller.interruptCurrent()
        let interrupted = await runaway.value
        #expect(interrupted.status == .interrupted)
        #expect(await controller.state == .interrupted)

        // The worker SURVIVED the interrupt and the wire is intact.
        let two = await controller.evaluate("1 + 1")
        #expect(two.result?.plain == "2")

        // Restart intentionally resets the namespace: x is gone.
        await controller.restart()
        #expect(await controller.state == .idle)
        let fresh = await controller.evaluate("x")
        #expect(fresh.status == .error)
        #expect(fresh.result?.error?.type == "NameError")
        let freshSymbols = await controller.fetchSymbols()
        #expect(freshSymbols?.entries.isEmpty == true)

        await controller.shutdown()
        #expect(await controller.state == .notConnected)
    }

    @Test("timeout: the deadline SIGINTs; honored → .timedOut, worker survives", .timeLimit(.minutes(5)))
    func timeoutHonoredByRealSage() async {
        var configuration = SessionController.Configuration()
        configuration.evalTimeout = .seconds(1)
        let controller = SessionController(
            configuration: configuration, transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        let evaluation = await controller.evaluate("while True: pass")
        #expect(evaluation.status == .interrupted)
        #expect(await controller.state == .timedOut)
        #expect(await controller.state.canAcceptWork)

        let after = await controller.evaluate("2 + 2")
        #expect(after.result?.plain == "4")
        await controller.shutdown()
    }

    @Test("Casette preloads are callable built-ins and hidden from symbols", .timeLimit(.minutes(5)))
    func casettePreloadsAreHiddenBuiltIns() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        let normal = await controller.evaluate("normal_cdf(0)")
        #expect(normal.status == .ok)
        #expect(normal.result?.plain == "0.5")

        let binomial = await controller.evaluate("binomial_pmf(3, n=10, p=1/2)")
        #expect(binomial.status == .ok)
        #expect(binomial.result?.plain == "15/128")

        let poisson = await controller.evaluate("poisson_cdf(2, lambda_=3)")
        #expect(poisson.status == .ok)
        #expect(poisson.result?.approx == "0.4231900811")

        let untouchedSymbols = await controller.fetchSymbols()
        #expect(untouchedSymbols?.entries.contains { $0.name == "normal_cdf" } == false)
        #expect(untouchedSymbols?.entries.contains { $0.name == "binomial_pmf" } == false)

        _ = await controller.evaluate("normal_cdf = 42")
        let reassignedSymbols = await controller.fetchSymbols()
        #expect(reassignedSymbols?.entries.contains { $0.name == "normal_cdf" && $0.kind == "integer" } == true)

        await controller.restart()
        let afterRestart = await controller.evaluate("normal_cdf(0)")
        #expect(afterRestart.status == .ok)
        #expect(afterRestart.result?.plain == "0.5")
        let freshSymbols = await controller.fetchSymbols()
        #expect(freshSymbols?.entries.contains { $0.name == "normal_cdf" } == false)

        await controller.shutdown()
    }

    @Test("escalation: a SIGINT-ignoring runaway is hard-killed; restart recovers", .timeLimit(.minutes(5)))
    func escalationHardKillsRealRunaway() async {
        var configuration = SessionController.Configuration()
        configuration.evalTimeout = .seconds(1)
        configuration.interruptGrace = .seconds(2)
        let controller = SessionController(
            configuration: configuration, transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        // Clobber cysignals with SIG_IGN — the V0.2 hostile case. SIGINT will
        // be swallowed; the controller must escalate to a group kill.
        let runaway = await controller.evaluate(
            "import signal\nsignal.signal(signal.SIGINT, signal.SIG_IGN)\nwhile True: pass")
        #expect(runaway.status == .interrupted)
        #expect(await controller.state == .crashed)
        #expect(await controller.issue?.contains("force-stopped") == true)

        // Restart recovers with a fresh worker.
        await controller.restart()
        #expect(await controller.state == .idle)
        let after = await controller.evaluate("2 + 2")
        #expect(after.result?.plain == "4")
        await controller.shutdown()
    }
}
