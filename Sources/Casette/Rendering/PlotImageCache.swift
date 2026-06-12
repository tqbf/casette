import AppKit
import ImageIO

/// Loads plot PNG artifacts into `NSImage`s with the file read + decode OFF
/// the main thread, memoized in a bounded cache — so LazyVStack recycling and
/// hover/selection re-renders never re-read or re-decode a file, and
/// scrolling the tape stays smooth (the `MathRenderCache` precedent,
/// PROBLEMS.md V1.5: what hitches a tape is the *repeated* work).
///
/// Keyed by path. Artifact paths are never rewritten in place — the worker's
/// `plot-NNNNN` counter is monotonic and a rerun produces a NEW row with new
/// paths — so a cached image can go unused, never stale.
@MainActor
final class PlotImageCache {
    static let shared = PlotImageCache()

    private var images: [String: NSImage] = [:]
    /// Bounded with a whole-cache reset on overflow (SWIFTUI-RULES §3.2 — a
    /// self-patching cache is its own bug class). 64 decoded ~640×480 plots
    /// is roughly 75 MB worst case, and a reset just costs a re-decode.
    private let capacity = 64

    /// The already-decoded image, if cached — synchronous, so a recycled row
    /// can re-show its plot without a placeholder frame.
    func cachedImage(forPath path: String) -> NSImage? {
        images[path]
    }

    /// Loads and decodes the image file at `path`, off the main thread,
    /// caching the result. Returns nil when the file is gone or doesn't
    /// decode — and a non-nil return IS a decoded raster (the V0.5 lesson:
    /// never trust a merely *loaded* image; `CGImageSource` either yields a
    /// real bitmap or nil, there is no "loads fine, renders wrong" PNG path).
    func image(forPath path: String) async -> NSImage? {
        if let cached = images[path] { return cached }
        guard let cgImage = await Self.decode(path: path) else { return nil }
        // Point size = pixel size: predictable layout math, and the zoom
        // sheet's "natural size" is the full-resolution raster.
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height))
        if images.count >= capacity { images.removeAll() }
        images[path] = image
        return image
    }

    /// Decodes the file into a raster `CGImage`. `nonisolated` + async runs
    /// on the global executor (never the main actor), and the
    /// `ShouldCacheImmediately` hint forces the actual PNG decode HERE — not
    /// lazily at first draw on the main thread.
    private nonisolated static func decode(path: String) async -> CGImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
