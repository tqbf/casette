import SwiftUI

/// The kernel recovery banner, shown between the tape and the input pane
/// when the kernel is unavailable for a reason (no Sage found, crash, forced
/// stop): the honest explanation plus the right recovery action.
struct KernelIssueBanner: View {
    let message: String
    var isSetupFailure = false
    let restart: () -> Void
    let openDoctor: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.inputElementSpacing) {
            Label {
                Text(message)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            Spacer(minLength: Theme.inputElementSpacing)
            if isSetupFailure {
                Button("Open Sage Doctor", action: openDoctor)
                    .controlSize(.small)
            } else {
                Button("Restart Sage", action: restart)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.inputPaddingHorizontal)
        .padding(.vertical, Theme.sidebarSectionPadding)
        .background(.yellow.opacity(0.12))
    }
}

#Preview {
    KernelIssueBanner(
        message: "Sage stopped unexpectedly. Restart Sage to continue (variables will be reset).",
        restart: {},
        openDoctor: {}
    )
    .frame(width: 640)
}
