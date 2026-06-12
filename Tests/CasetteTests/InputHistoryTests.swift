import Foundation
import Testing
@testable import Casette

/// The Up/Down command-history model: recall order, the customary draft
/// preservation (the in-progress draft is restored when you come back down),
/// boundary behavior, and duplicate collapsing.
@Suite("InputHistory")
struct InputHistoryTests {
    @Test("up recalls newest-first; down walks back to the stashed draft")
    func upDownRoundTrip() {
        var history = InputHistory()
        history.record("2 + 2")
        history.record("factor x^4 - 1")

        #expect(history.recallPrevious(stashing: "in progress") == "factor x^4 - 1")
        #expect(history.recallPrevious(stashing: "ignored") == "2 + 2")
        #expect(history.recallNext() == "factor x^4 - 1")
        // Past the newest entry: the in-progress draft comes back.
        #expect(history.recallNext() == "in progress")
        #expect(!history.isNavigating)
    }

    @Test("up at the oldest entry stays put (returns nil, draft untouched)")
    func upStopsAtOldest() {
        var history = InputHistory()
        history.record("only one")
        #expect(history.recallPrevious(stashing: "draft") == "only one")
        #expect(history.recallPrevious(stashing: "draft") == nil)
        // Still navigating; down restores the original stash.
        #expect(history.recallNext() == "draft")
    }

    @Test("down without navigating is a no-op")
    func downWithoutNavigating() {
        var history = InputHistory()
        history.record("2 + 2")
        #expect(history.recallNext() == nil)
    }

    @Test("up with no history is a no-op")
    func upWithNoHistory() {
        var history = InputHistory()
        #expect(history.recallPrevious(stashing: "draft") == nil)
        #expect(!history.isNavigating)
    }

    @Test("an empty in-progress draft is restored as empty")
    func emptyDraftRestores() {
        var history = InputHistory()
        history.record("2 + 2")
        #expect(history.recallPrevious(stashing: "") == "2 + 2")
        #expect(history.recallNext() == "")
    }

    @Test("recording resets navigation")
    func recordResetsNavigation() {
        var history = InputHistory()
        history.record("a")
        history.record("b")
        _ = history.recallPrevious(stashing: "stash")
        #expect(history.isNavigating)

        history.record("c")
        #expect(!history.isNavigating)
        // Fresh navigation starts at the new newest.
        #expect(history.recallPrevious(stashing: "") == "c")
    }

    @Test("endNavigation resets the cursor and the stash: the next up starts at the newest")
    func endNavigationResets() {
        var history = InputHistory()
        history.record("a")
        history.record("b")
        history.record("c")
        _ = history.recallPrevious(stashing: "old draft")  // "c"
        _ = history.recallPrevious(stashing: "")  // "b" — mid-list
        history.endNavigation()
        #expect(!history.isNavigating)
        // Fresh navigation: newest entry first, stashing the CURRENT draft.
        #expect(history.recallPrevious(stashing: "fresh") == "c")
        #expect(history.recallNext() == "fresh")
    }

    @Test("endNavigation without navigating is a harmless no-op")
    func endNavigationIdle() {
        var history = InputHistory()
        history.record("a")
        history.endNavigation()
        #expect(history.recallPrevious(stashing: "draft") == "a")
        #expect(history.recallNext() == "draft")
    }

    @Test("consecutive duplicates collapse; non-consecutive repeats survive")
    func duplicateCollapsing() {
        var history = InputHistory()
        history.record("2 + 2")
        history.record("2 + 2")
        history.record("x")
        history.record("2 + 2")
        #expect(history.entries == ["2 + 2", "x", "2 + 2"])
    }
}
