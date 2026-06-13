import SwiftUI

struct HelpExampleRowView: View {
    let example: HelpExample

    var body: some View {
        GridRow {
            Text(example.command)
                .font(Theme.Fonts.helpCommand)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(example.detail)
                .font(Theme.Fonts.helpBody)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(example.sage)
                .font(Theme.Fonts.helpSage)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
        HelpExampleRowView(example: HelpReference.sections[0].examples[0])
    }
    .padding()
}
