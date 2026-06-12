import SwiftUI

/// The plot result card (V1.7, replacing the V1.5 placeholder chrome): every
/// plot the eval produced renders inline from its PNG artifact — a
/// multi-plot eval stacks its images in call order — over the envelope's
/// `plain` caption. Click an image to expand it in a sheet; a missing or
/// failed PNG shows the honest state with a Rerun affordance.
struct PlotCardView: View {
    let result: PersistedEnvelope
    /// The row's input echo, for the zoom sheet's header.
    let title: String
    let canRerun: Bool
    let onRerun: () -> Void

    @State private var zoomed: PlotZoomItem?

    var body: some View {
        let renditions = result.plotRenditions
        VStack(alignment: .leading, spacing: Theme.rowInnerSpacing) {
            ForEach(renditions) { rendition in
                PlotImageWell(
                    rendition: rendition,
                    canRerun: canRerun,
                    onRerun: onRerun,
                    onZoom: { zoomed = $0 },
                    title: title)
            }
            if renditions.isEmpty && !result.artifacts.isEmpty {
                // Artifacts exist but none is a renderable PNG (e.g. only an
                // SVG survived a save failure) — one honest missing state.
                PlotMissingView(saveError: pngSaveError, canRerun: canRerun, onRerun: onRerun)
            }
            Text(result.plain)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .sheet(item: $zoomed) { item in
            PlotZoomView(item: item)
        }
    }

    /// A PNG-entry save error to surface when there's no rendition to carry
    /// it (defensive: a failed PNG save normally still yields an entry).
    private var pngSaveError: String? {
        result.artifacts.first { $0.format == "png" && $0.error != nil }?.error
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        PlotCardView(
            result: PersistedEnvelope(
                kind: "plot",
                plain: "Graphics object consisting of 1 graphics primitive",
                artifacts: [
                    PersistedArtifact(
                        type: "image", format: "svg",
                        path: "/tmp/sagecalc/session-0-preview/plot-00001.svg",
                        bytes: 20587, status: .missing),
                    PersistedArtifact(
                        type: "image", format: "png",
                        path: "/tmp/sagecalc/session-0-preview/plot-00001.png",
                        bytes: 18896, status: .missing),
                ]),
            title: "plot sin(x), x=-pi..pi",
            canRerun: true,
            onRerun: {})
        PlotCardView(
            result: PersistedEnvelope(
                kind: "plot",
                plain: "Graphics object consisting of 1 graphics primitive",
                artifacts: [
                    PersistedArtifact(
                        type: "image", format: "png", path: nil,
                        status: .missing,
                        error: "OSError: [Errno 28] No space left on device"),
                ]),
            title: "plot cos(x), x=-pi..pi",
            canRerun: true,
            onRerun: {})
    }
    .padding()
    .frame(width: 560)
}
