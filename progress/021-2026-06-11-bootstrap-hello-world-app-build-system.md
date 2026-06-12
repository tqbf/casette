## 2026-06-11 — Bootstrap: hello-world app + build system

**Did.** Stood up the project skeleton and the `swift build` + `build.sh` +
`Makefile` build system, modeled on `Makefile.example` (the Moves pipeline).
No Xcode IDE, no xcodebuild.

- `Package.swift` — SwiftPM, `swift-tools-version:6.0`, macOS 14 floor,
  executable target `Casette` + `CasetteTests` (swift-testing).
- `Sources/Casette/CasetteApp.swift` — `@main` `App` with a `WindowGroup`,
  `.windowResizability(.contentMinSize)`.
- `Sources/Casette/ContentView.swift` — hello-world: `f(x)` glyph + title +
  subtitle. Semantic fonts, centralized `Metrics` enum, `accessibilityHidden`
  on the decorative glyph (per SWIFTUI-RULES §5.1, §2.4).
- `Resources/Info.plist` — bundle plist with `__SHORT_VERSION__` /
  `__BUILD_VERSION__` placeholders substituted by `build.sh`.
- `Casette/Casette.entitlements` — App Sandbox **off** (will spawn a Sage
  worker process in V1.3); hardened-runtime exceptions for exec'ing an
  interpreter. Sandboxed/bundled Sage is a V2 concern.
- `build.sh` — `swift build` → assemble `build/Casette.app` (MacOS binary,
  Info.plist w/ version substitution, PkgInfo, optional icon) → codesign with
  `SIGN_IDENTITY` and **ad-hoc fallback** so `make run` works with no certs.
- `scripts/make-icon.swift` — pure-CoreGraphics icon: draws a cassette tape
  (the "session tape") into `build/AppIcon.iconset` at all 10 sizes;
  `iconutil` packs it. No asset files, runs under bare `swift`.
- `Makefile` — adapted from `Makefile.example`: `build/check/test/run/icon/
  clean/install/register` + the full `dist` sign→notarize→staple→zip pipeline.
  Defaults are ad-hoc-friendly (`DEV_IDENTITY := -`, signing identity / team id
  left blank until someone fills them for `make dist`).
- `.gitignore` — `.build/ build/ dist/`.

**Gate passed (per SWIFTUI-RULES §9.1, "launch + alive check").**
`make check` ✓ · `make test` ✓ (1 smoke test) · `make build` ✓ (ad-hoc signed,
`codesign --verify` clean) · launched `Casette.app`, alive after 4s, renders
correctly (screenshotted), quit clean.

**Learned / surprised.**
- `${VAR:-default}` in `build.sh` covers the empty-string case, not just unset
  — so `VERSION=""` from the Makefile (no tag, no VERSION file) still resolves
  to `0.0.0`. Confirmed in the stamped Info.plist.
- `swiftui-pro` flagged a `.windowToolbarStyle(.unified)` I'd added with no
  toolbar present — removed it (keep it simple).

**Next.** V0.1 — the Sage worker protocol. The first real gate: can we boot
Sage, send eval requests, preserve state, and get structured JSONL responses
reliably? Nothing else matters until that works.
