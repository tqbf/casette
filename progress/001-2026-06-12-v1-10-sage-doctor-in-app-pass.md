## 2026-06-12 — V1.10: Sage Doctor in app — PASS

**Sage Doctor is now in the app.** Added a standard macOS sheet reachable from
**Sage ▸ Sage Doctor…** and from setup-failure banners. It renders the selected
Sage binary, saved path, manual override field, native **Choose Sage…** picker,
discovery candidates, live diagnostic checks, and **Copy Report** (human
summary + the stable JSON contract from `plans/SAGE-DOCTOR.md`).

**Architecture.** The in-app Doctor reuses the app's single sources of truth:
`SageDiscovery` + `SageConfigStore` for path selection, `SageVersionDetector`
for `sage --version`, and the real `KernelTransport` / `SageKernel` seam for
worker checks. No second process-control stack was introduced. Setup failures
now flow as `KernelStatus.isSetupFailure`, so the banner opens the Doctor for
missing Sage / missing worker cases and still offers Restart Sage for runtime
crashes. `KernelTransport.sageBinaryPath` lets `SessionController` expose the
current binary; `ShellModel` fills the session header's `sageVersion`
asynchronously after boot/restart without delaying the boot prelude.

**UI.** The sheet is intentionally utility-shaped: grouped form sections,
metadata-scale details, selectable monospaced paths/details, system symbols for
ok/fail/skipped states, no custom chrome, and native ellipsis labels for commands
that open another panel. `swiftui-pro` review applied: separate view files, no
computed `some View` sections, `@Bindable` for editable model state,
`ContentUnavailableView` for empty checks, `foregroundStyle`, no manual
`Binding(get:set:)`, and no expensive body work beyond small derived labels.
`macos-design` review applied: standard sheet, focused utility layout, menu
placement under Sage, setup banner leading to the diagnostic path, and simple
light/dark-adaptive system colors. `typography-designer`: no new hardcoded
sizes; reused `Theme.Fonts` semantic roles.

**Gate.** `make check` ✓ · **`make test` 285/285** (47 suites; +7:
`DoctorModelTests` ×4 for discovery/version probe, Use This Sage success,
missing-path refusal, copyable report; `SageDoctorRunnerTests` ×2 for
fail-loud missing override and report/check order; `SageDoctorIntegrationTests`
×1 against REAL Sage: worker boot, eval, state persistence, LaTeX extraction,
plot artifact, interrupt, restart all ok) · `make build` ✓.

**Live check.** Fresh `build/Casette.app` launched; Computer Use saw the main
app and confirmed **Sage ▸ Sage Doctor…** in the menu. Selecting it opened the
Doctor sheet, but Computer Use then returned `remoteConnection` for Casette
while remaining able to inspect other apps. Casette did not crash; a
CoreGraphics on-screen window query showed both the main 1040×720 window and
the 680×560 Doctor sheet. Treat this as a Computer Use/app-accessibility quirk
to re-check in the next live gate, not a functional Doctor failure.

**Next.** V1.11 — Result Actions. Note: much of the result-action surface was
already implemented in V1.6; start by reconciling `plans/INITIAL.md` with the
current `ResultAction`/Actions-tab behavior before adding more UI.

---
