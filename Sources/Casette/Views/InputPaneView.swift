import SwiftUI

/// The bottom input pane — the calculator line. An expanding editor
/// (single-line by default, multiline via Shift-Return) over the live
/// generated-Sage preview, with keycap hints and the kernel status indicator
/// at the trailing edge.
///
/// Ambiguous submissions present their candidates in an INLINE overlay
/// floated directly above the pane — same window, so the editor keeps
/// keyboard focus and its key handlers (Return/digits) drive the picker;
/// Esc is the one key the editor can never see (the text view consumes it
/// as `cancelOperation:`), so it's caught by an AppKit local event monitor
/// (`EscapeInterceptor`, mounted in this view's background) instead.
/// Never a `.popover`: on macOS that becomes its own key window, the editor
/// resigns first responder, and every advertised key goes dead (PROBLEMS.md).
struct InputPaneView: View {
    // Plain reference, not @Bindable — the popover's `$model.pendingAmbiguity`
    // binding is gone; this view only reads the model and calls its methods.
    let model: ShellModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.inputPreviewSpacing) {
            HStack(alignment: .top, spacing: Theme.inputElementSpacing) {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, Theme.inputAccessoryTopPadding)
                    .accessibilityHidden(true)
                InputEditor(model: model, isFocused: isFocused)
                    .frame(maxWidth: .infinity)
                // Always mounted, opacity-faded (never insert/remove — §1.1).
                Text("⏎ evaluate   ⇧⏎ newline")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.tertiary)
                    .opacity(model.draft.isEmpty ? 0 : 1)
                    .animation(.easeOut(duration: 0.15), value: model.draft.isEmpty)
                    .padding(.top, Theme.inputAccessoryTopPadding)
                    .accessibilityHidden(true)
                // The V1.8 exact/numeric controls: session-scoped, so they
                // live with the input (next to the kernel status), not in
                // Settings.
                ExactnessControls(model: model)
                    .padding(.top, Theme.inputControlTopPadding)
                KernelStatusView(state: model.kernelState, issue: model.kernelIssue)
                    .padding(.top, Theme.inputAccessoryTopPadding)
            }
            if let formula = model.formulaIR {
                FormulaBarView(model: model, formula: formula)
                    .padding(.leading, Theme.inputFormulaLeadingInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            DraftPreviewLine(preview: model.draftPreview)
                .padding(.leading, Theme.inputFormulaLeadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.inputPaddingHorizontal)
        .padding(.vertical, Theme.inputPaddingVertical)
        .background(.bar)
        // Esc-dismisses-the-panel. An AppKit local NSEvent monitor is the
        // ONLY hook that fires: the focused text view consumes Esc as the
        // `cancelOperation:` action before `.onKeyPress(.escape)` OR
        // `.onExitCommand` on/above the editor can see it (PROBLEMS.md).
        // `cancelAmbiguity()` returns false with no panel pending, so a
        // plain Esc passes through and keeps its system behavior.
        .background(EscapeInterceptor { model.cancelAmbiguity() })
        // The ambiguity panel: anchored to the pane's top-leading corner and
        // shifted fully above it (its bottom sits `ambiguityPanelGap` over
        // the pane's top edge), floating over the tape like an autocomplete
        // panel. Plain structural conditional, no transition, so it appears
        // and vanishes instantly (Esc must FEEL immediate; §1.1 is about
        // animated insert/remove). It contains no focusable controls — the
        // still-focused editor is its keyboard.
        .overlay(alignment: .topLeading) {
            if let ambiguity = model.pendingAmbiguity {
                AmbiguityPickerView(ambiguity: ambiguity) { candidate in
                    model.resolveAmbiguity(choosing: candidate)
                }
                .padding(.horizontal, Theme.inputPaddingHorizontal)
                .alignmentGuide(.top) { panel in
                    panel[.bottom] + Theme.ambiguityPanelGap
                }
            }
        }
        .onChange(of: model.pendingAmbiguity == nil) { _, _ in
            // The editor must hold keyboard focus on BOTH edges: while the
            // panel is up it is the panel's keyboard (Return/digits/Esc),
            // and once the panel closes (chosen, cancelled, or dismissed by
            // an edit) the flow must never strand the user unfocused.
            isFocused.wrappedValue = true
        }
    }
}
