import SwiftUI

/// One labeled section of an expanded result card ("Input", "Generated
/// Sage", "Plain"): a quiet chrome label over selectable monospaced content,
/// with a copy item on the section's context menu.
struct CardSectionView: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardSectionLabelSpacing) {
            Text(label)
                .font(Theme.Fonts.cardSectionLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(Theme.Fonts.cardMono)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            Button("Copy \(label)") { Pasteboard.copy(value) }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        CardSectionView(label: "Input", value: "factor x^4 - 1")
        CardSectionView(label: "Generated Sage", value: "factor(x^4 - 1)")
        CardSectionView(label: "Plain", value: "(x^2 + 1)*(x + 1)*(x - 1)")
    }
    .padding()
    .frame(width: 480)
}
