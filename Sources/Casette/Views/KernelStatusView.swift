import SwiftUI

/// The honest kernel status indicator: a small tinted dot + label living at
/// the trailing edge of the input pane. States differ by text as well as
/// color (never color-only); the tooltip carries the precise machine state
/// and any issue detail.
struct KernelStatusView: View {
    let state: KernelState
    let issue: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(label)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(issue ?? "Sage kernel state: \(state.rawValue)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sage: \(label)")
    }

    private var label: String {
        switch state {
        case .notConnected: "Sage not connected"
        case .restarting: "Starting Sage…"
        case .running: "Working…"
        case .crashed: "Sage stopped"
        case .idle, .completed, .error, .interrupted, .timedOut: "Sage ready"
        }
    }

    private var tint: Color {
        switch state {
        case .notConnected: .gray
        case .restarting: .yellow
        case .running: .blue
        case .crashed: .red
        case .idle, .completed, .error, .interrupted, .timedOut: .green
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        KernelStatusView(state: .notConnected, issue: nil)
        KernelStatusView(state: .restarting, issue: nil)
        KernelStatusView(state: .running, issue: nil)
        KernelStatusView(state: .completed, issue: nil)
        KernelStatusView(state: .crashed, issue: "Sage stopped unexpectedly.")
    }
    .padding()
}
