# V0.5 — Plot & Artifact Pipeline

Proves Sage-generated plot artifacts move from the worker to the macOS UI. Two
halves, both standalone (the SwiftUI viewer is its own `Package.swift`,
deliberately **not** entangled with the main Casette app — that integration is
V1.7):

1. **Worker side** — the canonical worker (`../01-worker-protocol/worker.py`,
   extended in place) saves a Sage `Graphics`/`GraphicsArray` to image files and
   reports them in the envelope's `artifacts` array. Spec + frozen artifact shape
   in [`plans/WORKER-PROTOCOL.md`](../../plans/WORKER-PROTOCOL.md).
2. **`harness.py`** — drives the spec's plot cases through a live worker and
   asserts the files exist, are nonempty, parse as SVG/PNG, and never collide.
3. **`CasettePlotProof`** — a SwiftUI viewer that loads the artifact files and
   renders them in a scrolling tape with a per-row SVG/PNG toggle and zoom.

## Run

```bash
# Worker + harness (88 checks). --keep leaves the session dir for the viewer.
python3 harness.py
python3 harness.py --keep          # prints SESSION_DIR=… ; viewer auto-finds it
python3 harness.py --json          # dump full envelopes

# Viewer (loads the newest /tmp/sagecalc/session-* dir)
swift run                          # builds + launches the window
./bundle.sh debug && open build/CasettePlotProof.app   # as a real .app
```

Produce artifacts first (`python3 harness.py --keep`), then launch the viewer.

## Artifact contract (V0.5)

Each plot → an **SVG + PNG** pair (SVG first), saved under a session-scoped dir
with a monotonic, collision-free name:

```json
"artifacts": [
  {"type":"image","format":"svg","path":"/tmp/sagecalc/session-<pid>-<rand>/plot-00001.svg","bytes":20587},
  {"type":"image","format":"png","path":"/tmp/sagecalc/session-<pid>-<rand>/plot-00001.png","bytes":18896}
]
```

- **Two capture channels:** the echoed value (last expr is a plot) and a wrapped
  `.show()` (captures instead of opening a GUI window → several plots per eval).
- **Lifetime:** session dir removed on clean `shutdown`; a hard kill leaves it,
  but it's pid+rand-namespaced under `/tmp`. The app may clean the tree on launch.
- **Failures structured:** a bad plot *call* → normal error envelope; a *save*
  failure → a per-format `{"path":null,"error":…}` entry, eval still `ok:true`.

## The finding: render PNG, not SVG

Sage 9.5 saves SVG/PNG/PDF cleanly. On macOS, **PNG renders perfectly via
`NSImage`/`NSBitmapImageRep`**; **SVG loads but the system `_NSSVGImageRep`
mis-rasterizes matplotlib's text-as-glyphs into a large black blob over the
curve** (verified on screen). So the viewer defaults to PNG; SVG is kept only for
a future real SVG engine. Detail in [`PROBLEMS.md`](../../PROBLEMS.md).

## Exit criteria — all verified (harness + ON SCREEN via computer-use)

| Criterion | Result |
| --- | --- |
| Worker generates plot files | PASS — SVG+PNG for sin / implicit / parametric |
| Parent receives artifact metadata | PASS — `artifacts` entries with path+bytes |
| SwiftUI renders the artifact | PASS — PNG renders crisply; on screen |
| Multiple plots don't collide | PASS — monotonic names; 16 unique files / session |
| Predictable lifetime | PASS — session dir removed on clean shutdown |
| SVG works OR PNG fallback proven | PASS — **PNG proven**; SVG corrupts (documented) |
| Plot failures return structured errors | PASS — save error structured; bad call → error envelope |

No worker regression: V0.1 18/18 · V0.2 35/35 · V0.3 97/97.
