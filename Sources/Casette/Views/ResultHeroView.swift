import SwiftUI

/// The hero of a value-bearing result card: the envelope's `latex` rendered
/// as math (SwiftMath behind the `MathRenderer` abstraction), falling back to
/// `plain` monospaced when LaTeX is missing or unparseable (the V0.4
/// graceful-degradation contract — malformed LaTeX never crashes, never
/// vanishes). Below it: the V0.8 `≈ approx` secondary line and the honest
/// truncation note.
struct ResultHeroView: View {
    let result: PersistedEnvelope

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch MathContent.choose(latex: result.latex) {
            case .math(let latex):
                // Wide math (long polynomials, big matrices) scrolls
                // horizontally instead of overflowing the row.
                ScrollView(.horizontal) {
                    MathView(latex: heroLatex(latex), displayStyle: .block)
                }
                .scrollIndicators(.automatic)
                // The typeset math is an NSView — silent to VoiceOver; the
                // envelope's plain text is the honest spoken value.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(heroPlain)
            case .plain:
                Text(heroPlain)
                    .font(Theme.Fonts.resultPrimary)
                    .textSelection(.enabled)
            }
            if let approx = result.approx {
                Text("≈ \(approx)")
                    .font(Theme.Fonts.resultSecondary)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let note = result.truncationNote {
                Label(note, systemImage: "scissors")
                    .font(Theme.Fonts.truncationNote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// V0.8 `primary_is_approx`: the primary value already IS an
    /// approximation (float primary or force-numeric) — say so on the value.
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
