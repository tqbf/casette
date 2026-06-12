## Parallel swift-testing + `setenv`: tests that pass config through process-global env race every test that reads it

**The symptom (V1.6 gate).** The frozen v0/10 suite — green at every prior
gate — failed once during the V1.6 regression:
`defaultDirectoryUsesApplicationSupportWhenNoOverride` saw a
`/tmp/casette-cfg-<UUID>/sessions` path where it expected the Application
Support default. Rerun: 21/21. `--no-parallel`: 21/21.

**The cause.** swift-testing runs a target's tests **in parallel inside one
process**, and environment variables are process-global. One test does
`setenv("CASETTE_CONFIG_DIR", override, 1)` (with a deferred `unsetenv`)
while the no-override test calls `unsetenv` and then reads the default — the
two interleave, and the no-override test observes its sibling's override.
The hermetic override that makes each test clean in isolation is exactly
what makes the suite racy in parallel.

**Rules.**
1. **Don't pass test configuration through `setenv`** — inject the path/value
   as a parameter (the SUT should take its config dir as an argument, with
   the env var consulted only at the production call site). If env mutation
   is unavoidable, mark the suite `.serialized`.
2. A test failure that names a SIBLING test's fixture (here: the other
   test's `/tmp/casette-cfg-` pattern) is a parallelism leak, not a logic
   bug — rerun serialized before touching code.
3. v0/ is frozen evidence, so the race stays documented rather than fixed
   there; V1.9's app-side persistence tests must follow rule 1.

---
