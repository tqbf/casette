import SwiftUI

/// Details for the selected tape row: the envelope fields the UI carries
/// (kind, plain, approx, LaTeX, error), the input split (raw vs generated
/// Sage), and the evaluation metadata (duration, time).
struct InspectorTabView: View {
    let row: SessionRow?

    var body: some View {
        if let row {
            Form {
                Section("Result") {
                    if let result = row.result {
                        LabeledContent("Kind", value: result.kind)
                        if !result.plain.isEmpty {
                            InspectorMonoField(label: "Plain", value: result.plain)
                        }
                        if let approx = result.approx {
                            InspectorMonoField(label: "Approx", value: "≈ \(approx)")
                        }
                        if let latex = result.latex {
                            InspectorMonoField(label: "LaTeX", value: latex)
                        }
                        if let error = result.error {
                            LabeledContent("Error", value: error.type)
                        }
                    } else {
                        LabeledContent("Status", value: "Not evaluated")
                    }
                }
                Section("Input") {
                    InspectorMonoField(label: "Raw", value: row.input)
                    InspectorMonoField(label: "Generated Sage", value: row.sage)
                }
                Section("Evaluation") {
                    if let duration = row.duration {
                        LabeledContent(
                            "Duration",
                            value: Duration.seconds(duration)
                                .formatted(.units(allowed: [.seconds, .milliseconds]))
                        )
                    }
                    LabeledContent("Time") {
                        Text(row.timestamp, style: .time)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "info.circle",
                description: Text("Select a result in the tape to inspect it.")
            )
        }
    }
}

#Preview("Selected") {
    InspectorTabView(row: PlaceholderData.rows[1])
        .frame(width: 280, height: 500)
}

#Preview("Empty") {
    InspectorTabView(row: nil)
        .frame(width: 280, height: 500)
}
