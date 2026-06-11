import SwiftUI
import AppKit

/// Which artifact format the viewer is currently rendering for a row.
enum PlotFormat: String, CaseIterable, Identifiable {
    case svg = "SVG"
    case png = "PNG"
    var id: String { rawValue }
}

/// Renders a plot artifact file (SVG or PNG) via `NSImage`.
///
/// V0.5 finding (macOS 14+): `NSImage(contentsOf:)` loads Sage/matplotlib SVG
/// natively through the system `_NSSVGImageRep` (vector, crisp at any zoom) and
/// PNG through `NSBitmapImageRep`. We render the loaded `NSImage` with
/// `.resizable().scaledToFit()` so SVG stays sharp when scaled up. If a file
/// fails to load (e.g. a renderer that lacks SVG support on an older OS), we show
/// a readable placeholder rather than a blank — that itself is the signal to use
/// the PNG fallback.
struct PlotImageView: View {
    let url: URL?
    let format: PlotFormat

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .accessibilityLabel("Rendered \(format.rawValue) plot")
            } else {
                unavailable
            }
        }
    }

    private var loadedImage: NSImage? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private var unavailable: some View {
        ContentUnavailableView {
            Label("Couldn't render \(format.rawValue)", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text(url == nil
                 ? "No \(format.rawValue) file for this plot."
                 : "NSImage couldn't decode this \(format.rawValue). Try the PNG fallback.")
        }
        .frame(minHeight: 160)
    }
}
