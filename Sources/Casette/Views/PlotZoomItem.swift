import AppKit

/// What the plot zoom sheet shows: the already-decoded full-resolution image
/// plus the row context for its header. Identity is the artifact path —
/// unique per plot (the worker's monotonic `plot-NNNNN` counter).
struct PlotZoomItem: Identifiable {
    /// The row's input echo, for the sheet header.
    let title: String
    /// The PNG's on-disk path (identity; also drives Reveal in Finder).
    let path: String
    /// The decoded image, handed over by the inline well — the sheet never
    /// re-loads from disk.
    let image: NSImage

    var id: String { path }
}
