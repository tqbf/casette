## Interrupting Sage: cysignals owns SIGINT and makes C code abortable — don't clobber it

**The question (V0.2 spec): does SIGINT reach mid-computation Sage? Does it abort
C-level loops?** Answer, measured: **yes, promptly — but only because of
cysignals, and only if you don't overwrite its handler.**

**What's actually installed.** After `from sage.all import *`, the process's
SIGINT handler is **`cysignals.python_check_interrupt`** (a cyfunction), *not*
whatever Python handler you set. cysignals wraps Sage C/Cython in
`sig_on()`/`sig_off()` and, on SIGINT, longjmps out of the C frame at the next
interrupt check, raising `KeyboardInterrupt`. So `factorial(10^8)` — which runs
**>60s** uninterrupted — is **aborted at +3.00s** when SIGINT arrives. Verified in
the real worker.

**The trap that produced a 23-second deferral.** If you install your own
`signal.signal(signal.SIGINT, handler)` *after* the Sage import, you **clobber
cysignals' handler** and revert to plain-Python signal semantics: the handler only
runs between bytecode instructions, and a long GMP/C call never yields, so the
`KeyboardInterrupt` is deferred until the C call *returns* — measured at **+23s**
for `factorial(10^8)`. Same computation, same SIGINT, prompt vs 23s, decided
purely by *whose* SIGINT handler is in place.

**Rules.**
1. Let cysignals own SIGINT. Your worker's handler is a harmless fallback it
   supersedes (and it still raises `KeyboardInterrupt`, which your eval loop
   catches → `interrupted` envelope).
2. **Never assume SIGINT lands.** Sage code not wrapped in `sig_on/sig_off`, user
   code that does `signal.signal(SIGINT, SIG_IGN)`, or a tight pure-C loop with no
   check will swallow it. The parent must **escalate SIGINT → hard
   process-group kill** after a grace window. (Spec policy: brutal restart is OK.)
3. Send SIGINT to the worker's **real pid** (from the ready banner); hard-kill the
   whole **process group** (`os.killpg`) — see the wrapper lesson below.

---
