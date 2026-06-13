# Completion UI

Casette's completion UI is an editing aid over friendly input. It does not
compile directly to Sage and it does not own a second source buffer.

## Source Of Truth

`ShellModel.draft` is the single source of truth for the input pane. Completion
views parse that draft into a small typed shape, let the user edit the shape,
then render it back to friendly input.

The dispatch seam is `FormulaIR` in `FriendlyCompiler`: one case per formula
family, each wrapping that family's typed IR. The flow for every family:

- `ShellModel.formulaIR` parses `draft` using `FormulaIR.parse` (which tries
  each family's IR; families are keyed by disjoint leading commands).
- The family's bar view (dispatched by `FormulaBarView`) edits the typed IR.
- `ShellModel.updateFormula(_:)` replaces `draft` with the IR's
  `friendlyInput`.

The integral prototype is the reference implementation of the pattern
(`IntegralFormulaIR` / `IntegralFormulaBar`).

Because the draft remains the source of truth, all existing input behavior
continues to work: live preview, Return submission, history, ambiguity, compile
errors, and persistence.

## UI Shape

When the draft begins with the friendly command `integral` or `integrate`, the
input pane shows a Numbers-style hint lane below the main input row.

The lane contains:

- a pinned function chip: `INTEGRAL`
- an editable expression token
- an editable variable token
- optional lower-bound and upper-bound tokens

The hint lane is full-width and aligned with the editor text after the prompt
chevron. It is deliberately not constrained by the numeric controls or Sage
status on the right side of the main input row. At the normal window size the
whole function shape should be visible at once:

```text
INTEGRAL  expr  var  ,  lower  ..  upper
```

The function chip is a hint and anchor, not the compiler. The editable tokens
are small SwiftUI `TextField`s styled like compact macOS tokens.

## Friendly IR

The UI emits friendly input, not Sage. For a definite integral with a tape
reference, the rendered draft looks like this:

```text
integral #14 + x^2, x=0..1
```

That string is the app/compiler boundary IR. It is intentionally human-readable
and still valid as typed friendly input.

For an explicit indefinite integral, the UI can render:

```text
integral x*y, wrt y
```

The friendly compiler accepts this and compiles it to:

```text
integrate(x*y, y)
```

## Tape References

Completion UI must preserve `#ROW` references as text. It must not expand them
or rewrite them to Sage.

The normal app compile boundary handles references:

1. `CompiledInput.compile(_:tapeReferences:)` normalizes the raw draft.
2. `TapeReferenceTable.expandReferences(in:)` rewrites valid `#ROW` references
   to `__casette_tape_refs[ROW]`.
3. `FriendlyCompiler.compile(_:)` receives the expanded friendly input.

So:

```text
integral #14 + x^2, x=0..1
```

becomes:

```text
integrate(__casette_tape_refs[14] + x^2, (x, 0, 1))
```

The row still records the user-facing raw input with `#14`.

## Partial Edits Must Round-Trip

The bars' token bindings re-read the IR from a fresh re-parse of the draft on
every access. So every INTERMEDIATE editing state must be a parse/render fixed
point, or a half-typed field silently vanishes when focus moves (the original
integral bar lost a typed lower bound this way: `x=0..` failed the strict
range parse and re-read as empty).

Rule: IR parsing is TOLERANT — use `FriendlyCompiler.parsePartialRange` (not
the strict `parseRange`) and keep half-typed clauses' text. The compiler
lowerings stay strict; an incomplete range remains an honest compile error in
the preview line. `PartialEditInvarianceTests` simulates each bar's per-field
edit sequence and asserts nothing typed is ever lost — add a case there for
every new family.

## Keyboard

Tab in the main editor enters the lane (first token field) when a formula is
showing and no ambiguity picker is pending; Tab/Shift-Tab then walk the tokens
through the native key-view loop. Return submits from the main editor only.

## Extension Rule

To add another completion UI:

1. Add a small typed IR in `FriendlyCompiler`, plus a `FormulaIR` case and
   parse hook.
2. Parse the relevant friendly command from `ShellModel.draft` (tolerantly —
   see Partial Edits above).
3. Render edits back to friendly input.
4. Let `CompiledInput` remain the only app compile boundary.
5. Keep the visual hint lane readable without hiding optional arguments behind
   horizontal scrolling at the normal window size. Reuse `FormulaFunctionChip`
   and `FormulaTokenField`; tokens that carry whole equations or binding lists
   should pass `growsWithContent: true` (the lane's `.fixedSize` layout sizes
   fields to their IDEAL width, so a fixed compact ideal clips long payloads
   regardless of `maxWidth`).
6. Add the family to `PartialEditInvarianceTests` and the round-trip/`#ROW`
   preservation tests.

Do not have completion UI emit Sage directly.
