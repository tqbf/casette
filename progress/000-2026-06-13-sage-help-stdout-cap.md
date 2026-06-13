# Sage Help stdout cap

Status: PASS

`help(x)` for a Sage symbolic expression returns a very large pydoc payload
(about 386 KB on the local Sage 9.5 install). The worker already captured it as
stdout correctly, but handing that much text to a SwiftUI tape row made the app
feel hung.

The canonical worker now caps captured stdout/stderr at 32,768 characters and
appends a visible truncation note. This preserves the normal stdout rendering
path for Sage help text while keeping the app responsive. The V0.1 worker
harness now covers `help(x)` after `x = var("x")`, asserting that the help text
is returned as bounded stdout and that the protocol remains healthy.

Follow-up: a restored pre-fix row can still contain a much larger stdout string
on disk. `StdoutBlockView` now renders only a 16,384-character preview with an
honest omitted-character note, so session restore and first paint stay bounded
even for old help rows.

Validation:

- `python3 v0/01-worker-protocol/harness.py --sage /usr/local/bin/sage`:
  19/19 passed.
- `swift test --filter StdoutDisplayCapTests`: 2/2 passed.
- `make check`: passed.
- `swift test`: 632/632 passed.
- `make build`: passed; bundled `worker.py` contains the stdout cap.
