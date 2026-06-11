import SwiftUI

/// Details for the selected tape row: the envelope fields the UI carries
/// (kind, input, generated Sage, plain, LaTeX, approx, timing).
struct InspectorTabView: View {
    let row: TapeRow?

    var body: some View {
        if let row {
            Form {
                Section("Result") {
                    LabeledContent("Kind", value: row.kind)
                    if !row.primary.isEmpty {
                        InspectorMonoField(label: "Plain", value: row.primary)
                    }
                    if let approx = row.approx {
                        InspectorMonoField(label: "Approx", value: "≈ \(approx)")
                    }
                    if let latex = row.latex {
                        InspectorMonoField(label: "LaTeX", value: latex)
                    }
                    if let errorType = row.errorType {
                        LabeledContent("Error", value: errorType)
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
