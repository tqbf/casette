import SwiftUI

/// The V0.5 plot-artifact viewer: a scrolling tape of the plots a Casette Sage
/// worker produced, loaded from its session directory. Proves the macOS UI can
/// render worker-generated SVG/PNG artifacts.
struct ContentView: View {
    @State private var plots: [PlotArtifact] = []
    @State private var sessionDir: URL?
    /// Per-row chosen format, keyed by plot id. Defaults follow `globalFormat`.
    @State private var formats: [String: PlotFormat] = [:]
    @State private var globalFormat: PlotFormat = .svg
    @State private var zoomed: PlotArtifact?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(minWidth: 560, minHeight: 640)
        .onAppear(perform: reload)
        .sheet(item: $zoomed) { plot in
            ZoomView(plot: plot, format: format(for: plot))
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Casette · Plot Artifacts")
                    .font(.headline)
                if let dir = sessionDir {
                    Text(dir.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Picker("Default format", selection: $globalFormat) {
                ForEach(PlotFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .onChange(of: globalFormat) { _, new in
                // Apply the new default to every row.
                for p in plots { formats[p.id] = new }
            }
            Button("Reload", systemImage: "arrow.clockwise", action: reload)
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if plots.isEmpty {
            ContentUnavailableView {
                Label("No plot artifacts found", systemImage: "chart.xyaxis.line")
            } description: {
                Text("Run the V0.5 harness with --keep to produce a session dir under /tmp/sagecalc, then Reload.")
            } actions: {
                Button("Reload", action: reload)
            }
        } else {
            List {
                ForEach(plots) { plot in
                    PlotRow(plot: plot, format: binding(for: plot)) {
                        zoomed = plot
                    }
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - State helpers

    private func binding(for plot: PlotArtifact) -> Binding<PlotFormat> {
        Binding(
            get: { format(for: plot) },
            set: { formats[plot.id] = $0 }
        )
    }

    private func format(for plot: PlotArtifact) -> PlotFormat {
        formats[plot.id] ?? globalFormat
    }

    private func reload() {
        guard let dir = PlotLoader.newestSessionDirectory() else {
            plots = []
            sessionDir = nil
            return
        }
        sessionDir = dir
        plots = PlotLoader.load(from: dir)
        // Seed any new rows with the current global default.
        for p in plots where formats[p.id] == nil { formats[p.id] = globalFormat }
    }
}

/// A zoomed view of one plot, shown in a sheet. Proves the click-to-expand path
/// and lets us inspect raster/vector quality up close.
struct ZoomView: View {
    let plot: PlotArtifact
    @State var format: PlotFormat
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(plot.title).font(.headline).lineLimit(1)
                Spacer()
                Picker("Format", selection: $format) {
                    ForEach(PlotFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                            .disabled(f == .svg ? !plot.hasSVG : !plot.hasPNG)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                PlotImageView(url: format == .svg ? plot.svgURL : plot.pngURL, format: format)
                    .frame(minWidth: 700, minHeight: 520)
                    .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 640)
    }
}
