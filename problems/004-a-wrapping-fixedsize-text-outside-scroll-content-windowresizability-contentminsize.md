## A wrapping `fixedSize` Text OUTSIDE scroll content + `.windowResizability(.contentMinSize)` = the window's MIN HEIGHT balloons to ~1600pt the moment the view appears

**The symptom (V1.6 live gate).** Selecting a result row (which populates the
Actions sidebar tab) made the whole window instantly GROW to 1100×1598 — and
1598pt became a hard MINIMUM: AppleScript `set size`, macOS zoom-to-fit, and
manual resize all refused to shrink it. On a 967pt-tall display the bottom
~660pt of the window (input pane, sidebar footer) were permanently off-screen
and unreachable. Two verification rounds burned before the repro was pinned:
click a result row with the Actions tab visible → balloon.

**The mechanism.** The Actions tab pinned a hint under its List:
`VStack { List {...}; Text(hint).fixedSize(horizontal: false, vertical: true) }`.
With `.windowResizability(.contentMinSize)`, AppKit asks SwiftUI for the
content's minimum size, and that measurement proposes ~ZERO width. At zero
width the wrapping Text lays out one character per line — ~100 lines — and
`fixedSize(vertical: true)` makes that height a REQUIREMENT, not an ideal.
The window's min height becomes input-pane + tape-min + ~1500pt of
one-character-per-line hint text. Bisected by removing the Text (balloon
gone) and confirmed by the arithmetic.

**The fix + the rule.** Put wrapping helper text INSIDE the scrollable
content (a plain final List row, `.listRowSeparator(.hidden)`): scroll
content never participates in window min-size measurement, and a list row's
width proposal is always the real column width, so the text wraps correctly
at any sidebar width. General rules:
1. Under `.windowResizability(.contentMinSize)`, every NON-scrolling view in
   the window participates in the window's minimum size. A
   `fixedSize(horizontal: false, vertical: true)` Text is a min-height bomb
   there — its min height is its height at min width, which for wrapping
   text is absurd.
2. macOS `List` Section footers single-line-truncate at narrow widths (the
   original V1.6 defect), so the footer idiom isn't the answer either — an
   ordinary in-list row is.
3. When a window won't shrink, suspect content min size, and bisect the
   newest non-scrolling view. `set size of front window` via System Events
   is the cheap probe (it silently clamps to the real minimum).

---
