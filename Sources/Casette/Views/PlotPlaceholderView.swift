import SwiftUI

/// Stand-in for a rendered plot artifact (V1.7 renders the real PNG). Keeps
/// the tape's layout honest about hosting non-text result content.
struct PlotPlaceholderView: View {
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.rowInnerSpacing) {
            RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
                .fill(.quaternary.opacity(0.5))
                .frame(width: Theme.plotPlaceholderWidth, height: Theme.plotPlaceholderHeight)
                .overlay {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Plot preview placeholder")
            Text(caption)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    PlotPlaceholderView(caption: "Graphics object consisting of 1 graphics primitive")
        .padding()
}
