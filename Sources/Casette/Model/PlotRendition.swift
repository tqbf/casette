import Foundation

/// One renderable plot in a result card: a PNG artifact and its position
/// among the result's plots (the worker's call order).
///
/// **PNG is THE rendered format** (PROBLEMS.md V0.5: `NSImage` mis-rasterizes
/// matplotlib SVG — axis labels paint as a black blob — so SVG artifacts stay
/// in the model and the Inspector but are never rendered through `NSImage`).
/// Each plot the worker captures yields one SVG + one PNG entry; selecting
/// the PNGs in order therefore selects exactly the plots, including a
/// multi-plot eval's several `.show()`n graphics.
struct PlotRendition: Identifiable, Equatable {
    /// Position among the result's PNG artifacts (call order).
    let index: Int
    /// The PNG artifact reference (path is nil when that save failed).
    let artifact: PersistedArtifact

    /// Stable within a row: the worker's monotonic `plot-NNNNN` path never
    /// collides; an unsaved plot falls back to its position.
    var id: String { "\(index)|\(artifact.path ?? "unsaved")" }

    /// The on-disk path, when this plot's PNG actually saved.
    var path: String? { artifact.path }

    /// The worker's per-format save error, when the PNG failed to save.
    var saveError: String? { artifact.error }
}

extension PersistedEnvelope {
    /// The plots a result card renders: the PNG artifacts, in worker order.
    /// Empty when the result carries no PNG entries at all (then the card
    /// shows one honest missing state if other artifacts exist).
    var plotRenditions: [PlotRendition] {
        artifacts.filter { $0.format == "png" }.enumerated().map {
            PlotRendition(index: $0.offset, artifact: $0.element)
        }
    }
}
