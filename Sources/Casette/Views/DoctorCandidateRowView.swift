import SwiftUI

/// One path the Doctor considered during discovery.
struct DoctorCandidateRowView: View {
    let candidate: ReportCandidate

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: Theme.cardSectionLabelSpacing) {
                Text(candidate.path)
                    .font(Theme.Fonts.sidebarMono)
                    .textSelection(.enabled)
                Text(detail)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label(sourceTitle, systemImage: imageName)
        }
    }

    private var imageName: String {
        if candidate.selected {
            return "checkmark.circle.fill"
        }
        return candidate.exists ? "circle" : "xmark.circle"
    }

    private var detail: String {
        if candidate.selected {
            return "selected"
        }
        return candidate.exists ? "available" : "not found"
    }

    private var sourceTitle: String {
        switch candidate.source {
        case "override":
            "Manual"
        case "stored":
            "Saved"
        case "knownPath":
            "Known Path"
        case "pathLookup":
            "PATH"
        default:
            candidate.source
        }
    }
}

#Preview {
    Form {
        DoctorCandidateRowView(
            candidate: ReportCandidate(
                path: "/usr/local/bin/sage",
                source: "pathLookup",
                exists: true,
                selected: true
            )
        )
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
