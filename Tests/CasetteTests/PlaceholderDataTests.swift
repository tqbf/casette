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
        #expect(rows.contains { $0.status == .ok && $0.approx != nil })
        // A statement row (assignment — echoes no value).
        #expect(rows.contains { $0.isStatement })
        // A plot row and an error row.
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
            #expect(!row.actions.isEmpty, "row \(row.input) has no actions")
        }
    }

    @Test("symbols are sorted by name, like the worker symbols op")
    func symbolsSorted() {
        let names = PlaceholderData.symbols.map(\.name)
        #expect(names == names.sorted())
        #expect(!PlaceholderData.symbols.isEmpty)
    }
}
