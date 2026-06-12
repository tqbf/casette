# Completion UI

Casette's completion UI is an editing aid over friendly input. It does not
compile directly to Sage and it does not own a second source buffer.

## Source Of Truth

`ShellModel.draft` is the single source of truth for the input pane. Completion
views parse that draft into a small typed shape, let the user edit the shape,
then render it back to friendly input.

For the current integral prototype:

- `ShellModel.integralFormula` parses `draft` using `IntegralFormulaIR.parse`.
- `IntegralFormulaBar` edits that `IntegralFormulaIR`.
- `ShellModel.updateIntegralFormula(_:)` replaces `draft` with
  `IntegralFormulaIR.friendlyInput`.

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

## Extension Rule

To add another completion UI:

1. Add a small typed IR in `FriendlyCompiler`.
2. Parse the relevant friendly command from `ShellModel.draft`.
3. Render edits back to friendly input.
4. Let `CompiledInput` remain the only app compile boundary.
5. Keep the visual hint lane readable without hiding optional arguments behind
   horizontal scrolling at the normal window size.

Do not have completion UI emit Sage directly.
