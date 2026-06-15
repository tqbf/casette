# SwiftPM resource bundles in hand-assembled `.app`s need a verified lookup path

**Symptom.** A copied `Casette.app` can crash on launch with `EXC_BREAKPOINT`
inside SwiftPM's generated `Bundle.module` accessor for SwiftMath. The stack
then proceeds through `MTFont.fontBundle`, `MTFontManager.defaultFont`, and
`MTMathUILabel.initCommon()`.

**Cause.** SwiftMath stores its math fonts in
`SwiftMath_SwiftMath.bundle/mathFonts.bundle`. SwiftPM's generated accessor
first looks beside `Bundle.main.bundleURL`; for an app bundle, that means the
`.app` root. Casette's hand-built bundle wants resources under
`Contents/Resources`, so `build.sh` patches the derived accessor to check that
location. If the app is built with an unpatched accessor or copied away from
the developer `.build` fallback without the expected bundle layout, SwiftMath
traps before any LaTeX fallback policy can run.

**Fix.** `build.sh` now patches the generated accessor to search
`Contents/Resources`, verifies that the patch survived the second SwiftPM
build, and verifies that `latinmodern-math.otf` exists in the copied resource
bundle before codesigning.

**Rule.** For package dependencies that use `Bundle.module`, a hand-assembled
macOS app must verify that the generated lookup path matches the bundle layout.
Do not assume parser or renderer guards can help with missing resources; the
crash happens while the dependency initializes.
