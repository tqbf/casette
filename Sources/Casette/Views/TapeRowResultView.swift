import SwiftUI

/// The result portion of a tape row, switched on the row's status. Plain
/// monospaced text for now — V1.5 swaps in rendered math (SwiftMath behind
/// the `MathRenderer` abstraction) and V1.7 real plot artifacts.
///
/// An incomplete (`.running`) row is presented honestly based on the kernel:
/// with no kernel connected (V1.2) it reads "Not evaluated"; once V1.3 wires
/// `SageKernel` in, the same row reads "Evaluating…" with a spinner.
struct TapeRowResultView: View {
    let row: SessionRow
    let isKernelConnected: Bool

    var body: some View {
        switch row.status {
        case .running:
            if isKernelConnected {
                HStack(spacing: Theme.rowInnerSpacing) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Evaluating…")
                        .font(Theme.Fonts.resultSecondary)
                        .foregroundStyle(.secondary)
                }
                // One element for assistive tech — the spinner alone would
                // read as an anonymous "in progress".
                .accessibilityElement(children: .combine)
            } else {
                Label("Not evaluated — Sage isn't connected yet.", systemImage: "bolt.slash")
                    .font(Theme.Fonts.resultSecondary)
                    .foregroundStyle(.secondary)
            }
        case .error:
            errorBody(tint: .red, fallbackTitle: "Error")
        case .interrupted:
            errorBody(tint: .orange, fallbackTitle: "Interrupted")
        case .ok:
            if row.isPlot {
                PlotPlaceholderView(caption: row.result?.plain ?? "")
            } else if !row.isStatement, let result = row.result {
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.plain)
                        .font(Theme.Fonts.resultPrimary)
                        .textSelection(.enabled)
                    if let approx = result.approx {
                        Text("≈ \(approx)")
                            .font(Theme.Fonts.resultSecondary)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    /// Error and interrupted rows share an anatomy: the type line over the
    /// message, tinted (red = failed, orange = stopped by the user).
    private func errorBody(tint: Color, fallbackTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.errorType ?? fallbackTitle)
                .font(Theme.Fonts.errorType)
                .foregroundStyle(tint)
            if let plain = row.result?.plain, !plain.isEmpty {
                Text(plain)
                    .font(Theme.Fonts.resultSecondary)
                    .foregroundStyle(tint)
                    .textSelection(.enabled)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PlaceholderData.rows) { row in
            TapeRowResultView(row: row, isKernelConnected: false)
        }
    }
    .padding()
    .frame(width: 640)
}
