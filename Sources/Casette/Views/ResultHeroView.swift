import SwiftUI

/// The hero of a value-bearing result card: the envelope's `latex` rendered
/// as math (SwiftMath behind the `MathRenderer` abstraction), falling back to
/// `plain` monospaced when LaTeX is missing or unparseable (the V0.4
/// graceful-degradation contract — malformed LaTeX never crashes, never
/// vanishes). Below it: the V0.8 `≈ approx` secondary line (copyable — the
/// approximation is right there, zero clicks), the force-numeric
/// `= … exactly` line (the preserved `exactValue` — numeric display never
/// loses the exact form), and the honest truncation note.
struct ResultHeroView: View {
    let result: PersistedEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if result.exactValue != nil {
                // Force-numeric (V0.8): `plain` IS the decimal primary, but
                // `latex` still describes the EXACT form (the worker computes
                // it before re-presenting) — so the hero must be the plain
                // decimal, never the typeset exact value.
                Text("≈ \(result.plain)")
                    .font(Theme.Fonts.resultPrimary)
                    .textSelection(.enabled)
            } else {
                switch MathContent.choose(latex: result.latex) {
                case .math(let latex):
                    // Wide math (long polynomials, big matrices) scrolls
                    // horizontally instead of overflowing the row.
                    ScrollView(.horizontal) {
                        MathView(latex: heroLatex(latex), displayStyle: .block)
                    }
                    .scrollIndicators(.automatic)
                    // The typeset math is an NSView — silent to VoiceOver;
                    // the envelope's plain text is the honest spoken value.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(heroPlain)
                case .plain:
                    Text(heroPlain)
                        .font(Theme.Fonts.resultPrimary)
                        .textSelection(.enabled)
                }
            }
            if let approx = result.approx {
                Text("≈ \(approx)")
                    .font(Theme.Fonts.resultSecondary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .contextMenu {
                        Button("Copy Approximation") { Pasteboard.copy(approx) }
                    }
            }
            if let exactValue = result.exactValue {
                // The value keeps the mono Sage voice; "exactly" is a chrome
                // word at the metadata scale. One line — the full string is
                // in the Inspector and on Copy Exact Value.
                (Text("= \(exactValue)").font(Theme.Fonts.resultSecondary)
                    + Text("  exactly").font(Theme.Fonts.meta))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
                    .help("The exact value, preserved — numeric display never changes what's stored")
                    .contextMenu {
                        Button("Copy Exact Value") { Pasteboard.copy(exactValue) }
                    }
            }
            if let note = result.truncationNote {
                Label(note, systemImage: "scissors")
                    .font(Theme.Fonts.truncationNote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// V0.8 `primary_is_approx`: the primary value already IS an
    /// approximation (a float primary) — say so on the value.
    private func heroLatex(_ latex: String) -> String {
        result.primaryIsApprox == true ? "\\approx " + latex : latex
    }

    private var heroPlain: String {
        result.primaryIsApprox == true ? "≈ \(result.plain)" : result.plain
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        ResultHeroView(result: PersistedEnvelope(
            kind: "rational", plain: "8/15", latex: "\\frac{8}{15}",
            approx: "0.5333333333"))
        ResultHeroView(result: PersistedEnvelope(
            kind: "real", plain: "0.533333333333333", latex: "0.533333333333333",
            primaryIsApprox: true))
        ResultHeroView(result: PersistedEnvelope(
            kind: "rational", plain: "0.3333333333", latex: "\\frac{1}{3}",
            primaryIsApprox: true, exactValue: "1/3"))
        ResultHeroView(result: PersistedEnvelope(
            kind: "matrix", plain: "[1 2]\n[3 4]",
            latex: "\\left(\\begin{array}{rr}\n1 & 2 \\\\\n3 & 4\n\\end{array}\\right)"))
        ResultHeroView(result: PersistedEnvelope(
            kind: "unknown", plain: "(1,2,3)", latex: "\\badmacro{",
            truncated: true,
            truncation: PersistedTruncation(plainLength: 455_748, plainCap: 8192)))
    }
    .padding()
    .frame(width: 480)
}
