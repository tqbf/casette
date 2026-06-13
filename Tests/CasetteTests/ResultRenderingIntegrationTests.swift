import Foundation
import Testing
@testable import Casette

/// V1.5 against REAL Sage: the envelope `latex` the worker emits for the
/// card kinds flows through the lifted normalizer and parses in the real
/// engine (`MathContent.choose` returns `.math`), stdout is captured, and a
/// genuinely huge result arrives truncated WITH its honest sizes. Skipped
/// (not failed) without Sage.
@MainActor
@Suite(
    "Result rendering integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct ResultRenderingIntegrationTests {
    @Test("matrix / symbolic / solve-list latex is renderable end-to-end", .timeLimit(.minutes(5)))
    func renderableLatexForCardKinds() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        // Matrix: Sage emits the `array` form; the normalizer must turn it
        // into something SwiftMath parses (the V0.4 load-bearing rewrite).
        let matrix = await controller.evaluate("matrix([[1,2],[3,4]])")
        #expect(matrix.result?.kind == "matrix")
        if let latex = matrix.result?.latex {
            #expect(latex.contains("\\begin{array}"))  // the raw Sage shape
            #expect(MathContent.choose(latex: latex) == .math(latex: latex))
            #expect(MathRenderCache.entry(for: latex).normalized.contains("\\begin{pmatrix}"))
        } else {
            Issue.record("matrix envelope carried no latex")
        }

        // Symbolic with braced scripts (the LaTeXSwiftUI killer): x^{8}, \, …
        _ = await controller.evaluate("x = var('x')")
        let poly = await controller.evaluate("expand((x+1)^8)")
        #expect(poly.result?.kind == "symbolic")
        if let latex = poly.result?.latex {
            #expect(latex.contains("x^{8}"))
            #expect(MathContent.choose(latex: latex) == .math(latex: latex))
        } else {
            Issue.record("symbolic envelope carried no latex")
        }

        // A solve list (Sequence → kind list) renders too.
        let solved = await controller.evaluate("solve(x^2 + 5*x + 6 == 0, x)")
        #expect(solved.result?.kind == "list")
        if let latex = solved.result?.latex {
            #expect(MathContent.choose(latex: latex) == .math(latex: latex))
        } else {
            Issue.record("solve envelope carried no latex")
        }

        // Basis-vector lists from matrix space/kernel actions are Sage
        // `Sequence_generic` values, but their elements are typed vectors. The
        // worker should render that type as a labeled, safe set of column
        // vectors, not Sage's default tuple-list LaTeX.
        let kernelBasis = await controller.evaluate(
            "matrix([[1,2,3],[2,4,6],[1,1,1]]).right_kernel().basis()")
        #expect(kernelBasis.result?.kind == "list")
        #expect(kernelBasis.result?.plain.contains("(1, -2, 1)") == true)
        if let latex = kernelBasis.result?.latex {
            #expect(latex.contains("\\mathcal{B} ="))
            #expect(latex.contains("\\begin{pmatrix}"))
            #expect(MathContent.choose(latex: latex) == .math(latex: latex))
        } else {
            Issue.record("basis envelope carried no latex")
        }

        let svd = await controller.evaluate(
            "__casette_svd_labeled(matrix(RDF, [[1,2],[3,4]]).SVD())")
        #expect(svd.result?.kind == "list")
        #expect(svd.result?.plain.contains("U =") == true)
        #expect(svd.result?.plain.contains("S =") == true)
        #expect(svd.result?.plain.contains("V =") == true)
        if let latex = svd.result?.latex {
            #expect(latex.contains("U ="))
            #expect(latex.contains("S ="))
            #expect(latex.contains("V ="))
            #expect(MathContent.choose(latex: latex) == .math(latex: latex))
        } else {
            Issue.record("SVD envelope carried no latex")
        }

        // A scalar-exact card: rational with the ≈ secondary line.
        let rational = await controller.evaluate("1/3 + 1/5")
        #expect(rational.result?.exact == true)
        #expect(rational.result?.approx == "0.5333333333")
        if let latex = rational.result?.latex {
            #expect(MathContent.choose(latex: latex) == .math(latex: latex))
        }

        await controller.shutdown()
    }

    @Test("calculator variables are predefined at boot and after restart", .timeLimit(.minutes(5)))
    func bootPreludeMatchesTheRealREPL() async {
        // Through the ShellModel seam, where the boot prelude lives: a
        // raw-Sage bypass over `x` (no friendly var('V') preludes) must work
        // straight after boot, exactly as in the real `sage` REPL — plus
        // the calculator-variables deviation (see
        // plans/FRIENDLY-COMPILER.md).
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "expand((x+1)^8)"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        #expect(model.rows[0].result?.kind == "symbolic")
        #expect(model.rows[0].result?.error == nil)
        #expect(model.rows[0].result?.plain.contains("x^8") == true)
        #expect(model.rows[0].result?.latex?.contains("x^{8}") == true)
        // The sidebar honestly shows ALL the predefined calculator
        // variables (worker-sorted by name).
        #expect(await eventually { @MainActor in
            model.symbols.entries.map(\.name) == ShellModel.bootVariableNames.sorted()
        })

        // Restart resets the namespace; the prelude must be re-applied.
        model.restartKernel()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.symbols.entries.map(\.name) == ShellModel.bootVariableNames.sorted()
        })
        model.draft = "expand((x+1)^2)"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.count == 2 && model.rows[1].status == .ok
        })
        #expect(model.rows[1].result?.plain == "x^2 + 2*x + 1")

        await controller.shutdown()
    }

    @Test("stdout is captured and a huge result is honestly truncated", .timeLimit(.minutes(5)))
    func stdoutAndTruncation() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        // print() → a statement card with stdout (the text/stdout kind).
        let printed = await controller.evaluate("print(\"hello\")")
        #expect(printed.status == .ok)
        #expect(printed.result?.stdout == "hello\n")
        if let result = printed.result {
            #expect(ResultCardKind(okEnvelope: result) == .statement)
        }

        // factorial(10^5) (~456 KB of digits) arrives capped, with the
        // truncation sizes for the "showing N of M characters" note.
        let huge = await controller.evaluate("factorial(10^5)")
        #expect(huge.status == .ok)
        #expect(huge.result?.truncated == true)
        #expect((huge.result?.truncation?.plainLength ?? 0) > 100_000)
        #expect(huge.result?.truncation?.plainCap == 8192)
        #expect(huge.result?.truncationNote?.contains("of") == true)

        await controller.shutdown()
    }
}
