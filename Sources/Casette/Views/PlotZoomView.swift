import SwiftUI

/// Click-to-expand plot view, presented as a STANDARD sheet (the V1.7
/// decision): window-modal, native presentation animation, and Esc just
/// works — the Done button carries `.cancelAction`, the macOS idiom — with
/// no custom key plumbing (`EscapeInterceptor` stays a last resort for
/// focused-text-view cases; PROBLEMS.md V1.4).
///
/// The image shows at its natural full resolution (point size == pixel
/// size, set by `PlotImageCache`) inside a two-axis scroll view; the sheet
/// itself opens at the image's size, capped to sane bounds.
struct PlotZoomView: View {
    let item: PlotZoomItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.title)
                    .font(Theme.Fonts.rowInput)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: Theme.inputElementSpacing)
                Button("Done", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(Theme.plotZoomChromePadding)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: item.image)
                    .padding(Theme.plotZoomImagePadding)
                    .accessibilityLabel("Expanded plot for \(item.title)")
            }
        }
        .frame(
            minWidth: Theme.plotZoomMinWidth,
            idealWidth: idealWidth,
            minHeight: Theme.plotZoomMinHeight,
            idealHeight: idealHeight)
    }

    /// Open at the image's natural size plus chrome, capped — a small plot
    /// gets a snug sheet, a huge one gets scrollbars instead of a sheet
    /// bigger than the screen.
    private var idealWidth: CGFloat {
        min(item.image.size.width + Theme.plotZoomImagePadding * 2,
            Theme.plotZoomMaxIdealWidth)
    }

    private var idealHeight: CGFloat {
        min(item.image.size.height + Theme.plotZoomImagePadding * 2 + 44,
            Theme.plotZoomMaxIdealHeight)
    }
}
