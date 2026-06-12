## The V0.7 friendly compiler FLATTENS NEWLINES — route multiline input around it, or raw Sage gets corrupted

**The trap (V1.4).** `FriendlyCompiler.compile` was written for one line of
input and begins by normalizing: `rawInput.replacingOccurrences(of: "\n",
with: " ")`. That's correct for its domain (friendly commands are single-line
forms), but V1.4 adds a multiline input field — and a multiline *raw Sage*
submission piped through the compiler comes back from `.bypass` with its
newlines flattened to spaces. Python/Sage is newline-sensitive, so
`a = 5⏎a * 9` silently becomes the syntax error `a = 5 a * 9`. The bypass
contract ("returned untouched") is broken by the normalizer before the bypass
decision is even made — and nothing fails loudly; the user just gets a
confusing SyntaxError row.

**The fix — decide multiline BEFORE the compiler.** In the app's compile
boundary (`CompiledInput.compile`): input containing a newline is raw Sage by
definition and bypasses without ever entering the library. No friendly form
is multiline, so nothing is lost; the frozen library stays byte-identical to
the v0/07 proof. **Rule: when lifting a single-line parser into a multiline
input surface, gate on the line count at the boundary — don't widen the
frozen parser's domain.** (Also reconfirmed while testing this: the worker's
star-import predefines NO symbolic variables — not even `x`, despite a stray
aside in FRIENDLY-COMPILER.md — so the always-declare `var('V')` prelude
policy is load-bearing for every friendly form, x included.)

---
