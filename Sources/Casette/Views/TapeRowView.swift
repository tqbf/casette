import SwiftUI

/// One result card on the tape. Collapsed: a disclosure chevron, the echoed
/// input + timestamp, and the rendered result below. Expanded (chevron, the
/// persisted `SessionRow.expanded`): the full Input / Generated Sage / Plain
/// sections and the traceback disclosure. Selection (tap) drives the
/// Inspector and Actions tabs; background priority is selected > hovered >
/// clear (§7.2). Copy lives on the context menu plus a hover-revealed
/// button (§4.5 — opacity fade, never insert-on-hover).
struct TapeRowView: View {
    let row: SessionRow
    let isSelected: Bool
    let isKernelConnected: Bool
    let onSelect: () -> Void
    let onToggleExpanded: () -> Void
    /// Re-evaluates this row's input as a fresh tape row (the plot card's
    /// missing-PNG regenerate affordance — V1.7).
    let onRerun: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowInnerSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Button(
                    row.expanded ? "Collapse details" : "Expand details",
                    systemImage: "chevron.right",
                    action: onToggleExpanded
                )
                .buttonStyle(.plain)
                .labelStyle(.iconOnly)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(row.expanded ? 90 : 0))
                .animation(.easeOut(duration: 0.12), value: row.expanded)
                .help(row.expanded ? "Collapse details" : "Show input, generated Sage, and plain text")
                Text(row.input)
                    .font(Theme.Fonts.rowInput)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.inputElementSpacing)
                Button("Copy Result", systemImage: "doc.on.doc", action: copyPrimary)
                    .buttonStyle(.plain)
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                    .animation(.easeOut(duration: 0.12), value: isHovered)
                    .help("Copy result")
                Text(row.timestamp, style: .time)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.tertiary)
            }
            TapeRowResultView(row: row, isKernelConnected: isKernelConnected, onRerun: onRerun)
            // Structural conditional with NO transition (§1.1) — same
            // precedent as the kernel banner and the ambiguity panel.
            if row.expanded {
                TapeRowExpandedView(row: row)
            }
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
            if let plain = row.result?.plain, !plain.isEmpty {
                Button("Copy Result") { Pasteboard.copy(plain) }
            }
            if let latex = row.result?.latex {
                Button("Copy LaTeX") { Pasteboard.copy(latex) }
            }
            if let traceback = row.result?.error?.traceback, !traceback.isEmpty {
                Button("Copy Traceback") { Pasteboard.copy(traceback) }
            }
        }
    }

    /// The hover button copies the most useful string: the result's plain
    /// text, or (for statements/pending rows) the input itself.
    private func copyPrimary() {
        if let plain = row.result?.plain, !plain.isEmpty {
            Pasteboard.copy(plain)
        } else {
            Pasteboard.copy(row.input)
        }
    }
}

#Preview {
    VStack(spacing: 2) {
        ForEach(PlaceholderData.rows.prefix(4)) { row in
            TapeRowView(
                row: row, isSelected: false, isKernelConnected: false,
                onSelect: {}, onToggleExpanded: {}, onRerun: {}
            )
        }
    }
    .padding()
    .frame(width: 640)
}
