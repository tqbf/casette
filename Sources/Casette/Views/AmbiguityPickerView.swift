import SwiftUI

/// The candidate picker for an ambiguous friendly submission — an inline
/// suggestion panel (autocomplete-style: material, rounded, shadowed)
/// floated directly above the input pane, IN THE MAIN WINDOW. The choice
/// evaluates immediately.
///
/// Why not a `.popover`: on macOS a popover is presented as its own KEY
/// window. The moment it appears the main window resigns key, the input
/// editor loses first-responder status, and every key — Esc, Return, the
/// digit picks, even plain typing — goes to the popover window, which has
/// no text field and no working shortcut routing. The keys are dead and the
/// editor is unreachable (PROBLEMS.md). An inline overlay lives in the SAME
/// window, so the editor keeps keyboard focus the whole time.
///
/// Keyboard-first, and the focused `InputEditor` IS the keyboard: Return
/// takes the first (most likely) reading, digits 2–9 take the rest, Esc
/// cancels and keeps the draft — and any edit to the draft dismisses the
/// panel via `ShellModel.draft.didSet` (its candidates would be stale).
/// This view renders candidates and hints only; it deliberately carries NO
/// `keyboardShortcut`s and no focusable controls, so it can never steal
/// focus or double-handle a key. Mouse is the one path it owns: a plain
/// `Button` per candidate.
struct AmbiguityPickerView: View {
    let ambiguity: PendingAmbiguity
    let choose: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("“\(ambiguity.raw)” can mean:")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.ambiguityRowPaddingHorizontal)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(Array(ambiguity.candidates.enumerated()), id: \.element) { index, candidate in
                CandidateRow(candidate: candidate, index: index, choose: choose)
            }
            Text("↩ first   2–9 choose   esc keep editing")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, Theme.ambiguityRowPaddingHorizontal)
                .padding(.top, 2)
                .padding(.bottom, 6)
        }
        .padding(Theme.ambiguityPanelPadding)
        .frame(minWidth: 320, maxWidth: 480, alignment: .leading)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: Theme.ambiguityPanelCornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.ambiguityPanelCornerRadius)
                .strokeBorder(.separator)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Possible readings of \(ambiguity.raw)")
    }
}

/// One candidate row: the generated Sage plus its keycap hint (↩ for the
/// first, the digit for the rest). A plain button — hover-tinted like a
/// suggestion-list row, no shortcut (the focused editor routes the keys).
private struct CandidateRow: View {
    let candidate: String
    let index: Int
    let choose: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: chooseThis) {
            HStack(spacing: 8) {
                Text(candidate)
                    .font(Theme.Fonts.inputPreviewSage)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                Text(index == 0 ? "↩" : "\(index + 1)")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.ambiguityRowPaddingHorizontal)
            .padding(.vertical, Theme.ambiguityRowPaddingVertical)
            .background(
                Theme.rowBackground(isSelected: false, isHovered: isHovered),
                in: RoundedRectangle(cornerRadius: Theme.ambiguityRowCornerRadius)
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Evaluate \(candidate)")
    }

    private func chooseThis() {
        choose(candidate)
    }
}

#Preview {
    AmbiguityPickerView(
        ambiguity: PendingAmbiguity(
            raw: "solve x*y = 1",
            candidates: ["solve(x*y == 1, x)", "solve(x*y == 1, y)"],
            advances: true),
        choose: { _ in })
    .padding(40)
}
