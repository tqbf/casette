import SwiftUI

struct FormulaTokenField: View {
    let title: String
    let prompt: String
    @Binding var text: String
    /// The spoken label; defaults to `title`, but a labelless token (e.g. the
    /// upper field of a compact axis group) can name itself for VoiceOver while
    /// showing no visible label text.
    var accessibilityTitle: String?
    /// The value field's growth ceiling. Defaults to the compact 150pt token;
    /// longer payloads (e.g. a `subs` binding list) widen it.
    var maxWidth: CGFloat

    init(
        title: String,
        prompt: String,
        text: Binding<String>,
        accessibilityTitle: String? = nil,
        maxWidth: CGFloat = 150
    ) {
        self.title = title
        self.prompt = prompt
        self._text = text
        self.accessibilityTitle = accessibilityTitle
        self.maxWidth = maxWidth
    }

    var body: some View {
        HStack(spacing: 5) {
            if !title.isEmpty {
                Text(title)
                    .font(Theme.Fonts.formulaTokenLabel)
                    .foregroundStyle(.secondary)
            }
            TextField(prompt, text: $text)
                .font(Theme.Fonts.formulaTokenValue)
                .textFieldStyle(.plain)
                .frame(minWidth: 34, idealWidth: text.isEmpty ? 44 : 72, maxWidth: maxWidth)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: Theme.formulaTokenCornerRadius, style: .continuous)
                .fill(.quaternary.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.formulaTokenCornerRadius, style: .continuous)
                .stroke(.separator.opacity(0.28), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle ?? title)
    }
}
