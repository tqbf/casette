import FriendlyCompiler
import SwiftUI

struct LimitFormulaBar: View {
    @Bindable var model: ShellModel
    let formula: LimitFormulaIR

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            FormulaFunctionChip(title: "LIMIT")

            HStack(alignment: .center, spacing: 6) {
                FormulaTokenField(
                    title: "expr",
                    prompt: "sin(x)/x",
                    text: binding(
                        get: { $0.expression },
                        set: { $0.expression = $1 }))

                FormulaTokenField(
                    title: "var",
                    prompt: "x",
                    text: binding(
                        get: { $0.variable },
                        set: { $0.variable = $1 }))

                Text("→")
                    .font(Theme.Fonts.formulaPunctuation)
                    .foregroundStyle(.tertiary)

                FormulaTokenField(
                    title: "point",
                    prompt: "0",
                    text: binding(
                        get: { $0.point },
                        set: { $0.point = $1 }))

                directionControl
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private var directionControl: some View {
        Picker("direction", selection: directionBinding) {
            Text("both").tag(LimitFormulaIR.Direction.both)
            Text("left").tag(LimitFormulaIR.Direction.left)
            Text("right").tag(LimitFormulaIR.Direction.right)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .font(Theme.Fonts.formulaTokenValue)
        .fixedSize()
        .accessibilityLabel("direction")
    }

    private var directionBinding: Binding<LimitFormulaIR.Direction> {
        Binding {
            model.limitFormula?.direction ?? formula.direction
        } set: { value in
            var next = model.limitFormula ?? formula
            next.direction = value
            model.updateFormula(.limit(next))
        }
    }

    private func binding(
        get: @escaping (LimitFormulaIR) -> String,
        set: @escaping (inout LimitFormulaIR, String) -> Void
    ) -> Binding<String> {
        Binding {
            guard let current = model.limitFormula else { return get(formula) }
            return get(current)
        } set: { value in
            var next = model.limitFormula ?? formula
            set(&next, value)
            model.updateFormula(.limit(next))
        }
    }
}
