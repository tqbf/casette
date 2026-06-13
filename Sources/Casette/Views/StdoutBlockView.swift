import SwiftUI

/// Captured user output (`print(...)`, raw fd writes) from the envelope's
/// `stdout` field — rendered as a labeled monospaced block above the result,
/// in execution order. The label keeps it honestly distinct from the echoed
/// value.
struct StdoutBlockView: View {
    struct Preview: Equatable, Sendable {
        var text: String
        var note: String?
    }

    nonisolated static let displayCharacterLimit = 16_384

    let stdout: String

    var body: some View {
        let preview = Self.preview(for: stdout)
        VStack(alignment: .leading, spacing: Theme.cardSectionLabelSpacing) {
            Text("stdout")
                .font(Theme.Fonts.cardSectionLabel)
                .foregroundStyle(.tertiary)
            Text(preview.text)
                .font(Theme.Fonts.cardMono)
                .textSelection(.enabled)
            if let note = preview.note {
                Text(note)
                    .font(Theme.Fonts.truncationNote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    nonisolated static func preview(for stdout: String) -> Preview {
        let text = stdout.trimmingCharacters(in: .newlines)
        guard text.count > displayCharacterLimit else {
            return Preview(text: text, note: nil)
        }
        let omitted = text.count - displayCharacterLimit
        return Preview(
            text: String(text.prefix(displayCharacterLimit)),
            note: "Showing \(displayCharacterLimit.formatted()) of \(text.count.formatted()) characters; \(omitted.formatted()) omitted.")
    }
}

#Preview {
    StdoutBlockView(stdout: "hello\nworld\n")
        .padding()
}
