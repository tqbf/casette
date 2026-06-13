import AppKit
import Foundation
import Testing
@testable import Casette

/// The V1.7 plot pipeline against REAL Sage, through the same seam the UI
/// uses (controller → envelope mapping → renditions → image cache): basic
/// `plot`, `implicit_plot`, a multi-plot eval, and a failing plot call.
/// Skipped (not failed) without Sage.
@MainActor
@Suite(
    "Plot integration (real Sage)",
    .serialized,
    .enabled(if: SageTestEnvironment.available))
struct PlotIntegrationTests {
    @Test("plot journey: basic plot, implicit_plot, multi-plot, failing plot", .timeLimit(.minutes(5)))
    func plotJourney() async {
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        await controller.connect()

        // Variables first (the worker predefines none — PROBLEMS.md V0.5).
        _ = await controller.evaluate("x, y = var('x y')")

        // Basic plot: kind plot, a present PNG artifact, a real file on disk
        // that decode-verifies into an image (the exit criterion).
        let sine = await controller.evaluate("plot(sin(x), (x, -pi, pi))")
        #expect(sine.status == .ok)
        #expect(sine.result?.kind == "plot")
        let sineRenditions = sine.result?.plotRenditions ?? []
        #expect(sineRenditions.count == 1)
        if let artifact = sineRenditions.first?.artifact, let path = artifact.path {
            #expect(artifact.status == .present)
            #expect((artifact.bytes ?? 0) > 0)
            #expect(FileManager.default.fileExists(atPath: path))
            let image = await PlotImageCache().image(forPath: path)
            #expect(image != nil)
            #expect((image?.size.width ?? 0) > 100)
        } else {
            Issue.record("basic plot should yield a saved PNG artifact")
        }
        // The SVG sibling is in the model (for the Inspector) but is never a
        // rendition.
        #expect(sine.result?.artifacts.contains { $0.format == "svg" && $0.status == .present } == true)

        // implicit_plot works (the second exit criterion).
        let circle = await controller.evaluate(
            "implicit_plot(x^2 + y^2 == 1, (x, -2, 2), (y, -2, 2))")
        #expect(circle.status == .ok)
        #expect(circle.result?.kind == "plot")
        let circlePNG = circle.result?.plotRenditions.first
        #expect(circlePNG?.artifact.status == .present)
        if let path = circlePNG?.path {
            #expect(FileManager.default.fileExists(atPath: path))
        }

        // A multi-plot eval (two .show()n plots) yields one rendition per
        // plot, at distinct paths, all present.
        let multi = await controller.evaluate(
            "p1 = plot(sin(x)); p1.show(); p2 = plot(cos(x)); p2.show()")
        #expect(multi.status == .ok)
        #expect(multi.result?.kind == "plot")
        let multiRenditions = multi.result?.plotRenditions ?? []
        #expect(multiRenditions.count == 2)
        #expect(Set(multiRenditions.compactMap(\.path)).count == 2)
        #expect(multiRenditions.allSatisfy { $0.artifact.status == .present })

        // A failing plot call is a NORMAL error envelope — readable type and
        // message, no artifacts (the "plot errors readable" criterion).
        let failing = await controller.evaluate("plot(sin(x), (x, 0, 'notanumber'))")
        #expect(failing.status == .error)
        #expect(failing.result?.error?.type.isEmpty == false)
        #expect(failing.result?.artifacts.isEmpty == true)

        // The worker survived the failed plot; the wire is intact.
        let two = await controller.evaluate("1 + 1")
        #expect(two.result?.plain == "2")

        await controller.shutdown()
    }

    @Test("implicit_plot works OUT OF THE BOX — the boot prelude predefines y", .timeLimit(.minutes(5)))
    func implicitPlotWorksWithoutDeclaringVariables() async {
        // The V1.7 live gate failed here: through the real app path (the
        // ShellModel, whose boot prelude is the ONLY variable setup) an
        // upstream-docs-verbatim implicit_plot NameError'd on `y`. The boot
        // prelude covers `x` and `y` — this must just work, with a
        // present, decodable PNG.
        let controller = SessionController(transportFactory: SageTestEnvironment.factory)
        let model = ShellModel()
        model.connectKernel(controller)

        model.draft = "implicit_plot(x^2 + y^2 == 1, (x, -2, 2), (y, -2, 2))"
        model.submitDraft()
        #expect(await eventually(timeout: .seconds(120)) { @MainActor in
            model.rows.first?.status == .ok
        })
        #expect(model.rows[0].result?.error == nil)
        #expect(model.rows[0].result?.kind == "plot")
        let rendition = model.rows[0].result?.plotRenditions.first
        #expect(rendition?.artifact.status == .present)
        if let path = rendition?.path {
            #expect(FileManager.default.fileExists(atPath: path))
            let image = await PlotImageCache().image(forPath: path)
            #expect(image != nil)
        } else {
            Issue.record("implicit_plot should yield a saved PNG artifact")
        }

        await controller.shutdown()
    }
}
