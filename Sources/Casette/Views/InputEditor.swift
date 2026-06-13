import AppKit
import FriendlyCompiler
import SwiftUI

/// The expanding input field: single-line by default, growing with its
/// content (newlines or wrap) up to a ceiling, then scrolling.
///
/// Built on `TextEditor` rather than a vertical-axis `TextField` because the
/// keyboard contract demands it: Shift-Return must insert a newline AT THE
/// CURSOR (the field editor would end editing instead), plain Return must
/// evaluate, and ⌘-Return must evaluate without advancing. An invisible
/// `Text` mirror gives the editor the intrinsic height `TextEditor` lacks.
///
/// Key handling (the V1.4/V1.12 contract):
/// - Return → evaluate (submit the draft).
/// - Shift-Return → newline (ignored here so the text view inserts it).
/// - ⌘-Return → evaluate without advancing (also on the Sage menu, which
///   claims the key equivalent first when present; this is the fallback).
/// - Up/Down → history in single-line mode; cursor movement in multiline
///   (except mid-navigation, where the arrows keep walking history).
///
/// While the ambiguity panel is up, the editor — which keeps keyboard focus;
/// the panel is an inline same-window overlay with no focusable controls —
/// is also the panel's keyboard: Return takes the first reading, digits 2–9
/// the rest. Esc (dismiss, keep the draft) is the one advertised key NOT
/// handled here: the backing `NSTextView` consumes it as `cancelOperation:`
/// before `.onKeyPress(.escape)` can see it AND without forwarding it up
/// the responder chain, so `.onExitCommand` never fires either. It is
/// intercepted by an AppKit local event monitor (`EscapeInterceptor`,
/// mounted by `InputPaneView`) instead. These must match the keycap hints
/// `AmbiguityPickerView` advertises. (This routing is exactly why the
/// panel must never be a `.popover` — a popover becomes its own key window
/// and these handlers stop firing. PROBLEMS.md.)
struct InputEditor: View {
    @Bindable var model: ShellModel
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The sizing mirror: same font and insets as the editor's text,
            // so the ZStack (and therefore the editor) is exactly as tall as
            // the content. A trailing newline gets a stand-in space — Text
            // doesn't count it, but the editor shows a cursor line there.
            Text(mirrorText)
                .font(Theme.Fonts.input)
                .padding(.vertical, Theme.inputEditorInsetVertical)
                .padding(.horizontal, Theme.inputEditorInsetHorizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(0)
                .accessibilityHidden(true)
            if model.draft.isEmpty {
                Text("Type math — try  factor x^4 - 1")
                    .font(Theme.Fonts.input)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, Theme.inputEditorInsetVertical)
                    .padding(.horizontal, Theme.inputEditorInsetHorizontal)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $model.draft)
                .font(Theme.Fonts.input)
                .scrollContentBackground(.hidden)
                // The editor's own line-fragment padding supplies the
                // horizontal inset; only the vertical needs matching.
                .padding(.vertical, Theme.inputEditorInsetVertical)
                .focused(isFocused)
                .onKeyPress(keys: [.return], phases: [.down], action: handleReturn)
                // No Esc handler here, deliberately: neither
                // `.onKeyPress(.escape)` nor `.onExitCommand` ever fires on
                // a focused TextEditor (verified on screen, fix rounds 1–3)
                // — the NSTextView eats Esc as `cancelOperation:`. The
                // working Esc route is `EscapeInterceptor` in InputPaneView.
                .onKeyPress(characters: Self.pickerDigits, phases: [.down], action: handlePickerDigit)
                // Tab → enter the formula lane (Numbers-style), but ONLY when a
                // lane is actually showing and no picker is up. The lane's
                // tokens are NSTextFields in this same window's key-view loop,
                // laid out after the editor, so advancing to the next key view
                // lands on the first token; native Tab/Shift-Tab then walks the
                // tokens. This is the same conservative routing as the handlers
                // above: no new event monitor, and we return `.ignored` whenever
                // there's no lane, so Tab keeps its default text behavior (and
                // the picker's Return/digit/Esc routing is untouched).
                .onKeyPress(.tab, phases: [.down], action: handleTab)
                .onKeyPress(.upArrow) { historyStep(model.recallPreviousInput) }
                .onKeyPress(.downArrow) { historyStep(model.recallNextInput) }
                .accessibilityLabel("Expression")
        }
        .frame(maxHeight: Theme.inputMaxHeight)
    }

    private var mirrorText: String {
        if model.draft.isEmpty { return " " }
        return model.draft.hasSuffix("\n") ? model.draft + " " : model.draft
    }

    private func handleReturn(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.shift) {
            return .ignored  // the text view inserts the newline at the cursor
        }
        if model.pendingAmbiguity != nil {
            // The picker is up: Return takes the first (most likely)
            // reading, as its ↩ keycap hint advertises.
            model.resolveAmbiguity(at: 0)
            return .handled
        }
        if press.modifiers.contains(.command) {
            model.evaluateInPlace()
            return .handled
        }
        model.submitDraft()
        return .handled
    }

    /// While the picker is up, digits 2–9 are picker keys: each takes the
    /// matching candidate; an out-of-range digit is swallowed (it must not
    /// silently type into the draft). Otherwise digits type as usual.
    private func handlePickerDigit(_ press: KeyPress) -> KeyPress.Result {
        guard model.pendingAmbiguity != nil else { return .ignored }
        if let digit = press.characters.first?.wholeNumberValue {
            model.resolveAmbiguity(at: digit - 1)
        }
        return .handled
    }

    /// Tab moves keyboard focus into the formula lane when one is showing.
    /// When `shouldEnterLane` is false (no lane, or a picker pending) Tab is
    /// `.ignored` so the text view's default tab behavior is preserved.
    private func handleTab(_ press: KeyPress) -> KeyPress.Result {
        guard Self.shouldEnterLane(formulaIR: model.formulaIR, pendingAmbiguity: model.pendingAmbiguity)
        else { return .ignored }
        // Shift-Tab keeps walking the loop backwards natively once focus is in
        // the lane; from the editor a plain Tab is the only entry gesture.
        if press.modifiers.contains(.shift) { return .ignored }
        NSApp.keyWindow?.selectNextKeyView(nil)
        return .handled
    }

    /// The model-level guard for "Tab should enter the lane": a lane is showing
    /// and no ambiguity picker is pending. Pure so it is unit-testable.
    static func shouldEnterLane(formulaIR: FormulaIR?, pendingAmbiguity: PendingAmbiguity?) -> Bool {
        formulaIR != nil && pendingAmbiguity == nil
    }

    private func historyStep(_ step: () -> Bool) -> KeyPress.Result {
        step() ? .handled : .ignored
    }

    private static let pickerDigits = CharacterSet(charactersIn: "23456789")
}
