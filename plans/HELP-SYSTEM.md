# Help System

Casette now has a native SwiftUI Help window for the Friendly Compiler mini
language. The Help menu includes **Friendly Compiler Language**, which opens a
separate utility window with searchable reference content.

The help content is code-native in `HelpReference` instead of loaded from a
loose Markdown file. That keeps the packaged `.app` reliable under SwiftPM's
current executable target setup, and it lets tests assert that the shipped
reference covers the current command families.

Design notes:

- The Help window is a single-purpose utility surface, so it does not use a
  sidebar.
- The top bar uses `.bar` material and a compact search field, matching a
  standard macOS reference window.
- Prose uses the app's regular semantic callout style; friendly input and Sage
  output use monospaced semantic styles from `Theme.Fonts`.
- The reference intentionally shows the generated Sage for every example,
  preserving Casette's "friendly in, Sage out" contract.

Validation:

- `HelpReferenceTests` checks representative command-family coverage and the
  key boundary rules: command-call bypass, tape references, and required plot
  ranges.
