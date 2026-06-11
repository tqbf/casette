import SwiftUI

/// Centralized layout metrics (SWIFTUI-RULES §2.4 — no sprinkled magic numbers).
enum Metrics {
    static let rowSpacing: CGFloat = 10
    static let cardPadding: CGFloat = 14
    static let plotMaxHeight: CGFloat = 300
    static let cardCorner: CGFloat = 12
}

/// One plot in the scrolling tape: source caption, a format toggle, byte sizes,
/// and the rendered image. Clicking the image opens a zoomed view.
struct PlotRow: View {
    let plot: PlotArtifact
    /// The format selected for THIS row. Bound up so each row can independently
    /// flip SVG/PNG — that's how we verify both on screen.
    @Binding var format: PlotFormat
    let onExpand: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            header
            plotImage
            footer
        }
        .padding(Metrics.cardPadding)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: Metrics.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(plot.title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            formatPicker
        }
    }

    private var formatPicker: some View {
        Picker("Format", selection: $format) {
            ForEach(PlotFormat.allCases) { f in
                Text(f.rawValue)
                    .tag(f)
                    // Disable a format whose file is missing for this plot.
                    .disabled(f == .svg ? !plot.hasSVG : !plot.hasPNG)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var plotImage: some View {
        PlotImageView(url: currentURL, format: format)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: Metrics.plotMaxHeight)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
            .help("Click to zoom")
            .contextMenu {
                Button("Zoom", systemImage: "arrow.up.left.and.arrow.down.right", action: onExpand)
                if let url = currentURL {
                    Button("Reveal in Finder", systemImage: "folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    Button("Copy Path", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                }
            }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(format.rawValue, systemImage: format == .svg ? "scribble.variable" : "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let bytes = currentBytes {
                Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            Text(plot.id)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
    }

    private var currentURL: URL? {
        format == .svg ? plot.svgURL : plot.pngURL
    }

    private var currentBytes: Int? {
        format == .svg ? plot.svgBytes : plot.pngBytes
    }
}
