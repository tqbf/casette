import SwiftUI

/// A labeled, selectable, monospaced value in the Inspector tab — used for
/// every Sage/math string so they read as code, wrap instead of truncate,
/// and can be copied.
struct InspectorMonoField: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(Theme.Fonts.sidebarMono)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .contextMenu {
            Button("Copy \(label)") { Pasteboard.copy(value) }
        }
    }
}

#Preview {
    Form {
        InspectorMonoField(label: "Plain", value: "(x^2 + 1)*(x + 1)*(x - 1)")
    }
    .formStyle(.grouped)
    .frame(width: 280)
}
