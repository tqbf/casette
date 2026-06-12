import SwiftUI

/// The single renderer the whole app uses. Swap this one line to change
/// engines — the rest of the app is untouched (the V0.4 deliverable; the
/// LaTeXSwiftUI→SwiftMath swap was exactly this line).
@MainActor let activeMathRenderer = SwiftMathRenderer()

/// A thin SwiftUI view that renders one LaTeX string through
/// `activeMathRenderer`. This is what cards actually place on screen; they
/// never see the concrete engine.
struct MathView: View {
    let latex: String
    var displayStyle: MathDisplayStyle = .block

    var body: some View {
        activeMathRenderer.render(latex, displayStyle: displayStyle)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        MathView(latex: "\\frac{8}{15}")
        MathView(latex: "x^{8} + 8 \\, x^{7} + 28 \\, x^{6} + 56 \\, x^{5} + 70 \\, x^{4}")
        MathView(latex: "\\left(\\begin{array}{rr}\n1 & 2 \\\\\n3 & 4\n\\end{array}\\right)")
        MathView(latex: "\\frac{8}{15}", displayStyle: .inline)
        MathView(latex: "\\oops{broken")
    }
    .padding()
    .frame(width: 480)
}
