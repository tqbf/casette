import SwiftUI

/// The result portion of a tape row, switched on the row's status/kind.
/// Plain monospaced text for now — V1.5 swaps in rendered math (SwiftMath
/// behind the `MathRenderer` abstraction) and V1.7 real plot artifacts.
struct TapeRowResultView: View {
    let row: TapeRow

    var body: some View {
        switch row.status {
        case .notEvaluated:
            Label(row.primary, systemImage: "bolt.slash")
                .font(Theme.Fonts.resultSecondary)
                .foregroundStyle(.secondary)
        case .error:
            VStack(alignment: .leading, spacing: 2) {
                Text(row.errorType ?? "Error")
                    .font(Theme.Fonts.errorType)
                    .foregroundStyle(.red)
                Text(row.primary)
                    .font(Theme.Fonts.resultSecondary)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        case .ok:
            if row.isPlot {
                PlotPlaceholderView(caption: row.primary)
            } else if !row.isStatement {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.primary)
                        .font(Theme.Fonts.resultPrimary)
                        .textSelection(.enabled)
                    if let approx = row.approx {
                        Text("≈ \(approx)")
                            .font(Theme.Fonts.resultSecondary)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PlaceholderData.rows) { row in
            TapeRowResultView(row: row)
        }
    }
    .padding()
    .frame(width: 640)
}
