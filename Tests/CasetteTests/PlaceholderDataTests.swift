import Foundation
import Testing
@testable import Casette

@Suite("PlaceholderData")
struct PlaceholderDataTests {
    @Test("tape covers the result shapes the shell must lay out")
    func rowsCoverShapes() {
        let rows = PlaceholderData.rows
        #expect(!rows.isEmpty)
        // A value row with an ≈ secondary line (the V0.8 display policy).
        #expect(rows.contains { $0.status == .ok && $0.result?.approx != nil })
        // A statement row (`del`, print-only code, or other no-value result).
        #expect(rows.contains { $0.isStatement })
        // A plot row and an error row (with structured error detail).
        #expect(rows.contains { $0.isPlot })
        #expect(rows.contains { $0.status == .error && $0.errorType != nil })
    }

    @Test("rows are in chronological tape order")
    func rowsChronological() {
        let stamps = PlaceholderData.rows.map(\.timestamp)
        #expect(stamps == stamps.sorted())
    }

    @Test("value rows carry per-kind actions for the Actions tab")
    func valueRowsCarryActions() {
        for row in PlaceholderData.rows where row.status == .ok && !row.isStatement {
            #expect(row.result?.actions.isEmpty == false, "row \(row.input) has no actions")
        }
    }

    @Test("the plot row's artifacts are honest path refs marked missing")
    func plotArtifactsAreMissingPathRefs() {
        let plot = PlaceholderData.rows.first { $0.isPlot }
        let artifacts = plot?.result?.artifacts ?? []
        #expect(!artifacts.isEmpty)
        // Placeholder /tmp paths don't exist — the EXPECTED restored state
        // (PROBLEMS.md V0.10): the row still renders from its plain text.
        #expect(artifacts.allSatisfy { $0.status == .missing })
        #expect(plot?.result?.plain.isEmpty == false)
    }

    @Test("completed rows are stamped like the V0.10 recorder (cached at eval time)")
    func provenanceIsCached() {
        for row in PlaceholderData.rows {
            #expect(row.provenance.kind == .cached)
            #expect(row.provenance.cachedAt == row.timestamp)
        }
    }

    @Test("symbol entries are sorted by name, like the worker symbols op")
    func symbolsSorted() {
        let names = PlaceholderData.symbols.entries.map(\.name)
        #expect(names == names.sorted())
        #expect(!PlaceholderData.symbols.entries.isEmpty)
    }

    @Test("symbol visibility can hide untouched boot variables")
    func symbolVisibilityHidesUntouchedBootVariables() {
        let snapshot = SymbolSnapshot(entries: [
            SymbolEntry(name: "n", kind: "integer", summary: "104729"),
            SymbolEntry(name: "x", kind: "symbolic", summary: "x"),
            SymbolEntry(name: "x1", kind: "symbolic variable", summary: "x1"),
            SymbolEntry(name: "y", kind: "integer", summary: "5"),
        ], capturedAt: nil)

        #expect(
            snapshot.visibleEntries(showingBuiltinSymbols: false).map(\.name)
                == ["n", "y"]
        )
        #expect(
            snapshot.visibleEntries(showingBuiltinSymbols: true).map(\.name)
                == ["n", "x", "x1", "y"]
        )
    }
}
