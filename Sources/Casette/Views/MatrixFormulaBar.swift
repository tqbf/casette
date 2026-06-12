import FriendlyCompiler
import SwiftUI

struct MatrixFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: MatrixFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: formula.kind.title)

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: payloadTitle,
                    prompt: payloadPrompt,
                    text: binding(
                        get: { $0.payload },
                        set: { $0.payload = $1 }))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    /// The visible token label. `matrix`/`vector` are constructors, so their
    /// token names the entries; the method bars (det, rref, …) operate on a
    /// matrix, so their token is labelled "matrix".
    private var payloadTitle: String {
        switch formula.kind {
        case .matrix, .vector: return "entries"
        default: return "matrix"
        }
    }

    private var payloadPrompt: String {
        switch formula.kind {
        case .vector: return "[1,2,3]"
        default: return "[1,2; 3,4]"
        }
    }

    private func binding(
        get: @escaping (MatrixFormulaIR) -> String,
        set: @escaping (inout MatrixFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.matrixFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.matrixFormula ?? formula
            set(&next, value)
            model.updateFormula(.matrixOp(next))
        }
    }
}
