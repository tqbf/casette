import SwiftUI

// MARK: - MathRenderer abstraction (V1.5)
//
// LIFTED from v0/04-latex-rendering/Sources/CasetteLatexProof/MathRenderer.swift
// — the surviving V0.4 artifact, migrated here per plans/MATH-RENDERING.md.
// The single v0/04 file is split across Rendering/ (one type per file, the
// app convention); each type's code is otherwise the proven V0.4 shape.
//
// The app never talks to a concrete math library directly — it asks a
// `MathRenderer` for a SwiftUI view. That keeps the engine swappable
// (SwiftMath today) without touching any call site. V0.4 proved the seam:
// the LaTeXSwiftUI→SwiftMath engine swap was one line.
//
// V1.5 deviation from the v0/04 file, documented in MATH-RENDERING.md: the
// `LaTeXSwiftUIRenderer` alternative is NOT lifted into the app. It stays on
// record in the frozen v0/04 proof; shipping it would add the multi-megabyte
// MathJax/JavaScriptCore bundles to the product for an engine V0.4 measured
// as broken here (braced scripts). The seam itself is what survives.
//
// Contract:
//   - `render(_:displayStyle:)` returns a `View` for a single LaTeX string
//     drawn from the worker envelope's `latex` field.
//   - The renderer is responsible for graceful degradation: malformed LaTeX
//     must NOT crash and must NOT vanish — it shows the raw source as a
//     visible degraded fallback. The app relies on this guarantee.

/// How a piece of math should be laid out in the tape.
enum MathDisplayStyle {
    /// Block / display math — on its own line, full size. The default for a
    /// result row's hero math.
    case block
    /// Inline math — text-mode layout at a smaller size, for math shown
    /// alongside chrome (the Inspector's LaTeX preview).
    case inline
}

/// The abstraction every view renders math through. Implementations wrap a
/// concrete typesetting engine. `render` is `@MainActor` because SwiftUI view
/// construction (and the underlying engines) are main-actor-isolated.
@MainActor
protocol MathRenderer {
    associatedtype Body: View
    /// A short identifier for the backing engine (diagnostics, docs).
    nonisolated var engineName: String { get }
    @ViewBuilder
    func render(_ latex: String, displayStyle: MathDisplayStyle) -> Body
}
