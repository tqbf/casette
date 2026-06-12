import SwiftUI

/// Details for the selected tape row: the envelope fields the UI carries
/// (kind, plain, approx, LaTeX, error), artifact references (path +
/// liveness, for plot rows), the input split (raw vs generated Sage), and
/// the evaluation metadata (duration, time).
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
                        if let exact = result.exact {
                            LabeledContent("Exact", value: exact ? "Yes" : "No")
                        }
                        if let approx = result.approx {
                            InspectorMonoField(label: "Approx", value: "≈ \(approx)")
                        }
                        if let exactValue = result.exactValue {
                            // A force-numeric row (V0.8): the primary is the
                            // decimal; the preserved exact form lives here.
                            InspectorMonoField(label: "Exact Value", value: exactValue)
                        }
                        if let latex = result.latex {
                            // Small rendered preview above the source —
                            // only when the engine can actually parse it.
                            // Leading-aligned and clipped to the column;
                            // wide math (matrices) scrolls horizontally,
                            // the same idiom as the tape hero — scrolling
                            // keeps the typeset size honest where
                            // scale-to-fit would shrink it unreadably.
                            if case .math = MathContent.choose(latex: latex) {
                                LabeledContent("Rendered") {
                                    ScrollView(.horizontal) {
                                        MathView(latex: latex, displayStyle: .inline)
                                    }
                                    .scrollIndicators(.automatic)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    // The typeset NSView is silent to
                                    // VoiceOver; the Plain and LaTeX fields
                                    // beside it carry the spoken value, so
                                    // hide the preview instead of reading an
                                    // empty "Rendered" row.
                                    .accessibilityHidden(true)
                                }
                            }
                            InspectorMonoField(label: "LaTeX", value: latex)
                        }
                        if let note = result.truncationNote {
                            LabeledContent("Truncated", value: note)
                        }
                        if let error = result.error {
                            LabeledContent("Error", value: error.type)
                            if let traceback = error.traceback, !traceback.isEmpty {
                                TracebackDisclosureView(traceback: traceback)
                            }
                        }
                    } else {
                        LabeledContent("Status", value: "Not evaluated")
                    }
                }
                if let artifacts = row.result?.artifacts, !artifacts.isEmpty {
                    Section("Artifacts") {
                        // Artifacts have no stable identity of their own
                        // (paths can repeat across formats); position in the
                        // envelope's array is the honest identity.
                        ForEach(Array(artifacts.enumerated()), id: \.offset) { _, artifact in
                            ArtifactInspectorRow(artifact: artifact)
                        }
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
