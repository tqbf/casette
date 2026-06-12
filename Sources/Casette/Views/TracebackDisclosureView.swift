import SwiftUI

/// The traceback behind a disclosure — hidden by default, one click away
/// (the V1.5 exit criterion). A plain structural conditional with NO
/// transition (SWIFTUI-RULES §1.1; same precedent as the kernel banner), so
/// it can't trip the hosted-constraint crash. Deliberately not a
/// `DisclosureGroup`, which animates insertion.
struct TracebackDisclosureView: View {
    let traceback: String

    @State private var isShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.cardSectionLabelSpacing) {
            Button(action: toggle) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .rotationEffect(.degrees(isShown ? 90 : 0))
                    Text("Traceback")
                        .font(Theme.Fonts.cardSectionLabel)
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isShown ? "Hide traceback" : "Show traceback")

            if isShown {
                ScrollView {
                    Text(traceback)
                        .font(Theme.Fonts.tracebackMono)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: Theme.tracebackMaxHeight)
                .contextMenu {
                    Button("Copy Traceback") { Pasteboard.copy(traceback) }
                }
            }
        }
    }

    private func toggle() {
        isShown.toggle()
    }
}

#Preview {
    TracebackDisclosureView(
        traceback: "Traceback (most recent call last):\n  File \"<string>\", line 1\nZeroDivisionError: rational division by zero"
    )
    .padding()
    .frame(width: 480)
}
