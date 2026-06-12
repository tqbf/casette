import SwiftUI

/// Live diagnostic check results, or the empty state before the first run.
struct DoctorCheckListView: View {
    let model: DoctorModel

    var body: some View {
        if model.checks.isEmpty {
            ContentUnavailableView(
                "No Checks Run",
                systemImage: "checklist",
                description: Text("Run checks to verify Sage can boot, evaluate, render math, plot, interrupt, and restart.")
            )
        } else {
            ForEach(model.checks, id: \.id) { check in
                DoctorCheckRowView(check: check)
            }
        }
    }
}

#Preview {
    Form {
        Section("Checks") {
            DoctorCheckListView(model: DoctorModel())
        }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 320)
}
