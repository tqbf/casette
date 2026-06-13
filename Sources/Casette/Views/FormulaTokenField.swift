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
    /// Tracks the typed content's natural width instead of the fixed compact
    /// ideal. The lane lays tokens out with `.fixedSize(horizontal:)`, which
    /// sizes each field to its IDEAL width — so a long payload in a compact
    /// token clips silently (the implicit-plot `= 1` lesson). Fields that
    /// carry whole equations or binding lists opt in to grow with content,
    /// still capped by `maxWidth`.
    var growsWithContent: Bool

    init(
        title: String,
        prompt: String,
        text: Binding<String>,
        accessibilityTitle: String? = nil,
        maxWidth: CGFloat = 150,
        growsWithContent: Bool = false
    ) {
        self.title = title
        self.prompt = prompt
        self._text = text
        self.accessibilityTitle = accessibilityTitle
        self.maxWidth = maxWidth
        self.growsWithContent = growsWithContent
    }

    /// nil lets the TextField's natural (content-fitting) ideal width through
    /// to the `.fixedSize` layout; the compact tokens keep their fixed ideal.
    private var idealWidth: CGFloat? {
        if growsWithContent, !text.isEmpty { return nil }
        return text.isEmpty ? 44 : 72
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
                .frame(minWidth: 34, idealWidth: idealWidth, maxWidth: maxWidth)
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
