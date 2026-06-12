import SwiftUI

/// The V1.10 Sage Doctor presented as a standard macOS sheet: discovery,
/// manual path selection, live checks, and a copyable diagnostic report.
struct DoctorSheetView: View {
    @Bindable var model: DoctorModel
    let reconnect: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            DoctorSummaryView(model: model)
                .padding(.horizontal, Theme.inputPaddingHorizontal)
                .padding(.vertical, Theme.inputPaddingVertical)

            Divider()

            Form {
                Section("Sage Binary") {
                    DoctorPathView(
                        model: model,
                        chooseSage: chooseSage
                    )
                }

                Section("Discovery") {
                    if model.candidates.isEmpty {
                        Text("No candidates checked yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.candidates.indices, id: \.self) { index in
                            DoctorCandidateRowView(candidate: model.candidates[index])
                        }
                    }
                }

                Section("Checks") {
                    DoctorCheckListView(model: model)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Button("Copy Report", action: model.copyReport)
                    .disabled(model.reportText == nil)

                Spacer()

                if model.isRunning {
                    Button("Stop", action: model.stopChecks)
                } else {
                    Button("Run Checks", action: model.runChecks)
                        .keyboardShortcut(.defaultAction)
                }

                Button("Done", action: close)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Theme.inputPaddingHorizontal)
            .padding(.vertical, Theme.inputPaddingVertical)
        }
        .frame(
            minWidth: 680,
            idealWidth: 760,
            minHeight: 500,
            idealHeight: 560
        )
        .onAppear(perform: prepare)
    }

    private func prepare() {
        model.reconnect = reconnect
        model.refresh()
    }

    private func chooseSage() {
        let panel = NSOpenPanel()
        panel.title = "Choose Sage"
        panel.prompt = "Choose"
        panel.message = "Select the Sage executable Casette should use."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.manualPath = url.path
        }
    }

    private func close() {
        dismiss()
    }
}

#Preview {
    DoctorSheetView(model: DoctorModel(), reconnect: {})
}
