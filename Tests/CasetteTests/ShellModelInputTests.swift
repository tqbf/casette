import Foundation
import Testing
@testable import Casette

/// The V1.4 input-pane semantics on the model: compiler-routed submission
/// (inline error = no row + draft kept; ambiguity = picker, the choice
/// evaluates), ⌘-Return (evaluate without advancing), Up/Down history with
/// draft preservation, the live draft preview, and the prelude wire order.
@MainActor
@Suite("ShellModel input semantics (V1.4)")
struct ShellModelInputTests {
    // MARK: - Submission routing

    @Test("a friendly submission records raw input + generated Sage on the row")
    func friendlySubmission() {
        let model = ShellModel()
        model.draft = "eigenvalues [[1,2],[3,4]]"
        model.submitDraft()
        #expect(model.rows.count == 1)
        #expect(model.rows[0].input == "eigenvalues [[1,2],[3,4]]")
        #expect(model.rows[0].sage == "matrix([[1,2],[3,4]]).eigenvalues()")
        #expect(model.draft.isEmpty)
    }

    @Test("a compile error submits NOTHING and keeps the draft")
    func compileErrorRefusesSubmission() {
        let model = ShellModel()
        model.draft = "integral x^2, x=0.."
        model.submitDraft()
        #expect(model.rows.isEmpty)
        #expect(model.draft == "integral x^2, x=0..")
        #expect(model.pendingAmbiguity == nil)
        guard case let .issue(message, suggestion) = model.draftPreview else {
            Issue.record("expected .issue preview, got \(model.draftPreview)")
            return
        }
        #expect(message.contains("incomplete"))
        #expect(suggestion != nil)
    }

    @Test("an ambiguous submission opens the picker; the choice evaluates and advances")
    func ambiguityRoundTrip() {
        let model = ShellModel()
        model.draft = "solve x*y = 1"
        model.submitDraft()
        #expect(model.rows.isEmpty)  // nothing evaluated yet
        #expect(model.draft == "solve x*y = 1")  // draft intact while choosing
        guard let pending = model.pendingAmbiguity else {
            Issue.record("expected a pending ambiguity")
            return
        }
        #expect(pending.candidates.count == 2)

        model.resolveAmbiguity(choosing: pending.candidates[1])
        #expect(model.pendingAmbiguity == nil)
        #expect(model.rows.count == 1)
        #expect(model.rows[0].input == "solve x*y = 1")
        #expect(model.rows[0].sage == "solve(x*y == 1, y)")
        #expect(model.draft.isEmpty)  // the resolved submission advanced
    }

    @Test("esc: cancelAmbiguity dismisses the picker and keeps the draft as typed")
    func cancelAmbiguityKeepsDraft() {
        let model = ShellModel()
        model.draft = "solve x*y = 1"
        model.submitDraft()
        #expect(model.pendingAmbiguity != nil)
        #expect(model.cancelAmbiguity())
        #expect(model.pendingAmbiguity == nil)
        #expect(model.draft == "solve x*y = 1")  // draft intact
        #expect(model.rows.isEmpty)  // nothing evaluated
        #expect(!model.cancelAmbiguity())  // nothing left to dismiss
    }

    @Test("keyboard pick by index: return = first, digit N = nth, out of range = picker stays")
    func resolveAmbiguityByIndex() {
        let model = ShellModel()
        model.draft = "solve x*y = 1"
        model.submitDraft()
        #expect(model.pendingAmbiguity?.candidates.count == 2)

        // An out-of-range digit (e.g. 7 with two candidates) does nothing.
        #expect(!model.resolveAmbiguity(at: 6))
        #expect(model.pendingAmbiguity != nil)
        #expect(model.rows.isEmpty)

        // Digit 2 = index 1 = the second reading; it evaluates and advances.
        #expect(model.resolveAmbiguity(at: 1))
        #expect(model.pendingAmbiguity == nil)
        #expect(model.rows.count == 1)
        #expect(model.rows[0].sage == "solve(x*y == 1, y)")
        #expect(model.draft.isEmpty)

        // With no picker up, index picks are inert.
        #expect(!model.resolveAmbiguity(at: 0))
    }

    @Test("editing the draft dismisses the picker — its candidates are stale")
    func draftEditDismissesAmbiguity() {
        let model = ShellModel()
        model.draft = "solve x*y = 1"
        model.submitDraft()
        #expect(model.pendingAmbiguity != nil)
        model.draft = ""  // ⌘A + Delete
        #expect(model.pendingAmbiguity == nil)
        #expect(model.rows.isEmpty)
    }

    @Test("history recall dismisses the picker too (the draft text changed)")
    func recallDismissesAmbiguity() {
        let model = ShellModel()
        model.draft = "2 + 2"
        model.submitDraft()
        model.draft = "solve x*y = 1"
        model.submitDraft()
        #expect(model.pendingAmbiguity != nil)
        #expect(model.recallPreviousInput())
        #expect(model.pendingAmbiguity == nil)
        #expect(model.draft == "2 + 2")
    }

    @Test("resolving with a string that isn't a candidate is a no-op")
    func resolveRejectsForeignCandidate() {
        let model = ShellModel()
        model.draft = "solve x*y = 1"
        model.submitDraft()
        model.resolveAmbiguity(choosing: "os.system('rm -rf /')")
        #expect(model.rows.isEmpty)
        #expect(model.pendingAmbiguity != nil)
    }

    // MARK: - ⌘-Return

    @Test("evaluateInPlace submits a row but the draft stays for iteration")
    func evaluateWithoutAdvancing() {
        let model = ShellModel()
        model.draft = "factor x^4 - 1"
        model.evaluateInPlace()
        #expect(model.rows.count == 1)
        #expect(model.rows[0].sage == "factor(x^4 - 1)")
        #expect(model.draft == "factor x^4 - 1")  // NOT cleared

        // Iterating and evaluating again appends a second row.
        model.draft = "factor x^6 - 1"
        model.evaluateInPlace()
        #expect(model.rows.count == 2)
        #expect(model.draft == "factor x^6 - 1")
    }

    @Test("an ambiguity from ⌘-Return keeps the draft after the choice")
    func ambiguityInPlaceKeepsDraft() {
        let model = ShellModel()
        model.draft = "derivative x*y"
        model.evaluateInPlace()
        guard let pending = model.pendingAmbiguity else {
            Issue.record("expected a pending ambiguity")
            return
        }
        model.resolveAmbiguity(choosing: pending.candidates[0])
        #expect(model.rows.count == 1)
        #expect(model.draft == "derivative x*y")  // ⌘↩ semantics survive the picker
    }

    // MARK: - History

    @Test("up/down recalls submitted inputs and restores the in-progress draft")
    func historyNavigation() {
        let model = ShellModel()
        for input in ["2 + 2", "factor x^4 - 1"] {
            model.draft = input
            model.submitDraft()
        }

        model.draft = "half-typed"
        #expect(model.recallPreviousInput())
        #expect(model.draft == "factor x^4 - 1")
        #expect(model.recallPreviousInput())
        #expect(model.draft == "2 + 2")
        #expect(!model.recallPreviousInput())  // at the oldest: key not consumed

        #expect(model.recallNextInput())
        #expect(model.draft == "factor x^4 - 1")
        #expect(model.recallNextInput())
        #expect(model.draft == "half-typed")  // the customary draft preservation
        #expect(!model.recallNextInput())
    }

    @Test("history records refused submissions never; in-place and choices always")
    func historyRecording() {
        let model = ShellModel()
        model.draft = "integral x^2, x=0.."  // compile error → refused
        model.submitDraft()
        model.draft = "factor x^4 - 1"
        model.evaluateInPlace()  // ⌘↩ still records
        model.draft = "solve x*y = 1"
        model.submitDraft()
        guard let pending = model.pendingAmbiguity else {
            Issue.record("expected a pending ambiguity")
            return
        }
        model.resolveAmbiguity(choosing: pending.candidates[0])
        #expect(model.inputHistory.entries == ["factor x^4 - 1", "solve x*y = 1"])
    }

    @Test("a user edit mid-navigation resets the cursor: the next up starts at the newest")
    func userEditResetsHistoryCursor() {
        let model = ShellModel()
        for input in ["1 + 1", "2 + 2", "3 + 3"] {
            model.draft = input
            model.submitDraft()
        }
        #expect(model.recallPreviousInput())  // "3 + 3"
        #expect(model.recallPreviousInput())  // "2 + 2" — mid-list
        #expect(model.draft == "2 + 2")

        model.draft = ""  // the user clears the field (⌘A, Delete)
        #expect(model.recallPreviousInput())
        #expect(model.draft == "3 + 3")  // back at the NEWEST, not "1 + 1"
        #expect(model.recallNextInput())
        #expect(model.draft.isEmpty)  // the cleared field was stashed afresh
    }

    @Test("arrows are NOT history keys in a multiline draft (cursor movement wins)")
    func multilineDraftBlocksHistory() {
        let model = ShellModel()
        model.draft = "2 + 2"
        model.submitDraft()
        model.draft = "line1\nline2"
        #expect(!model.recallPreviousInput())
        #expect(!model.recallNextInput())
        #expect(model.draft == "line1\nline2")
    }

    @Test("a recalled multiline entry doesn't strand the walk: arrows keep navigating")
    func multilineRecallKeepsNavigating() {
        let model = ShellModel()
        for input in ["a = 5\na * 9", "2 + 2"] {
            model.draft = input
            model.submitDraft()
        }
        model.draft = "fresh"
        #expect(model.recallPreviousInput())
        #expect(model.draft == "2 + 2")
        #expect(model.recallPreviousInput())
        #expect(model.draft == "a = 5\na * 9")  // multiline, mid-navigation
        // Down at the multiline entry CONTINUES forward (the stuck case).
        #expect(model.recallNextInput())
        #expect(model.draft == "2 + 2")
        #expect(model.recallNextInput())
        #expect(model.draft == "fresh")
        // And up from the recalled multiline entry keeps walking back too.
        #expect(model.recallPreviousInput())
        #expect(model.recallPreviousInput())
        #expect(model.draft == "a = 5\na * 9")
        #expect(!model.recallPreviousInput())  // at the oldest
    }

    @Test("editing a recalled multiline entry ends navigation; arrows return to the cursor")
    func editingMultilineRecallEndsNavigation() {
        let model = ShellModel()
        model.draft = "a = 5\na * 9"
        model.submitDraft()
        model.draft = ""
        #expect(model.recallPreviousInput())
        #expect(model.draft == "a = 5\na * 9")

        model.draft = "a = 5\na * 90"  // the user edits the recalled entry
        #expect(!model.recallPreviousInput())  // arrows are cursor keys again
        #expect(!model.recallNextInput())
        #expect(model.draft == "a = 5\na * 90")
    }

    // MARK: - Draft preview

    @Test("the live preview tracks the draft: empty, raw, generated, issue, ambiguous")
    func draftPreviewStates() {
        let model = ShellModel()
        #expect(model.draftPreview == .empty)
        model.draft = "2 + 2"
        #expect(model.draftPreview == .rawSage)
        model.draft = "factor x^4 - 1"
        #expect(model.draftPreview == .generated("factor(x^4 - 1)"))
        model.draft = "solve x*y = 1"
        #expect(model.draftPreview == .ambiguous(count: 2))
        model.draft = "expand (x+1"
        guard case .issue = model.draftPreview else {
            Issue.record("expected .issue for unbalanced bracket")
            return
        }
    }

    @Test("multiline drafts preview as raw Sage")
    func multilinePreviewIsRaw() {
        let model = ShellModel()
        model.draft = "factor x^4 - 1\n2 + 2"
        #expect(model.draftPreview == .rawSage)
    }

    // MARK: - Prelude wire order (fake transport)

    @Test("preludes are sent before the generated Sage, in order, and the row completes from the MAIN eval")
    func preludesPrecedeGeneratedSage() async {
        let model = ShellModel()
        let order = CodeRecorder()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            let code = request["code"] as? String ?? "?"
            order.record(code)
            // Distinguishable answers: preludes echo nothing useful.
            return [WireFixtures.okEnvelope(
                id: id, plain: code.hasPrefix("var(") ? "t" : "8/3", kind: "symbolic")]
        }
        var configuration = SessionController.Configuration()
        configuration.pollInterval = .milliseconds(5)
        model.connectKernel(SessionController(configuration: configuration) { fake })

        model.draft = "integral t^2, t=0..2"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })
        // The boot prelude leads (every boot applies it, V1.5 fix round),
        // then the submission's own prelude, then the generated Sage.
        #expect(order.values == [ShellModel.bootPrelude, "var('t')", "integrate(t^2, (t, 0, 2))"])
        // The row's envelope is the MAIN eval's, not a prelude's.
        #expect(model.rows[0].result?.plain == "8/3")
        #expect(model.rows[0].sage == "integrate(t^2, (t, 0, 2))")
    }
}

/// Records eval order across the fake's @Sendable responder.
private final class CodeRecorder: @unchecked Sendable {
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
