# Formula Autocomplete

Casette's formula autocomplete is a UI layer over friendly input, not a
parallel Sage compiler.

## Current Prototype

The first supported function is `integral`. When the draft begins with
`integral` or `integrate`, the input pane shows a compact Numbers-style token
bar:

- function token: `INTEGRAL`
- editable expression token
- editable variable token
- optional lower-bound token
- optional upper-bound token

The text editor remains the source of truth. Editing a token rewrites the draft
to friendly input:

```text
integral #14 + x^2, x=0..1
```

That source form is the IR between UI and compiler. It deliberately preserves
app-level source such as `#14` tape references. `CompiledInput.compile` expands
tape references before invoking `FriendlyCompiler`, so the generated Sage
becomes:

```text
integrate(__casette_tape_refs[14] + x^2, (x, 0, 1))
```

For explicit indefinite integrals, the compiler now accepts:

```text
integral x*y, wrt y
```

which compiles to:

```text
integrate(x*y, y)
```

## Extension Rule

Future formula bars should add a small typed IR in `FriendlyCompiler`, render
that IR back to friendly input, and let `CompiledInput` remain the single app
compile boundary. Do not have the UI emit Sage directly.
