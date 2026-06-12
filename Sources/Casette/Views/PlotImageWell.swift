import SwiftUI
import UniformTypeIdentifiers

/// One inline plot image in a result card. Loads the PNG artifact through
/// `PlotImageCache` (file read + decode off the main thread, memoized), then
/// renders it bounded and aspect-preserving — click to expand, copy/export
/// on the context menu. A PNG that's gone (the normal restored case) or that
/// never saved shows the honest missing state with a Rerun affordance.
struct PlotImageWell: View {
    let rendition: PlotRendition
    let canRerun: Bool
    let onRerun: () -> Void
    /// Click-to-expand: called with the decoded full-resolution image.
    let onZoom: (PlotZoomItem) -> Void
    /// The row's input echo (the zoom sheet's title).
    let title: String

    @State private var image: NSImage?
    @State private var loadFailed = false
    /// The row width available to the image, measured off the well's
    /// full-width container (whose width comes from the PARENT, never from
    /// the image) — so feeding it back into the image's explicit frame can't
    /// oscillate. `nil` until the first layout pass: the fit then caps by
    /// height only, which is already the final answer whenever the row is
    /// wider than the plot (the common case — no visible jump).
    @State private var availableWidth: CGFloat?

    var body: some View {
        Group {
            if let image {
                loadedImage(image)
            } else if rendition.path == nil || loadFailed {
                PlotMissingView(
                    saveError: rendition.saveError,
                    canRerun: canRerun,
                    onRerun: onRerun
                )
            } else {
                loadingPlaceholder
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { availableWidth = $0 }
        .task(id: rendition.id) { await load() }
    }

    /// The displayed size of a plot image: the decoded raster fit into
    /// `availableWidth` × `maxHeight`, aspect-preserving, NEVER upscaled
    /// past its natural size. Pure — unit-tested in `PlotRenderingTests`.
    ///
    /// The result feeds an EXPLICIT `.frame(width:height:)` (below) instead
    /// of `.resizable().scaledToFit()` + max-frames: SwiftUI-negotiated
    /// image sizing inside a tape row participated in the V1.7 live-gate
    /// AttributeGraph spin (PROBLEMS.md "AttributeGraph spin") — an
    /// explicitly sized image proposes nothing and renegotiates nothing.
    static func fittedDisplaySize(
        imageSize: CGSize,
        availableWidth: CGFloat?,
        maxHeight: CGFloat
    ) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        var scale = min(1, maxHeight / imageSize.height)
        if let availableWidth, availableWidth > 0 {
            scale = min(scale, availableWidth / imageSize.width)
        }
        // Whole points keep the layout stable; the clamp guarantees the
        // rounded frame never exceeds its caps by the rounding half-point.
        let width = (imageSize.width * scale).rounded()
        let height = (imageSize.height * scale).rounded()
        return CGSize(
            width: min(width, availableWidth ?? width),
            height: min(height, maxHeight))
    }

    /// The rendered plot: a plain-style button (click = expand; honest to
    /// assistive tech, unlike a tap gesture), capped at `plotMaxHeight` and
    /// never upscaled past the image's natural size.
    private func loadedImage(_ image: NSImage) -> some View {
        let size = Self.fittedDisplaySize(
            imageSize: image.size,
            availableWidth: availableWidth,
            maxHeight: Theme.plotMaxHeight)
        return Button(action: expand) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
        }
        .buttonStyle(.plain)
        .help("Click to expand")
        .accessibilityLabel("Plot image — opens at full size")
        .contextMenu {
            Button("Expand Plot", systemImage: "arrow.up.left.and.arrow.down.right", action: expand)
            Divider()
            Button("Copy Image", systemImage: "doc.on.doc", action: copyImage)
            Button("Save Image As…", systemImage: "square.and.arrow.down", action: saveImageAs)
            Button("Reveal in Finder", systemImage: "folder", action: revealInFinder)
        }
    }

    /// Quiet fixed-size box while the PNG decodes — same footprint as the
    /// missing state, so the tape doesn't jump between states.
    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
            .fill(.quaternary.opacity(0.5))
            .frame(width: Theme.plotPlaceholderWidth, height: Theme.plotPlaceholderHeight)
            .overlay {
                ProgressView()
                    .controlSize(.small)
            }
            .accessibilityLabel("Loading plot image")
    }

    private func load() async {
        image = nil
        loadFailed = false
        guard let path = rendition.path else { return }
        // Synchronous cache hit first: a recycled tape row re-shows its plot
        // without flashing the placeholder.
        if let cached = PlotImageCache.shared.cachedImage(forPath: path) {
            image = cached
            return
        }
        if let loaded = await PlotImageCache.shared.image(forPath: path) {
            image = loaded
        } else {
            // Gone (stale /tmp path after a worker restart) or undecodable —
            // the same honest missing state either way.
            loadFailed = true
        }
    }

    private func expand() {
        guard let image, let path = rendition.path else { return }
        onZoom(PlotZoomItem(title: title, path: path, image: image))
    }

    private func copyImage() {
        guard let image else { return }
        Pasteboard.copy(image: image)
    }

    private func revealInFinder() {
        guard let path = rendition.path else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Save As: copies the artifact file itself (byte-identical to what the
    /// worker saved), defaulting to its own `plot-NNNNN.png` name.
    private func saveImageAs() {
        guard let path = rendition.path else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = URL(fileURLWithPath: path).lastPathComponent
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try Data(contentsOf: URL(fileURLWithPath: path)).write(to: destination)
        } catch {
            // A user-initiated save must not fail silently.
            NSAlert(error: error).runModal()
        }
    }
}
