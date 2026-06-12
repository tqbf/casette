import SwiftUI

/// The quiet header for the Doctor sheet: selected path, version standing,
/// and last-run status without taking over the whole window.
struct DoctorSummaryView: View {
    let model: DoctorModel

    var body: some View {
        HStack(alignment: .top, spacing: Theme.inputElementSpacing) {
            Image(systemName: "stethoscope")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.cardSectionLabelSpacing) {
                Text("Sage Doctor")
                    .font(.headline)
                Text(summary)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if let standing = model.versionStanding {
                Label(standingTitle(standing), systemImage: standingImage(standing))
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(standingStyle(standing))
            }
        }
    }

    private var summary: String {
        if model.isRunning {
            return "Running diagnostics..."
        }
        if let report = model.lastReport {
            return report.overallOK
                ? "All diagnostics passed."
                : "One or more diagnostics need attention."
        }
        if let selectedPath = model.selectedPath {
            if let version = model.versionDetection?.displayVersion {
                return "\(selectedPath) · Sage \(version)"
            }
            return selectedPath
        }
        return "No Sage binary selected."
    }

    private func standingTitle(_ standing: VersionStanding) -> String {
        switch standing {
        case .supported:
            "Supported"
        case .belowFloor:
            "Below Floor"
        case .unknown:
            "Unknown Version"
        }
    }

    private func standingImage(_ standing: VersionStanding) -> String {
        switch standing {
        case .supported:
            "checkmark.circle.fill"
        case .belowFloor:
            "exclamationmark.triangle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    private func standingStyle(_ standing: VersionStanding) -> AnyShapeStyle {
        switch standing {
        case .supported:
            AnyShapeStyle(.green)
        case .belowFloor:
            AnyShapeStyle(.yellow)
        case .unknown:
            AnyShapeStyle(.secondary)
        }
    }
}

#Preview {
    DoctorSummaryView(model: DoctorModel())
        .padding()
        .frame(width: 640)
}
