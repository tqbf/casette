import Foundation
import Testing
@testable import Casette

/// V1.9 against REAL Sage, through the app's seams: record a session
/// (state-dependent pair + a plot + a numeric row) with incremental saves,
/// "relaunch" into a fresh model with NO kernel (restore renders from the
/// file alone), then connect a fresh worker and Replay Session — the
/// state-dependent row works because order is preserved, provenance flips,
/// the numeric row replays numeric, and deterministic rows show no spurious
/// supersession (artifact paths are never compared). Skipped without Sage.
@MainActor
@Suite(
    "Session persistence integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct PersistenceIntegrationTests {
    @Test("record → restore (no Sage) → replay: the full V1.9 journey", .timeLimit(.minutes(5)))
    func recordRestoreReplayJourney() async throws {
        let store = makeScratchStore()
        defer { removeScratch(store) }

        // ── Phase 1: record a session through the normal submit path.
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.restoreLastSession(from: store)  // fresh; attaches the store
        model.connectKernel(controller)

        for input in [
            "A = matrix([[2, 0], [0, 3]])",  // state…
            "A.eigenvalues()",            // …dependent
            "plot(sin(x), (x, -pi, pi))",  // artifacts on disk
        ] {
            model.draft = input
            model.submitDraft()
        }
        model.numericMode = true
        model.draft = "1/3"
        model.submitDraft()
        model.numericMode = false

        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.count == 4 && model.rows.allSatisfy { $0.status == .ok }
        })
        #expect(model.rows[1].result?.plain == "[3, 2]")
        #expect(model.rows[3].numeric == true)
        #expect(model.rows[3].result?.exactValue == "1/3")
        let recordedIDs = model.rows.map(\.id)
        let plotPaths = model.rows[2].result?.artifacts.compactMap(\.path) ?? []
        #expect(!plotPaths.isEmpty)

        // The worker dies WITHOUT a clean shutdown op (the app's quit path is
        // a hard kill), so this is the honest relaunch/crash shape. The plot
        // files happen to survive a hard kill — delete them to model the
        // real /tmp-reaped relaunch (PROBLEMS.md: missing is the NORMAL case).
        await controller.shutdown()
        for path in plotPaths {
            try? FileManager.default.removeItem(atPath: path)
        }

        // ── Phase 2: restore with Sage genuinely not involved.
        let relaunched = ShellModel()
        relaunched.restoreLastSession(from: store)
        #expect(relaunched.rows.map(\.id) == recordedIDs)
        #expect(relaunched.rows[1].result?.plain == "[3, 2]")
        #expect(relaunched.rows[2].result?.artifacts.allSatisfy { $0.status == .missing } == true)
        #expect(relaunched.rows[2].result?.kind == "plot")  // row restored anyway
        #expect(relaunched.rows.allSatisfy {
            relaunched.provenanceMark(for: $0) == .cached
        })

        // ── Phase 3: replay into a fresh worker, in tape order.
        let replayController = SessionController(transportFactory: SageTestEnvironment.factory)
        relaunched.connectKernel(replayController)
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            relaunched.kernelState.isConnected && relaunched.canReplaySession
        })
        relaunched.replaySession()
        #expect(await eventually(timeout: .seconds(240)) { @MainActor in
            !relaunched.isReplaying
                && relaunched.rows.allSatisfy { $0.provenance.kind == .replayed }
        })

        // The state-dependent row worked because A was re-assigned first.
        #expect(relaunched.rows[1].status == .ok)
        #expect(relaunched.rows[1].result?.plain == "[3, 2]")
        #expect(relaunched.rows.allSatisfy {
            relaunched.provenanceMark(for: $0) == .replayed
        })
        // Deterministic rows: NO spurious supersession — including the plot,
        // whose fresh artifacts live at NEW paths (paths are never compared).
        #expect(relaunched.rows.allSatisfy { $0.supersededCache == nil })
        let freshArtifacts = relaunched.rows[2].result?.artifacts ?? []
        #expect(freshArtifacts.contains { $0.status == .present })
        #expect(Set(freshArtifacts.compactMap(\.path)).isDisjoint(with: plotPaths))
        // The numeric row replayed with its recorded request shape.
        #expect(relaunched.rows[3].result?.primaryIsApprox == true)
        #expect(relaunched.rows[3].result?.exactValue == "1/3")

        await replayController.shutdown()
    }
}
