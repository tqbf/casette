import SwiftUI

/// The unobtrusive compile-preview line under the input field — the
/// friendly compiler's live answer for the current draft, so friendly → Sage
/// is always inspectable BEFORE submitting. Always mounted at a stable
/// minimum height (content swaps in place; the pane never jumps as you type).
struct DraftPreviewLine: View {
    let preview: DraftPreview

    var body: some View {
        line
            .frame(minHeight: Theme.inputPreviewMinHeight, alignment: .leading)
    }

    @ViewBuilder private var line: some View {
        switch preview {
        case .empty:
            // Reserved space only — nothing to say about an empty draft.
            Color.clear
                .frame(height: Theme.inputPreviewMinHeight)
                .accessibilityHidden(true)
        case .rawSage:
            Text("raw Sage")
                .font(Theme.Fonts.inputPreviewIssue)
                .foregroundStyle(.tertiary)
        case let .generated(sage):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(sage)
                    .font(Theme.Fonts.inputPreviewSage)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Generated Sage: \(sage)")
        case let .issue(message, suggestion):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                issueText(message: message, suggestion: suggestion)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .combine)
        case let .ambiguous(count):
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("\(count) possible readings — return offers the choices")
                    .font(Theme.Fonts.inputPreviewIssue)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// Message in prose voice; the `Try: …` suggestion in mono (it's example
    /// input). One wrapping run of text, so long errors stay compact.
    private func issueText(message: String, suggestion: String?) -> Text {
        let messageText = Text(message)
            .font(Theme.Fonts.inputPreviewIssue)
            .foregroundStyle(.secondary)
        guard let suggestion else { return messageText }
        return messageText + Text(verbatim: "  ")
            + Text(suggestion)
                .font(Theme.Fonts.inputPreviewSuggestion)
                .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        DraftPreviewLine(preview: .empty)
        DraftPreviewLine(preview: .rawSage)
        DraftPreviewLine(preview: .generated("factor(x^4 - 1)"))
        DraftPreviewLine(preview: .issue(
            message: "Range `x=0..` is incomplete — missing the upper bound after `..`.",
            suggestion: "Complete it, e.g. `x=0..1`."))
        DraftPreviewLine(preview: .ambiguous(count: 2))
    }
    .padding()
    .frame(width: 520)
}
