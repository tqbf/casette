import Foundation

/// One artifact entry as the worker reports it in the envelope's `artifacts`
/// array (V0.5 contract; see plans/WORKER-PROTOCOL.md):
///
///     {"type":"image","format":"svg","path":"…/plot-00001.svg","bytes":20587}
///
/// A failed save is reported with `path == nil` and a non-nil `error`.
struct ArtifactEntry: Decodable, Hashable {
    var type: String
    var format: String?
    var path: String?
    var bytes: Int?
    var error: String?
}

/// A plot the worker produced — the SVG and its PNG fallback grouped by their
/// shared `plot-NNNNN` stem. The viewer renders one of these per row.
struct PlotArtifact: Identifiable, Hashable {
    let id: String          // the stem, e.g. "plot-00001"
    let title: String       // a human label inferred from order / source
    var svgURL: URL?
    var pngURL: URL?
    var svgBytes: Int?
    var pngBytes: Int?

    /// True if the SVG file is present on disk.
    var hasSVG: Bool { svgURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    /// True if the PNG file is present on disk.
    var hasPNG: Bool { pngURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
}

/// Loads the artifacts a Casette Sage worker saved into a session directory.
///
/// The directory layout is the V0.5 contract:
/// `/tmp/sagecalc/session-<pid>-<rand>/plot-NNNNN.{svg,png}`. The loader simply
/// scans for `plot-*.svg` / `plot-*.png` files and pairs them by stem — exactly
/// the files the harness asserts exist. (A real app would instead receive the
/// `artifacts` arrays inline over the protocol; this proof reads them off disk to
/// keep the viewer independent of a live worker.)
enum PlotLoader {
    /// Human-readable titles for the known harness corpus, by order. Purely
    /// cosmetic — the proof works on whatever files are present.
    private static let knownTitles: [String] = [
        "plot(sin(x), (x, -π, π))",
        "implicit_plot(x² + y² == 1)",
        "parametric_plot((cos t, sin t))",
        "multi-plot eval · sin(x)",
        "multi-plot eval · cos(x)",
        "plot(sin(1·x))",
        "plot(sin(2·x))",
        "plot(sin(3·x))",
    ]

    static func load(from directory: URL) -> [PlotArtifact] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        // Group by stem (plot-NNNNN), collecting svg/png members.
        var byStem: [String: (svg: URL?, png: URL?, svgBytes: Int?, pngBytes: Int?)] = [:]
        for name in names {
            let url = directory.appendingPathComponent(name)
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension.lowercased()
            guard stem.hasPrefix("plot-"), ext == "svg" || ext == "png" else { continue }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
            var entry = byStem[stem] ?? (nil, nil, nil, nil)
            if ext == "svg" { entry.svg = url; entry.svgBytes = size }
            else { entry.png = url; entry.pngBytes = size }
            byStem[stem] = entry
        }

        let sortedStems = byStem.keys.sorted()
        return sortedStems.enumerated().map { index, stem in
            let e = byStem[stem]!
            let title = index < knownTitles.count ? knownTitles[index] : stem
            return PlotArtifact(
                id: stem,
                title: title,
                svgURL: e.svg,
                pngURL: e.png,
                svgBytes: e.svgBytes,
                pngBytes: e.pngBytes
            )
        }
    }

    /// Find the newest `/tmp/sagecalc/session-*` directory, so the viewer can
    /// auto-discover the harness's `--keep` output without a hardcoded path.
    static func newestSessionDirectory(root: URL = URL(fileURLWithPath: "/tmp/sagecalc")) -> URL? {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
        let dirs = names.filter { $0.hasPrefix("session-") }.map { root.appendingPathComponent($0) }
        func mtime(_ url: URL) -> Date {
            ((try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date) ?? .distantPast
        }
        return dirs.max { mtime($0) < mtime($1) }
    }
}
