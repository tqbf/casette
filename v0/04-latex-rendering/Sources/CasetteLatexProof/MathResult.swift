import Foundation

/// One renderable math result — the proof's stand-in for a session-tape row.
/// Mirrors the fields of the V0.3 worker envelope that drive rendering
/// (`kind`, `plain`, `latex`), plus the originating input and a display hint.
/// Identity is a stable UUID (SWIFTUI-RULES §3.4: never identify by instance).
struct MathResult: Identifiable {
    let id = UUID()

    /// The input that produced this (a hand-authored snippet label, or the Sage
    /// source for real envelope rows). Shown as the row's monospaced caption.
    let source: String

    /// The envelope `kind` (integer/rational/matrix/symbolic/…), shown as a chip.
    let kind: String

    /// The LaTeX to render — the envelope's `latex` field, or a raw test snippet.
    let latex: String

    /// The envelope's `plain` text fallback, shown beneath the math (and the only
    /// thing shown when `latex` is nil/empty).
    let plain: String

    /// Block (hero, centered) vs inline (woven into a sentence) rendering.
    let displayStyle: MathDisplayStyle

    /// Where this row came from — labels it in the UI and lets us prove we render
    /// both the spec's hand-authored snippets and real worker output.
    let provenance: Provenance

    enum Provenance: String {
        case spec = "Spec test LaTeX"
        case worker = "Real worker envelope"
        case inline = "Inline math"
        case invalid = "Invalid LaTeX (fallback)"
        case bulk = "Scrolling bulk"
    }
}
