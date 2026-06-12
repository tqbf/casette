import SwiftUI

/// The honest state for a plot whose PNG isn't on disk: the file lived in
/// the worker's session-scoped /tmp dir, which dies with the worker — so a
/// missing image is the NORMAL restored case, not an error (PROBLEMS.md
/// V0.5/V0.10), and it reads quiet. A save *failure* (the worker's
/// per-format error) shows its reason. Rerun re-evaluates the row through
/// the normal submit path, which regenerates fresh artifacts.
struct PlotMissingView: View {
    /// The worker's per-format save error, when the PNG never saved.
    let saveError: String?
    let canRerun: Bool
    let onRerun: () -> Void

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.rowCornerRadius)
            .fill(.quaternary.opacity(0.5))
            .frame(width: Theme.plotPlaceholderWidth, height: Theme.plotPlaceholderHeight)
            .overlay {
                VStack(spacing: 6) {
                    // Decorative — the message carries the meaning.
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                    Text(message)
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                    // Stays its own element so assistive tech can activate it.
                    Button("Rerun", systemImage: "arrow.clockwise", action: onRerun)
                        .controlSize(.small)
                        .disabled(!canRerun)
                        .help(canRerun ? "Re-evaluate this row to regenerate the plot" : "Replay the session before regenerating restored plots")
                }
                .padding(Theme.rowPaddingHorizontal)
            }
    }

    private var message: String {
        if let saveError {
            "PNG couldn't be saved — \(saveError)"
        } else {
            "Plot image missing — rerun to regenerate it"
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        PlotMissingView(saveError: nil, canRerun: true, onRerun: {})
        PlotMissingView(
            saveError: "OSError: [Errno 28] No space left on device",
            canRerun: true,
            onRerun: {}
        )
    }
    .padding()
}
