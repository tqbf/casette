import SwiftUI

/// The selected/stored Sage path plus the manual override controls.
struct DoctorPathView: View {
    @Bindable var model: DoctorModel
    let chooseSage: () -> Void

    var body: some View {
        if let selectedPath = model.selectedPath {
            InspectorMonoField(label: "Selected", value: selectedPath)
        } else {
            LabeledContent("Selected", value: "None")
        }

        if let storedPath = model.storedPath {
            InspectorMonoField(label: "Saved", value: storedPath)
            Button("Forget Saved Path", action: model.forgetStoredPath)
                .disabled(!model.canForgetStoredPath)
        }

        TextField("Sage executable path", text: $model.manualPath)
            .font(Theme.Fonts.sidebarMono)
            .textFieldStyle(.roundedBorder)
            .disabled(model.isRunning)

        HStack {
            Button("Choose Sage…", action: chooseSage)
                .disabled(model.isRunning)
            Button("Use This Sage", action: model.useManualPath)
                .disabled(!model.canUseManualPath || model.manualPathIssue != nil)
        }

        if let issue = model.manualPathIssue ?? model.useIssue {
            Label(issue, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    Form {
        Section("Sage Binary") {
            DoctorPathView(model: DoctorModel(), chooseSage: {})
        }
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
