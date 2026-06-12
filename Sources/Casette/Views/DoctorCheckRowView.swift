import SwiftUI

/// A single Doctor check with icon, timing, and actionable detail.
struct DoctorCheckRowView: View {
    let check: CheckResult

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: Theme.cardSectionLabelSpacing) {
                Text(duration)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                if !check.detail.isEmpty {
                    Text(check.detail)
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        } label: {
            Label(check.name, systemImage: imageName)
                .foregroundStyle(style)
        }
    }

    private var imageName: String {
        switch check.status {
        case .ok:
            "checkmark.circle.fill"
        case .fail:
            "xmark.circle.fill"
        case .skipped:
            "minus.circle.fill"
        }
    }

    private var style: AnyShapeStyle {
        switch check.status {
        case .ok:
            AnyShapeStyle(.green)
        case .fail:
            AnyShapeStyle(.red)
        case .skipped:
            AnyShapeStyle(.secondary)
        }
    }

    private var duration: String {
        guard check.durationMillis > 0 else { return check.status.rawValue }
        return Duration
            .milliseconds(check.durationMillis)
            .formatted(.units(allowed: [.seconds, .milliseconds]))
    }
}

#Preview {
    Form {
        DoctorCheckRowView(
            check: CheckResult(
                id: "eval",
                name: "Eval test",
                status: .ok,
                durationMillis: 38,
                detail: "2 + 2 = 4"
            )
        )
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
