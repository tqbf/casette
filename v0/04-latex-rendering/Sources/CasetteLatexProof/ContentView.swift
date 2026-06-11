import SwiftUI

struct ContentView: View {
    private let rows = SampleData.all

    /// Debug appearance override. The spec asks for an in-app toggle so we can
    /// flip dark mode reliably for on-screen verification (vs. fighting System
    /// Settings). nil = follow system.
    @State private var forcedScheme: ColorScheme? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        // Apply the debug override to the whole tree.
        .preferredColorScheme(forcedScheme)
    }

    // MARK: Header — title + appearance toggle

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Casette — Math Rendering Proof")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("V0.4 · \(rows.count) rows · SwiftMath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            appearancePicker
        }
        .padding(.horizontal, ProofMetrics.rowHorizontalPadding)
        .padding(.vertical, 14)
    }

    private var appearancePicker: some View {
        Picker("Appearance", selection: $forcedScheme) {
            Text("System").tag(ColorScheme?.none)
            Text("Light").tag(ColorScheme?.some(.light))
            Text("Dark").tag(ColorScheme?.some(.dark))
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    // MARK: List — the scrolling tape (ScrollView + LazyVStack for 50+ rows)

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: ProofMetrics.listSpacing) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    MathRow(index: idx + 1, result: row)
                }
            }
            .padding(.horizontal, ProofMetrics.rowHorizontalPadding)
            .padding(.vertical, ProofMetrics.listSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer — which engine is on screen (verification aid)

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "function")
                .foregroundStyle(.secondary)
            Text("Engine: \(activeMathRenderer.engineName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, ProofMetrics.rowHorizontalPadding)
        .padding(.vertical, 8)
    }
}
