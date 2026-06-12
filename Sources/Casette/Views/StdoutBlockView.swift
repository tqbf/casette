import SwiftUI

/// Captured user output (`print(...)`, raw fd writes) from the envelope's
/// `stdout` field — rendered as a labeled monospaced block above the result,
/// in execution order. The label keeps it honestly distinct from the echoed
/// value.
struct StdoutBlockView: View {
    let stdout: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardSectionLabelSpacing) {
            Text("stdout")
                .font(Theme.Fonts.cardSectionLabel)
                .foregroundStyle(.tertiary)
            Text(stdout.trimmingCharacters(in: .newlines))
                .font(Theme.Fonts.cardMono)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    StdoutBlockView(stdout: "hello\nworld\n")
        .padding()
}
