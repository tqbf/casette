#!/usr/bin/env python3
"""Parent-side test harness for the Casette plot/artifact pipeline (V0.5).

Boots the *canonical* worker once (`sage -python ../01-worker-protocol/worker.py`,
extended in place for V0.5), drives the spec's plot test cases through it in a
single persistent session, and asserts that each plot becomes one or more
artifact files that exist, are nonempty, parse as the format they claim
(SVG/PNG), and never collide across plots or evals.

Spec test cases:
  * plot(sin(x), (x, -pi, pi))
  * implicit_plot(x^2 + y^2 == 1, (x,-2,2), (y,-2,2))
  * parametric_plot((cos(t), sin(t)), (t,0,2*pi))
Plus, beyond the spec minimum:
  * several plots in ONE eval (via .show()) and several evals each plotting,
  * a plot FAILURE case (structured error, protocol intact).

Runs under plain Python 3 (the parent app's runtime), NOT under Sage. Usage::

    python3 harness.py
    python3 harness.py --sage /usr/local/bin/sage    # override Sage path
    python3 harness.py --json                         # dump full envelopes
    python3 harness.py --keep                         # don't shutdown-clean the
                                                      # session dir (for the
                                                      # SwiftUI viewer to load)

Exit status is 0 iff every exit criterion passes. With --keep it prints the
session dir path on the last line as `SESSION_DIR=<path>` for the viewer build.
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import time


HERE = os.path.dirname(os.path.abspath(__file__))
# Test the ONE canonical worker (owned by V0.1, extended in place for V0.5).
WORKER = os.path.normpath(os.path.join(HERE, "..", "01-worker-protocol", "worker.py"))


class Worker:
    """Thin parent-side wrapper around the worker subprocess."""

    def __init__(self, sage):
        self.proc = subprocess.Popen(
            [sage, "-python", WORKER],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
            start_new_session=True,
        )

    def await_ready(self):
        deadline = time.time() + 120
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("worker died before ready")
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("op") == "ready":
                return obj
        raise RuntimeError("worker never became ready")

    def eval(self, code, rid=None):
        rid = rid or ("e%d" % int(time.time() * 1e6))
        self.proc.stdin.write(json.dumps({"id": rid, "code": code}) + "\n")
        self.proc.stdin.flush()
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError("worker closed stdout (no response)")
        return json.loads(line)

    def shutdown(self):
        try:
            self.proc.stdin.write(json.dumps({"op": "shutdown"}) + "\n")
            self.proc.stdin.flush()
            self.proc.wait(timeout=10)
        except Exception:
            try:
                os.killpg(os.getpgid(self.proc.pid), signal.SIGKILL)
            except ProcessLookupError:
                pass


# ---------------------------------------------------------------------------
# Assertions / reporting.
# ---------------------------------------------------------------------------

PASS, FAIL = "PASS", "FAIL"
results = []


def check(name, ok, detail=""):
    results.append((name, PASS if ok else FAIL, detail))
    mark = "  ok " if ok else " FAIL"
    print(f"[{mark}] {name}" + (f"  — {detail}" if detail else ""))
    return ok


def is_svg(path):
    try:
        with open(path, "rb") as f:
            head = f.read(512)
    except OSError:
        return False
    # Sage/matplotlib SVG starts with an XML decl then a <svg ...> root.
    return b"<svg" in head or head.lstrip().startswith(b"<?xml")


def is_png(path):
    try:
        with open(path, "rb") as f:
            return f.read(8) == b"\x89PNG\r\n\x1a\n"
    except OSError:
        return False


def artifact_files(env):
    """All non-error artifact paths in an envelope's artifacts array."""
    return [a for a in env.get("artifacts", []) if a.get("path")]


def assert_plot_envelope(label, env, want_plots=1):
    """Assert an envelope carries `want_plots` plots, each saved as a nonempty,
    format-valid SVG + PNG pair, returning the set of SVG paths seen."""
    arts = env.get("artifacts", [])
    check(f"{label}: ok=true", env.get("ok") is True, f"ok={env.get('ok')}")
    check(f"{label}: kind=plot", env.get("kind") == "plot",
          f"kind={env.get('kind')}")
    # Each plot yields one svg + one png entry.
    svgs = [a for a in arts if a.get("format") == "svg" and a.get("path")]
    pngs = [a for a in arts if a.get("format") == "png" and a.get("path")]
    check(f"{label}: {want_plots} SVG artifact(s)", len(svgs) == want_plots,
          f"got {len(svgs)}")
    check(f"{label}: {want_plots} PNG artifact(s)", len(pngs) == want_plots,
          f"got {len(pngs)}")

    seen = set()
    for a in arts:
        p = a.get("path")
        if not p:
            continue
        seen.add(p)
        exists = os.path.isfile(p)
        nonempty = exists and os.path.getsize(p) > 0
        check(f"{label}: {os.path.basename(p)} exists+nonempty",
              nonempty, f"path={p} bytes={a.get('bytes')}")
        if a.get("format") == "svg":
            check(f"{label}: {os.path.basename(p)} parses as SVG",
                  exists and is_svg(p))
        elif a.get("format") == "png":
            check(f"{label}: {os.path.basename(p)} parses as PNG",
                  exists and is_png(p))
        # The reported byte size should match the file on disk.
        if exists and a.get("bytes") is not None:
            check(f"{label}: {os.path.basename(p)} reported size matches disk",
                  a["bytes"] == os.path.getsize(p),
                  f"reported={a.get('bytes')} disk={os.path.getsize(p)}")
    return seen


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sage", default="/usr/local/bin/sage")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--keep", action="store_true",
                    help="don't shutdown (keep session dir for the viewer)")
    args = ap.parse_args()

    w = Worker(args.sage)
    ready = w.await_ready()
    print("worker ready, pid=%s" % ready.get("pid"))

    # A bare `from sage.all import *` does NOT predefine `x`/`y`/`t` the way the
    # interactive Sage REPL does (that injection is REPL-only). The worker
    # protocol notes this: callers that rely on symbols must declare them. Do so
    # once in the persistent namespace so the spec's plot expressions resolve.
    w.eval("x, y, t = var('x y t')")

    all_svg_paths = []      # to assert no collisions across the whole session
    all_paths = []          # every artifact path produced
    session_dir = None

    def remember(env):
        for a in env.get("artifacts", []):
            if a.get("path"):
                all_paths.append(a["path"])
                if a.get("format") == "svg":
                    all_svg_paths.append(a["path"])
                # Capture the session dir from the first real path.
                nonlocal session_dir
                if session_dir is None:
                    session_dir = os.path.dirname(a["path"])

    # ---- Spec case 1: plot(sin(x)) -----------------------------------------
    e1 = w.eval("plot(sin(x), (x, -pi, pi))")
    if args.json:
        print(json.dumps(e1, indent=2))
    assert_plot_envelope("sin", e1, want_plots=1)
    remember(e1)

    # ---- Spec case 2: implicit_plot (circle) -------------------------------
    e2 = w.eval("implicit_plot(x^2 + y^2 == 1, (x,-2,2), (y,-2,2))")
    if args.json:
        print(json.dumps(e2, indent=2))
    assert_plot_envelope("implicit", e2, want_plots=1)
    remember(e2)

    # ---- Spec case 3: parametric_plot (circle) -----------------------------
    e3 = w.eval("parametric_plot((cos(t), sin(t)), (t,0,2*pi))")
    if args.json:
        print(json.dumps(e3, indent=2))
    assert_plot_envelope("parametric", e3, want_plots=1)
    remember(e3)

    # ---- Multi-plot in ONE eval (via .show()) ------------------------------
    # Two plots shown in a single eval must yield two distinct artifact pairs.
    multi = w.eval(
        "p = plot(sin(x),(x,-pi,pi)); q = plot(cos(x),(x,-pi,pi)); "
        "p.show(); q.show()")
    if args.json:
        print(json.dumps(multi, indent=2))
    assert_plot_envelope("multi", multi, want_plots=2)
    remember(multi)

    # ---- Several evals each producing a plot (rapid succession) ------------
    rapid = []
    for i in range(3):
        ei = w.eval("plot(sin(%d*x),(x,-pi,pi))" % (i + 1))
        assert_plot_envelope("rapid%d" % i, ei, want_plots=1)
        remember(ei)
        rapid.append(ei)

    # ---- Plot FAILURE: a save error must be a STRUCTURED artifact error, not
    # a crash. We force a save failure by patching the plot's .save to raise,
    # inside the eval — the eval must still return ok=true with an error entry
    # in artifacts (the plot object is still echoed). The protocol stays intact:
    # we prove it by doing a normal eval right after.
    fail = w.eval(
        "g = plot(sin(x),(x,-pi,pi)); "
        "g.save = (lambda *a, **k: (_ for _ in ()).throw(IOError('boom'))); "
        "g.show(); 1")
    if args.json:
        print(json.dumps(fail, indent=2))
    fail_arts = fail.get("artifacts", [])
    check("plot-fail: eval still ok=true (no crash)", fail.get("ok") is True,
          f"ok={fail.get('ok')}")
    check("plot-fail: structured error artifact present",
          any(a.get("error") for a in fail_arts),
          f"artifacts={fail_arts}")
    check("plot-fail: no real file claimed for failed save",
          all(a.get("path") is None for a in fail_arts if a.get("error")),
          "")

    # ---- Bad-plot-call FAILURE: plot() itself raises -> normal error envelope
    bad = w.eval("plot(sin(x), (x, 0, 'notanumber'))")
    if args.json:
        print(json.dumps(bad, indent=2))
    check("bad-plot: ok=false", bad.get("ok") is False, f"ok={bad.get('ok')}")
    check("bad-plot: kind=error", bad.get("kind") == "error",
          f"kind={bad.get('kind')}")
    check("bad-plot: has structured error",
          isinstance(bad.get("error"), dict) and bad["error"].get("type"),
          f"error={bad.get('error')}")

    # ---- Protocol still intact after the failures --------------------------
    sanity = w.eval("1 + 1")
    check("protocol intact after failures (1+1=2)",
          sanity.get("ok") and sanity.get("plain") == "2",
          f"plain={sanity.get('plain')}")

    # ---- No-collision check across the WHOLE session -----------------------
    check("no SVG path collisions across session",
          len(all_svg_paths) == len(set(all_svg_paths)),
          f"{len(all_svg_paths)} svg paths, {len(set(all_svg_paths))} unique")
    check("no artifact path collisions across session",
          len(all_paths) == len(set(all_paths)),
          f"{len(all_paths)} paths, {len(set(all_paths))} unique")
    check("all artifacts under one session dir",
          session_dir is not None and
          all(os.path.dirname(p) == session_dir for p in all_paths),
          f"session_dir={session_dir}")
    # Predictable layout: /tmp/sagecalc/session-<pid>-<rand>/plot-NNNNN.svg
    check("session dir under /tmp/sagecalc",
          session_dir is not None and
          session_dir.startswith("/tmp/sagecalc/session-"),
          f"session_dir={session_dir}")

    print("\nTotal artifact files produced this session: %d (%d SVG)" %
          (len(all_paths), len(all_svg_paths)))

    # ---------------------------------------------------------------------
    if args.keep:
        # Leave the worker's session dir in place for the SwiftUI viewer.
        # Hard-kill the worker WITHOUT a clean shutdown (which would rmtree it).
        try:
            os.killpg(os.getpgid(w.proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        print("SESSION_DIR=%s" % session_dir)
    else:
        # Clean shutdown also proves the lifetime policy: the session dir is
        # removed when the worker exits cleanly.
        w.shutdown()
        cleaned = session_dir is not None and not os.path.isdir(session_dir)
        check("session dir removed on clean shutdown (lifetime policy)",
              cleaned, f"session_dir={session_dir} exists={not cleaned}")

    # ---- Summary -----------------------------------------------------------
    npass = sum(1 for _, s, _ in results if s == PASS)
    nfail = sum(1 for _, s, _ in results if s == FAIL)
    print(f"\n{npass}/{npass + nfail} checks passed.")
    if nfail:
        print("FAILURES:")
        for n, s, d in results:
            if s == FAIL:
                print(f"  - {n}  {d}")
    sys.exit(0 if nfail == 0 else 1)


if __name__ == "__main__":
    main()
