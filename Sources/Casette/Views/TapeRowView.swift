import SwiftUI

/// One evaluation on the tape: the echoed input + timestamp on top, the
/// result below (value / `≈` secondary line / error / plot placeholder /
/// nothing for a statement). Selection drives the Inspector and Actions
/// tabs; background priority is selected > hovered > clear (§7.2).
struct TapeRowView: View {
    let row: TapeRow
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowInnerSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.input)
                    .font(Theme.Fonts.rowInput)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.inputElementSpacing)
                Text(row.timestamp, style: .time)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.tertiary)
            }
            TapeRowResultView(row: row)
        }
        .padding(.horizontal, Theme.rowPaddingHorizontal)
        .padding(.vertical, Theme.rowPaddingVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                .fill(Theme.rowBackground(isSelected: isSelected, isHovered: isHovered))
        )
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        // Selection is a tap gesture (a Button would fight text selection and
        // hover styling), so surface it to assistive tech explicitly.
        .accessibilityAddTraits(.isButton)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy Input") { Pasteboard.copy(row.input) }
            Button("Copy Generated Sage") { Pasteboard.copy(row.sage) }
            if !row.primary.isEmpty {
                Button("Copy Result") { Pasteboard.copy(row.primary) }
            }
            if let latex = row.latex {
                Button("Copy LaTeX") { Pasteboard.copy(latex) }
            }
        }
    }
}

#Preview {
    VStack(spacing: 2) {
        ForEach(PlaceholderData.rows.prefix(4)) { row in
            TapeRowView(row: row, isSelected: false, onSelect: {})
        }
    }
    .padding()
    .frame(width: 640)
}
