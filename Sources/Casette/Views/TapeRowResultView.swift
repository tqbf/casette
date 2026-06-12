import SwiftUI

/// The result portion of a tape row, switched on the row's card kind (the
/// V1.5 vocabulary: scalar exact/approximate, symbolic, matrix, list, plot,
/// text/stdout, error). Math-bearing cards render the envelope's `latex`
/// through `ResultHeroView` (SwiftMath behind the `MathRenderer`
/// abstraction, plain-mono fallback); captured stdout shows above the result
/// for every card, in execution order.
///
/// An incomplete (`.running`) row is presented honestly based on the kernel:
/// with no kernel connected it reads "Not evaluated"; with a kernel it reads
/// "Evaluating…" with a spinner.
struct TapeRowResultView: View {
    let row: SessionRow
    let isKernelConnected: Bool

    var body: some View {
        switch row.cardKind {
        case .pending:
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
            stdoutAndThen { errorBody(tint: .red, fallbackTitle: "Error") }
        case .interrupted:
            stdoutAndThen { errorBody(tint: .orange, fallbackTitle: "Interrupted") }
        case .statement:
            // A statement echoes no value; only captured output shows.
            if let stdout = row.result?.stdout {
                StdoutBlockView(stdout: stdout)
            }
        case .plot:
            stdoutAndThen { PlotPlaceholderView(caption: row.result?.plain ?? "") }
        case .scalarExact, .scalarApproximate, .symbolic, .matrix, .list, .text:
            stdoutAndThen {
                if let result = row.result {
                    ResultHeroView(result: result)
                }
            }
        }
    }

    /// Captured stdout precedes the result body — that's the order it
    /// happened in (prints run before the value echo).
    private func stdoutAndThen(@ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowInnerSpacing) {
            if let stdout = row.result?.stdout {
                StdoutBlockView(stdout: stdout)
            }
            body()
        }
    }

    /// Error and interrupted rows share an anatomy: the type line over the
    /// message, tinted (red = failed, orange = stopped by the user). The
    /// traceback stays behind the expanded card's disclosure.
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
