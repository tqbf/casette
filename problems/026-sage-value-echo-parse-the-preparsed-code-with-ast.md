## Sage value-echo: parse the *preparsed* code with `ast`, and suppress `None`

To mimic the REPL ("last expression prints its value"), parse the **preparsed**
source (not the raw source) with `ast`, exec all leading statements, and `eval`
the final node only if it's an `ast.Expr`. Suppress a `None` result so a bare
`print(...)` or an assignment echoes nothing (`kind:"none"`, `value:false`) —
otherwise `print("hello")` wrongly reports `plain:"None"`.

Note: in Sage 9.5, `factor(x^4 - 1)` returns `(x^2 + 1)*(x + 1)*(x - 1)`
(ordering differs from the spec's illustrative `(x - 1)*(x + 1)*(x^2 + 1)` —
mathematically identical; don't hard-code string equality on factor output).
