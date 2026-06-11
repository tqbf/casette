Here’s the plan I’d actually run: v0 as proof-point projects with hard gates; v1 as the real app bring-up.

# Sage-Backed macOS Calculator: Phased Project Plan

## Core Product Shape

The app is a native macOS calculator backed by SageMath.

The UI has three primary regions:

```text
┌───────────────────────────────────────────┬────────────────────┐
│                                           │ Sidebar tabs        │
│                                           │                    │
│ Large results pane / session tape         │ Symbols            │
│                                           │ History            │
│                                           │ Inspector          │
│                                           │ Actions            │
├───────────────────────────────────────────┴────────────────────┤
│ Bottom input pane                                               │
└────────────────────────────────────────────────────────────────┘
```

The app is not a notebook and not a spreadsheet. It is a calculator with a persistent session tape, live Sage state, rich math rendering, and a progressive bridge from friendly commands to raw Sage.

## Architecture Assumptions

V1 uses:

* SwiftUI for the app shell.
* Textual for rich result rendering where it fits.
* A long-lived Sage worker process.
* JSON-lines protocol between app and worker.
* One Sage session per app session.
* User-installed Sage for v1.
* Bundled/managed Sage deferred to v2.

The core bet:

```text
Native macOS UI
  ↕
SessionController
  ↕ JSONL over stdin/stdout or local socket
Sage worker
  ↕
Persistent Sage namespace
```

---

# V0: Proof-Point Projects

V0 is not the app. V0 is a set of focused projects that prove the technical risks. Most v0 code may be disposable, except the worker protocol and result model if they survive contact.

The rule: **do not build the app until v0 proves the kernel bridge.**

---

## V0.1 — Sage Worker Protocol

### Goal

Prove we can boot Sage, send it eval requests, preserve state, and receive structured responses reliably.

This is thing 1. Everything else relies on it.

### Build

A minimal worker launched as:

```bash
sage -python worker.py
```

The worker reads JSON lines from stdin and writes JSON lines to stdout.

Request:

```json
{"id":"req-1","code":"factor(x^4 - 1)"}
```

Response:

```json
{
  "id": "req-1",
  "ok": true,
  "kind": "symbolic",
  "plain": "(x - 1)*(x + 1)*(x^2 + 1)",
  "latex": "\\left(x - 1\\right)\\left(x + 1\\right)\\left(x^{2} + 1\\right)",
  "stdout": "",
  "stderr": "",
  "artifacts": []
}
```

### Test Cases

```python
2 + 2
x = var("x")
factor(x^4 - 1)
integrate(sin(x)^3, x)
A = matrix([[1,2],[3,4]])
A.eigenvalues()
print("hello")
1 / 0
```

### Exit Criteria

* Sage starts from a parent process.
* Multiple evals work in the same persistent namespace.
* Assignment state survives between evals.
* Python/Sage exceptions return structured errors.
* `stdout` and `stderr` are captured inside the response envelope.
* Protocol output is never corrupted by user code printing text.
* Parent can detect worker death.

---

## V0.2 — Worker Lifecycle, Interrupts, and Restart

### Goal

Prove the app can control Sage when Sage misbehaves.

A calculator that hangs permanently is dead.

### Build

Extend the worker harness with:

* Running state.
* Eval timeout.
* Cancel/interrupt command.
* Hard kill.
* Restart session.
* Crash detection.

### Test Cases

```python
while True:
    pass
```

```python
sleep(30)
```

```python
factorial(10^8)
```

```python
integrate(sin(x^x), x)
```

### Exit Criteria

* The parent process remains responsive during long evals.
* Current eval can be interrupted or killed.
* Worker can be restarted after a hard kill.
* UI-facing state can distinguish:

  * idle
  * running
  * completed
  * error
  * interrupted
  * timed out
  * crashed
  * restarting

### Opinionated v1 Policy

For v1, brutal restart is acceptable. Graceful interrupt is nice, but not required.

---

## V0.3 — Sage Result Envelope and Type Classification

### Goal

Prove we can turn Sage results into a small set of result types the app can render.

### Build

A result classifier that emits:

```json
{
  "kind": "matrix",
  "plain": "...",
  "latex": "...",
  "repr": "...",
  "approx": null,
  "actions": ["det", "rank", "rref", "eigenvalues"],
  "artifacts": []
}
```

### Minimum Result Kinds

```text
integer
rational
real
complex
symbolic expression
equation / relation
list / tuple
matrix
plot
text
error
unknown
```

### Test Cases

```python
ZZ(104729)
1/3 + 1/5
sqrt(2)
N(sqrt(2), digits=50)
sin(pi/3)
x^2 + 5*x + 6
solve(x^2 + 5*x + 6 == 0, x)
matrix([[1,2],[3,4]])
matrix([[1,2],[3,4]]).rref()
```

### Exit Criteria

* Each common result has a stable `kind`.
* Each result has `plain` output.
* Symbolic/math results have LaTeX where possible.
* Unknown objects degrade to `repr`, not failure.
* Large outputs are capped or summarized.
* Result metadata can drive UI actions.

---

## V0.4 — LaTeX Rendering in SwiftUI/Textual

### Goal

Prove the macOS UI can render math beautifully and reliably.

### Build

A tiny SwiftUI app that renders a scrolling list of math results.

Use Textual if it works well. Keep a `MathRenderer` abstraction so the app is not trapped if Textual’s math path is not enough.

### Test LaTeX

```latex
\int_0^1 x^2\,dx
```

```latex
\begin{bmatrix}1 & 2\\ 3 & 4\end{bmatrix}
```

```latex
\frac{\partial^2 f}{\partial x \partial y}
```

```latex
\sum_{n=0}^{\infty} \frac{x^n}{n!}
```

```latex
\left\{x \in \mathbb{R} : x^2 < 2\right\}
```

### Exit Criteria

* Inline math works.
* Block math works.
* Matrices render acceptably.
* Dark mode works.
* Scrolling performance is acceptable.
* Failed LaTeX produces a graceful fallback.
* Copy behavior is acceptable enough for v1.

---

## V0.5 — Plot and Artifact Pipeline

### Goal

Prove Sage-generated artifacts can move from worker to UI.

### Build

Worker support for generated image artifacts.

Candidate model:

```json
{
  "kind": "plot",
  "plain": "Graphics object consisting of 1 graphics primitive",
  "latex": null,
  "artifacts": [
    {
      "type": "image",
      "format": "svg",
      "path": "/tmp/sagecalc/session-123/plot-456.svg"
    }
  ]
}
```

### Test Cases

```python
plot(sin(x), (x, -pi, pi))
```

```python
implicit_plot(x^2 + y^2 == 1, (x,-2,2), (y,-2,2))
```

```python
parametric_plot((cos(t), sin(t)), (t,0,2*pi))
```

### Exit Criteria

* Worker can generate plot files.
* Parent receives artifact metadata.
* SwiftUI can render the artifact.
* Multiple plots do not collide.
* Artifacts have predictable lifetime.
* SVG works or PNG fallback is proven.
* Plot failures return structured errors.

---

## V0.6 — Live Symbol Table Introspection

### Goal

Prove we can show live Sage variables in the sidebar.

### Build

A worker command:

```json
{"id":"symbols-1","op":"symbols"}
```

Response:

```json
{
  "symbols": [
    {
      "name": "x",
      "kind": "symbolic variable",
      "summary": "x"
    },
    {
      "name": "A",
      "kind": "matrix",
      "summary": "2×2 over Integer Ring"
    }
  ]
}
```

### Test Cases

```python
x = var("x")
A = matrix([[1,2],[3,4]])
f(x) = sin(x)/x
n = 104729
del n
```

### Exit Criteria

* User-created symbols appear.
* Internal Sage junk is filtered.
* Deleted symbols disappear.
* Reassigned symbols update.
* Summaries are bounded.
* Symbol inspection does not accidentally trigger huge computation.

---

## V0.7 — Friendly Input Compiler

### Goal

Prove the Excel-like usability claim without inventing a general DSL.

The app should accept a small set of forgiving command forms and compile them to Sage.

### Build

A standalone compiler library and CLI:

```bash
sagecalc-compile "double integral x*y, x=0..1, y=0..x"
```

Output:

```python
integrate(integrate(x*y, (y, 0, x)), (x, 0, 1))
```

### Initial Supported Inputs

```text
factor x^4 - 1
expand (x + 1)^5
simplify sin(x)^2 + cos(x)^2
solve x^2 + 5*x + 6 = 0
solve x^2 + 5*x + 6 = 0 for x
derivative sin(x^2)
derivative sin(x^2) wrt x
integral x^2
integral x^2, x=0..1
double integral x*y, x=0..1, y=0..x
limit sin(x)/x, x->0
taylor sin(x), x=0, order=7
plot sin(x), x=-pi..pi
matrix [[1,2],[3,4]]
eigenvalues [[1,2],[3,4]]
rref [[1,2],[3,4]]
```

### Exit Criteria

* Compiler emits Sage, not direct eval.
* Generated Sage can be shown to the user.
* Raw Sage bypass works.
* Ambiguous input returns candidates or a structured parse error.
* Parse errors are useful.
* No implicit multiplication in v0 unless explicitly added later.

### Policy

This is a command shim, not a language.

---

## V0.8 — Exact/Numeric Display Policy

### Goal

Prove how exact and approximate results are represented.

### Test Cases

```python
1/3 + 1/5
sqrt(2)
N(sqrt(2), digits=50)
pi
sin(1)
sin(pi/3)
```

### Desired Display

```text
8/15
≈ 0.5333333333
```

### Exit Criteria

* Exact result is primary by default.
* Approximation is available for exact symbolic/numeric results.
* Precision can be configured.
* User can force numeric result.
* App does not accidentally coerce all math into floats.

---

## V0.9 — Sage Doctor / Environment Discovery

### Goal

Prove v1 can use user-installed Sage without bundling.

### Build

A small diagnostic tool, later embedded in the app.

It should find Sage, test it, and report status.

Example output:

```text
Sage path: /opt/homebrew/bin/sage
Sage version: ...
Worker boot: ok
Eval test: ok
LaTeX extraction: ok
Plot generation: ok
Interrupt/restart: ok
```

### Exit Criteria

* User can select Sage binary manually.
* Common install paths are searched.
* Version is detected.
* `sage -python worker.py` works.
* Failure diagnostics are useful.
* Configured path can be stored.

---

## V0.10 — Session Tape Persistence-Lite

### Goal

Prove the app can restore recent session history without becoming document-oriented.

### Build

A JSON session file containing:

```json
{
  "rows": [
    {
      "input": "factor x^4 - 1",
      "sage": "factor(x^4 - 1)",
      "result": {
        "kind": "symbolic",
        "plain": "...",
        "latex": "..."
      },
      "timestamp": "..."
    }
  ]
}
```

### Exit Criteria

* Last session tape can be restored.
* Inputs and rendered results survive app restart.
* Session can optionally replay into a fresh Sage worker.
* Replayed vs cached results are distinguishable.
* Missing artifacts degrade gracefully.

---

# V0 Completion Gate

Do not start v1 until these are true:

* Sage worker protocol is reliable.
* Worker can be killed and restarted.
* Common Sage results can be classified.
* LaTeX renders in SwiftUI.
* Plots can render as artifacts.
* Live symbols can populate a sidebar.
* Friendly command compiler proves the basic interaction model.

At that point, the project risk shifts from “can this work?” to “can this become a good macOS app?”

---

# V1: App Bring-Up Plan

V1 is the first real app. It should be small, native, keyboard-friendly, and usable for real coursework.

V1 should not chase every Sage feature. It should make the core loop excellent:

```text
type math
evaluate
see beautiful result
inspect generated Sage
reuse result
see live symbols
continue
```

---

## V1.1 — App Skeleton and Layout

### Goal

Create the native macOS app shell around the agreed layout.

### Build

* Main window.
* Large results pane.
* Tabbed right sidebar.
* Bottom input pane.
* Basic theme.
* Keyboard focus model.
* Placeholder data.

### Sidebar Tabs

Initial tabs:

```text
Symbols
History
Inspector
Actions
```

### Exit Criteria

* App launches fast.
* Layout feels like the product.
* Input pane owns keyboard focus by default.
* Results pane scrolls well.
* Sidebar can be hidden/shown.
* Window resizing behaves well.

---

## V1.2 — Session Model

### Goal

Define the in-app model for a calculator session.

### Core Types

```swift
Session
SessionRow
CompiledInput
Evaluation
ResultEnvelope
Artifact
SymbolSnapshot
KernelState
```

### Session Row Fields

```text
id
raw input
compiled Sage
status
result envelope
timestamp
duration
artifacts
expanded/collapsed UI state
```

### Exit Criteria

* Rows can be appended.
* Rows can be edited or copied.
* Rows have stable identity.
* Running rows are represented.
* Failed rows are represented.
* Result data is independent of UI rendering.

---

## V1.3 — Kernel Integration

### Goal

Connect the app to the Sage worker.

### Build

* `SageKernel` process wrapper.
* `SessionController`.
* Request/response routing by ID.
* Kernel state machine.
* Worker logs.
* Restart command.
* Basic error surfacing.

### Exit Criteria

* App can start Sage.
* App can evaluate raw Sage.
* Multiple evals work.
* State persists.
* Worker crash is visible.
* Restart resets state intentionally.
* User-facing error messages are decent.

---

## V1.4 — Input Pane v1

### Goal

Make the bottom input pane feel like a calculator, not a text editor bolted to a REPL.

### Build

* Single-line input by default.
* Expandable multiline input.
* Evaluate on Return.
* Newline on Shift-Return.
* Evaluate without advancing on Cmd-Return.
* Command history with Up/Down.
* Generated Sage disclosure.
* Friendly compiler integration.
* Raw Sage bypass.

### Initial Input Support

```text
raw Sage
calculator expressions
factor
expand
simplify
solve
derivative
integral
double integral
limit
plot
matrix
eigenvalues
rref
```

### Exit Criteria

* The user can stay on the keyboard.
* Friendly commands compile and evaluate.
* Generated Sage is inspectable.
* Compiler errors are shown inline.
* Raw Sage works without fighting the compiler.

---

## V1.5 — Result Rendering v1

### Goal

Render common results beautifully in the large results pane.

### Build Result Cards

* Scalar exact result.
* Scalar approximate result.
* Symbolic expression.
* Matrix.
* List/tuple.
* Plot.
* Text/stdout.
* Error.

### Result Card Pattern

Collapsed:

```text
factor x^4 - 1
= (x - 1)(x + 1)(x² + 1)
```

Expanded:

```text
Input:
factor x^4 - 1

Generated Sage:
factor(x^4 - 1)

Plain:
(x - 1)*(x + 1)*(x^2 + 1)
```

### Exit Criteria

* LaTeX results render in the tape.
* Plain fallback exists.
* Errors are readable.
* Tracebacks are hidden by default but available.
* Each card has copy affordances.
* Scrolling performance is acceptable.

---

## V1.6 — Sidebar v1

### Goal

Make Sage session state visible and useful.

### Symbols Tab

Shows live variables:

```text
x     symbolic variable
A     2×2 matrix over Integer Ring
f     symbolic function
n     integer
```

Actions:

```text
insert
copy Sage
forget
inspect
```

### History Tab

Shows prior inputs with quick reuse.

Actions:

```text
rerun
insert into input
copy
```

### Inspector Tab

Shows details for selected result:

```text
kind
plain representation
LaTeX
generated Sage
duration
artifacts
```

### Actions Tab

Shows context-sensitive actions for selected result.

Examples:

For expression:

```text
simplify
expand
factor
differentiate
integrate
plot
numeric approximation
```

For matrix:

```text
det
rank
rref
inverse
eigenvalues
```

### Exit Criteria

* Sidebar updates after each eval.
* Symbols tab reflects live state.
* Selecting a result updates Inspector and Actions.
* Sidebar actions can insert or evaluate commands.
* Sidebar never blocks core calculator flow.

---

## V1.7 — Plot Rendering v1

### Goal

Make basic Sage plots useful in the result pane.

### Build

* Render plot artifacts inline.
* Support PNG fallback.
* Store artifact metadata in session rows.
* Click-to-expand plot.
* Copy/export image affordance if easy.

### Exit Criteria

* Basic `plot` works.
* `implicit_plot` works.
* Plot errors are readable.
* Multiple plots work.
* Artifacts survive long enough for session use.

---

## V1.8 — Exact/Numeric Controls

### Goal

Expose exactness as a product feature, not a Sage weirdness.

### Build

* Default exact display.
* Secondary approximate display where useful.
* Per-result “approximate” action.
* Precision setting.
* Input affordance for numeric mode.

### Example

```text
8/15
≈ 0.5333333333
```

### Exit Criteria

* Exact results are primary.
* Approximation is one click away.
* Precision can be changed.
* Numeric mode does not pollute global behavior accidentally.

---

## V1.9 — Session Persistence and Recovery

### Goal

Make the app feel persistent without becoming document-oriented.

### Build

* Save recent tape automatically.
* Restore last session on launch.
* Remember Sage path.
* Remember UI layout.
* Optional “replay session” command.
* Mark cached results vs replayed results.

### Exit Criteria

* Quit/relaunch restores visible tape.
* App can recover after crash.
* Missing Sage path opens Sage Doctor.
* Session file format is simple and inspectable.

---

## V1.10 — Sage Doctor in App

### Goal

Make first launch and failure modes tolerable.

### Build

* Sage path selector.
* Auto-detection.
* Version check.
* Worker boot check.
* Eval check.
* LaTeX extraction check.
* Plot check.
* Restart check.

### Exit Criteria

* First launch can guide user to working Sage.
* Broken Sage config is diagnosable.
* App never fails silently because Sage is missing.
* Diagnostics can be copied into a bug report.

---

## V1.11 — Result Actions

### Goal

Turn the app from “Sage output renderer” into a calculator.

### Build

Contextual actions generated from result kind.

Expression actions:

```text
simplify
expand
factor
differentiate
integrate
plot
approximate
copy LaTeX
```

Matrix actions:

```text
det
rank
rref
inverse
eigenvalues
characteristic polynomial
```

Integer actions:

```text
factor
is prime
hex
binary
mod
```

### Exit Criteria

* Actions generate visible Sage commands.
* User can preview or immediately evaluate.
* Actions are result-kind-aware.
* Actions are useful enough to reduce Sage syntax lookups.

---

## V1.12 — Keyboard and Interaction Pass

### Goal

Make the app fast to drive.

### Required Shortcuts

```text
Return          evaluate
Shift-Return    newline
Cmd-Return      evaluate without advancing
Cmd-K           command palette
Cmd-L           focus input
Cmd-R           rerun selected row
Cmd-.           interrupt eval
Cmd-Shift-R     restart Sage
Cmd-B           toggle sidebar
```

### Exit Criteria

* Core flow is keyboard-first.
* Mouse interactions exist but are not required.
* Focus behavior is predictable.
* Interrupt is always reachable.

---

## V1.13 — Command Palette

### Goal

Make advanced math discoverable without building a huge custom language.

### Categories

```text
Algebra
Calculus
Linear Algebra
Plotting
Number Theory
Session
```

### Initial Commands

```text
Solve equation
Solve system
Factor polynomial
Derivative
Integral
Double integral
Limit
Taylor series
Matrix
RREF
Eigenvalues
Plot function
Restart Sage
Show symbols
```

### Exit Criteria

* Palette inserts templates into input.
* Templates compile to Sage.
* Palette is faster than menus.
* New users can discover capabilities without reading docs.

---

## V1.14 — Packaging for Sideloaded Use

### Goal

Produce a usable signed macOS app for local distribution.

### Build

* App signing.
* Settings storage.
* Worker resource bundling.
* Sage path config.
* Crash/log collection.
* Basic release archive.

### Exit Criteria

* App can be installed outside Xcode.
* App can launch and find configured Sage.
* Worker script is packaged with app.
* Logs are accessible.
* App can be updated manually.

---

# V1 Completion Criteria

V1 is done when the app can handle a real coursework session.

The target demo:

```text
factor x^4 - 1
solve x^2 + 5*x + 6 = 0
derivative sin(x^2)
integral x^2, x=0..1
double integral x*y, x=0..1, y=0..x
A = matrix([[1,2],[3,4]])
eigenvalues A
plot sin(x), x=-pi..pi
```

And during that demo:

* Results render nicely.
* Generated Sage is visible.
* Live symbols update.
* Plots appear inline.
* Errors are readable.
* Long evals can be interrupted.
* Session survives app restart.
* The user can drive the app mostly from the keyboard.

---

# Deferred to V2

Do not let these leak into v1:

* Bundled Sage installer.
* App Store sandboxing.
* Full document model.
* Notebook-style dependency recomputation.
* General natural language input.
* Handwriting recognition.
* General implicit multiplication.
* Cloud sync.
* Collaboration.
* Full symbolic-region parser for arbitrary multivariable integrals.
* Visual region editor.
* Full plugin system.

---

# Recommended Build Order Summary

## V0 Order

```text
1. Sage worker protocol
2. Worker lifecycle / kill / restart
3. Result envelope and type classification
4. LaTeX rendering
5. Plot artifacts
6. Live symbol table
7. Friendly input compiler
8. Exact/numeric policy
9. Sage Doctor
10. Session persistence-lite
```

## V1 Order

```text
1. App shell and layout
2. Session model
3. Kernel integration
4. Input pane
5. Result rendering
6. Sidebar
7. Plot rendering
8. Exact/numeric controls
9. Persistence/recovery
10. Sage Doctor in app
11. Result actions
12. Keyboard pass
13. Command palette
14. Sideload packaging
```

The two real gates are:

```text
V0.1: Can we talk to Sage reliably?
V1.5: Does typing math produce beautiful, useful results?
```

If those work, the app is real.
