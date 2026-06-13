import SwiftUI

struct HelpSectionView: View {
    let section: HelpSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(section.title)
                    .font(Theme.Fonts.helpSectionTitle)
                Text(section.summary)
                    .font(Theme.Fonts.helpBody)
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Input")
                    Text("Use")
                    Text("Generated Sage")
                }
                .font(Theme.Fonts.helpColumnLabel)
                .foregroundStyle(.tertiary)

                Divider()
                    .gridCellColumns(3)

                ForEach(section.examples) { example in
                    HelpExampleRowView(example: example)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ScrollView {
        HelpSectionView(section: HelpReference.sections[2])
            .padding()
    }
    .frame(width: 760)
}
