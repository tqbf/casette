import FriendlyCompiler
import SwiftUI

/// Dispatches the input pane's hint lane to the bar for the draft's formula
/// family. Every bar edits its family IR and funnels the rewrite through
/// `ShellModel.updateFormula(_:)`, so the draft stays the single source of
/// truth (docs/COMPLETION-UI.md).
struct FormulaBarView: View {
    let model: ShellModel
    let formula: FormulaIR

    var body: some View {
        switch formula {
        case let .integral(ir):
            IntegralFormulaBar(model: model, formula: ir)
        case let .unary(ir):
            UnaryFormulaBar(model: model, formula: ir)
        case let .solve(ir):
            SolveFormulaBar(model: model, formula: ir)
        case let .derivative(ir):
            DerivativeFormulaBar(model: model, formula: ir)
        case let .limit(ir):
            LimitFormulaBar(model: model, formula: ir)
        case let .taylor(ir):
            TaylorFormulaBar(model: model, formula: ir)
        case let .seriesRange(ir):
            SeriesRangeFormulaBar(model: model, formula: ir)
        case let .plot(ir):
            PlotFormulaBar(model: model, formula: ir)
        case let .implicitPlot(ir):
            ImplicitPlotFormulaBar(model: model, formula: ir)
        case let .parametricPlot(ir):
            ParametricPlotFormulaBar(model: model, formula: ir)
        case let .matrixOp(ir):
            MatrixFormulaBar(model: model, formula: ir)
        }
    }
}
