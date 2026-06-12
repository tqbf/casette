import AppKit
import Foundation
import Testing
@testable import Casette

/// The V1.7 plot model: artifact→card mapping (incl. multi-plot and the
/// missing-PNG selection logic), the additive per-format save-error field,
/// and the decode-verifying image cache.
@Suite("Plot rendering model (V1.7)")
struct PlotRenderingTests {
    @Test("a multi-plot envelope maps every SVG+PNG pair; renditions are the PNGs in call order")
    func multiPlotMapping() {
        let response: [String: Any] = [
            "ok": true, "kind": "plot", "plain": "2 graphics", "value": true,
            "artifacts": [
                ["type": "image", "format": "svg", "path": "/tmp/s/plot-00001.svg", "bytes": 100],
                ["type": "image", "format": "png", "path": "/tmp/s/plot-00001.png", "bytes": 200],
                ["type": "image", "format": "svg", "path": "/tmp/s/plot-00002.svg", "bytes": 110],
                ["type": "image", "format": "png", "path": "/tmp/s/plot-00002.png", "bytes": 210],
            ],
        ]
        let envelope = PersistedEnvelope(workerResponse: response)
        #expect(envelope.artifacts.count == 4)

        let renditions = envelope.plotRenditions
        #expect(renditions.count == 2)
        #expect(renditions[0].path == "/tmp/s/plot-00001.png")
        #expect(renditions[1].path == "/tmp/s/plot-00002.png")
        // SVG is NEVER a rendition (PROBLEMS.md V0.5 — NSImage corrupts it).
        #expect(renditions.allSatisfy { $0.artifact.format == "png" })
        // Stable, distinct identities for ForEach.
        #expect(Set(renditions.map(\.id)).count == 2)
    }

    @Test("a per-format save failure maps its structured error; a nil path is missing")
    func saveErrorMapping() {
        let response: [String: Any] = [
            "ok": true, "kind": "plot", "plain": "Graphics object", "value": true,
            "artifacts": [
                ["type": "image", "format": "svg", "path": "/tmp/s/plot-00001.svg", "bytes": 100],
                ["type": "image", "format": "png", "path": NSNull(),
                 "error": "OSError: [Errno 28] No space left on device"],
            ],
        ]
        let envelope = PersistedEnvelope(workerResponse: response)
        let png = envelope.artifacts[1]
        #expect(png.path == nil)
        #expect(png.status == .missing)
        #expect(png.error == "OSError: [Errno 28] No space left on device")
        // The failed PNG still yields a rendition — that's what carries the
        // honest "couldn't be saved" state onto the card.
        #expect(envelope.plotRenditions.count == 1)
        #expect(envelope.plotRenditions[0].saveError?.contains("No space left") == true)
        #expect(envelope.plotRenditions[0].path == nil)
    }

    @Test("missing-PNG selection: SVG-only artifacts yield no rendition (the card's one honest missing state)")
    func svgOnlyArtifacts() {
        let envelope = PersistedEnvelope(
            kind: "plot", plain: "Graphics object",
            artifacts: [
                PersistedArtifact(
                    type: "image", format: "svg",
                    path: "/tmp/s/plot-00001.svg", bytes: 100, status: .missing)
            ])
        #expect(envelope.plotRenditions.isEmpty)
        #expect(!envelope.artifacts.isEmpty)
    }

    @Test("a non-plot envelope has no renditions")
    func nonPlotEnvelope() {
        let envelope = PersistedEnvelope(kind: "integer", plain: "4")
        #expect(envelope.plotRenditions.isEmpty)
    }

    @Test("the additive artifact error field is omitted when nil and round-trips when set (schema v1)")
    func artifactErrorCodable() throws {
        let clean = PersistedArtifact(
            type: "image", format: "png", path: "/tmp/p.png", bytes: 10, status: .missing)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let cleanJSON = String(decoding: try encoder.encode(clean), as: UTF8.self)
        // Omitted-when-nil: a pre-V1.7 reader sees exactly the old shape.
        #expect(!cleanJSON.contains("error"))

        let failed = PersistedArtifact(
            type: "image", format: "png", path: nil, status: .missing,
            error: "OSError: disk full")
        let decoded = try JSONDecoder().decode(
            PersistedArtifact.self, from: try encoder.encode(failed))
        #expect(decoded == failed)
        #expect(decoded.error == "OSError: disk full")

        // A pre-V1.7 file (no error key) still decodes.
        let legacy = try JSONDecoder().decode(
            PersistedArtifact.self, from: Data(cleanJSON.utf8))
        #expect(legacy.error == nil)
    }

    // MARK: - The well's fitting math (V1.7 fix round)
    //
    // `PlotImageWell` sizes its image EXPLICITLY from this pure helper —
    // never via `.scaledToFit()` intrinsic-size negotiation (PROBLEMS.md
    // "AttributeGraph spin").

    @Test("fitting preserves aspect ratio when capped by height")
    @MainActor
    func fittingPreservesAspect() {
        // 1280×960 (4:3) into a 600pt row, 280pt cap → height-capped.
        let size = PlotImageWell.fittedDisplaySize(
            imageSize: CGSize(width: 1280, height: 960),
            availableWidth: 600, maxHeight: 280)
        #expect(size.height == 280)
        #expect(size.width == 373)  // round(1280 * 280/960) = round(373.3)
        #expect(abs(size.width / size.height - 1280.0 / 960.0) < 0.01)
    }

    @Test("fitting never upscales a small image")
    @MainActor
    func fittingNeverUpscales() {
        let size = PlotImageWell.fittedDisplaySize(
            imageSize: CGSize(width: 120, height: 90),
            availableWidth: 600, maxHeight: 280)
        #expect(size == CGSize(width: 120, height: 90))
    }

    @Test("fitting caps by the available width when the row is narrower than the height-capped image")
    @MainActor
    func fittingCapsByWidth() {
        // Height cap alone would give 373pt wide; a 300pt row wins.
        let size = PlotImageWell.fittedDisplaySize(
            imageSize: CGSize(width: 1280, height: 960),
            availableWidth: 300, maxHeight: 280)
        #expect(size.width == 300)
        #expect(size.height == 225)  // round(960 * 300/1280)
        #expect(size.width <= 300 && size.height <= 280)
    }

    @Test("an unmeasured width (first layout pass) caps by height only; degenerate sizes are zero")
    @MainActor
    func fittingHandlesUnknownWidthAndDegenerateInput() {
        let unmeasured = PlotImageWell.fittedDisplaySize(
            imageSize: CGSize(width: 1280, height: 960),
            availableWidth: nil, maxHeight: 280)
        #expect(unmeasured == CGSize(width: 373, height: 280))
        #expect(PlotImageWell.fittedDisplaySize(
            imageSize: .zero, availableWidth: 600, maxHeight: 280) == .zero)
    }
}

/// Artifacts flow into SESSION ROWS through the live eval path (the spec's
/// "store artifact metadata in session rows" — already modeled; this pins
/// the flow), and the card's rerun affordance is the History rerun.
@MainActor
@Suite("Plot rows (fake transport)")
struct PlotRowFlowTests {
    private static func fastConfig() -> SessionController.Configuration {
        var configuration = SessionController.Configuration()
        configuration.pollInterval = .milliseconds(5)
        configuration.readyTimeout = .seconds(2)
        configuration.metadataTimeout = .seconds(2)
        return configuration
    }

    @Test("a multi-plot eval's artifact entries land on the session row, renditions intact")
    func multiPlotArtifactsReachTheRow() async {
        let model = ShellModel()
        let fake = FakeKernelTransport()
        fake.respondToSend = { request in
            guard let id = request["id"] as? String else { return [] }
            if request["op"] as? String == "symbols" {
                return [WireFixtures.symbolsResponse(id: id, entries: [])]
            }
            return [[
                "id": id, "ok": true, "value": true, "kind": "plot",
                "plain": "Graphics object consisting of 1 graphics primitive",
                "actions": ["show", "save_png", "save_svg"],
                "artifacts": [
                    ["type": "image", "format": "svg", "path": "/tmp/s/plot-00001.svg", "bytes": 100],
                    ["type": "image", "format": "png", "path": "/tmp/s/plot-00001.png", "bytes": 200],
                    ["type": "image", "format": "svg", "path": "/tmp/s/plot-00002.svg", "bytes": 110],
                    ["type": "image", "format": "png", "path": "/tmp/s/plot-00002.png", "bytes": 210],
                ],
                "truncated": false, "stdout": "", "stderr": "",
            ]]
        }
        model.connectKernel(SessionController(configuration: Self.fastConfig()) { fake })

        model.draft = "p1.show(); p2.show()"
        model.submitDraft()
        #expect(await eventually { @MainActor in model.rows.first?.status == .ok })

        let row = model.rows[0]
        #expect(row.cardKind == .plot)
        #expect(row.result?.artifacts.count == 4)
        let renditions = row.result?.plotRenditions ?? []
        #expect(renditions.count == 2)
        // The fake's paths don't exist → liveness resolved to missing at the
        // mapping boundary (the card will show the honest state).
        #expect(renditions.allSatisfy { $0.artifact.status == .missing })

        // The card's rerun affordance: a FRESH row through the normal path.
        model.rerun(rowID: row.id)
        #expect(await eventually { @MainActor in
            model.rows.count == 2 && model.rows[1].status == .ok
        })
        #expect(model.rows[1].input == "p1.show(); p2.show()")
        #expect(model.rows[1].id != row.id)
    }
}

/// The image cache: decode-verified loading (the V0.5 lesson — a non-nil
/// image must be a real decoded raster), miss behavior, and memoization.
@MainActor
@Suite("Plot image cache (V1.7)")
struct PlotImageCacheTests {
    /// A real 1×1 red PNG (verified bytes), so the test needs no fixture file.
    private static let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func temporaryFile(named name: String, contents: Data) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "casette-plot-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try contents.write(to: url)
        return url.path
    }

    @Test("decodes a real PNG, with pixel-sized points, and memoizes it")
    func decodesAndCaches() async throws {
        let path = try temporaryFile(named: "plot-00001.png", contents: Self.onePixelPNG)
        let cache = PlotImageCache()

        #expect(cache.cachedImage(forPath: path) == nil)
        let image = await cache.image(forPath: path)
        #expect(image != nil)
        #expect(image?.size == NSSize(width: 1, height: 1))
        // Memoized: the synchronous accessor now hits, with the SAME instance.
        #expect(cache.cachedImage(forPath: path) === image)
        let again = await cache.image(forPath: path)
        #expect(again === image)
    }

    @Test("a gone file and a non-image file both return nil — never a 'loaded' lie")
    func missingAndGarbage() async throws {
        let cache = PlotImageCache()
        let gone = await cache.image(forPath: "/tmp/casette-plot-tests-nonexistent/plot.png")
        #expect(gone == nil)

        let garbagePath = try temporaryFile(
            named: "not-an-image.png", contents: Data("this is not a PNG".utf8))
        let garbage = await cache.image(forPath: garbagePath)
        #expect(garbage == nil)
        #expect(cache.cachedImage(forPath: garbagePath) == nil)  // failures aren't cached
    }
}
