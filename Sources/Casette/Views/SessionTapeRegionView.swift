import SwiftUI

struct SessionTapeRegionView: View {
    @Bindable var model: ShellModel

    var body: some View {
        VStack(spacing: 0) {
            SessionTapeView(model: model)
            if let issue = model.kernelIssue {
                Divider()
                KernelIssueBanner(
                    message: issue,
                    isSetupFailure: model.kernelSetupFailed,
                    restart: model.restartKernel,
                    openDoctor: model.openDoctor
                )
            }
        }
    }
}

#Preview {
    SessionTapeRegionView(model: ShellModel(rows: PlaceholderData.rows))
        .frame(width: 700, height: 520)
}
