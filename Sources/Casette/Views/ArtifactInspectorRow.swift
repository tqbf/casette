import SwiftUI

/// One artifact reference in the Inspector's Artifacts section: format,
/// liveness, and the path. A missing file is the NORMAL restored case
/// (the worker's /tmp session dir dies with it — PROBLEMS.md V0.10), so
/// "missing" reads quiet and factual, never alarming.
struct ArtifactInspectorRow: View {
    let artifact: PersistedArtifact

    var body: some View {
        LabeledContent(artifact.format.uppercased()) {
            VStack(alignment: .leading, spacing: 2) {
                Text(statusLine)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                if let path = artifact.path {
                    Text(path)
                        .font(Theme.Fonts.tracebackMono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu {
            if let path = artifact.path {
                Button("Copy Path") { Pasteboard.copy(path) }
            }
        }
    }

    private var statusLine: String {
        switch artifact.status {
        case .present:
            if let bytes = artifact.bytes {
                "On disk · \(bytes.formatted(.byteCount(style: .file)))"
            } else {
                "On disk"
            }
        case .missing:
            "Missing — rerun the row to regenerate it"
        }
    }
}

#Preview {
    Form {
        ArtifactInspectorRow(
            artifact: PersistedArtifact(
                type: "image", format: "png",
                path: "/tmp/sagecalc/session-123/plot-00001.png",
                bytes: 19432, status: .present))
        ArtifactInspectorRow(
            artifact: PersistedArtifact(
                type: "image", format: "svg",
                path: "/tmp/sagecalc/session-123/plot-00001.svg",
                bytes: nil, status: .missing))
    }
    .formStyle(.grouped)
    .frame(width: 300, height: 240)
}
