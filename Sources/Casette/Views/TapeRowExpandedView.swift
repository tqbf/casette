import SwiftUI

/// The expanded half of a result card (INITIAL.md V1.5 pattern): the full
/// Input / Generated Sage / Plain sections under the rendered result, plus
/// the traceback disclosure for error rows. The collapsed content stays
/// visible above — expanding ADDS detail, it never takes the rendered
/// result away (progressive disclosure).
struct TapeRowExpandedView: View {
    let row: SessionRow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardSectionSpacing) {
            CardSectionView(label: "Input", value: row.input)
            CardSectionView(label: "Generated Sage", value: row.sage)
            if let plain = row.result?.plain, !plain.isEmpty {
                CardSectionView(label: "Plain", value: plain)
            }
            if let traceback = row.result?.error?.traceback, !traceback.isEmpty {
                TracebackDisclosureView(traceback: traceback)
            }
        }
        .padding(.leading, Theme.cardExpandedInset)
        .padding(.top, Theme.rowInnerSpacing)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        TapeRowExpandedView(row: PlaceholderData.rows[4])
        TapeRowExpandedView(row: PlaceholderData.rows[PlaceholderData.rows.count - 1])
    }
    .padding()
    .frame(width: 560)
}
