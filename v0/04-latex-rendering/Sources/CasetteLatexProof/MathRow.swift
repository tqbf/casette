import SwiftUI
import AppKit

/// Centralized layout metrics (SWIFTUI-RULES §2.4 — no sprinkled magic numbers).
enum ProofMetrics {
    static let rowVerticalPadding: CGFloat = 14
    static let rowHorizontalPadding: CGFloat = 20
    static let rowInnerGap: CGFloat = 8
    static let cardCornerRadius: CGFloat = 8
    static let chipCornerRadius: CGFloat = 4
    static let listSpacing: CGFloat = 10
    static let secondaryOpacity: Double = 0.62
}

/// One result row: a card with the source (input) caption, a kind chip, the
/// rendered math (the hero), and the plain-text fallback line. Right-click and a
/// hover button both offer "Copy LaTeX".
struct MathRow: View {
    let index: Int
    let result: MathResult

    @State private var isHovered = false
    @State private var justCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: ProofMetrics.rowInnerGap) {
            header
            mathBody
            plainFallback
        }
        .padding(.vertical, ProofMetrics.rowVerticalPadding)
        .padding(.horizontal, ProofMetrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ProofMetrics.cardCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ProofMetrics.cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .onHover { isHovered = $0 }
        // Right-click menu (SWIFTUI-RULES §7.4 — context menu on every actionable
        // row). Works inside a ScrollView where .swipeActions would not (§4.1).
        .contextMenu {
            Button("Copy LaTeX") { copyLatex() }
            Button("Copy plain") { copyPlain() }
        }
    }

    // MARK: Header — index · provenance · kind chip · copy affordance

    private var header: some View {
        HStack(spacing: ProofMetrics.rowInnerGap) {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(result.source)
                .font(.callout)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: ProofMetrics.rowInnerGap)

            kindChip

            // Hover-revealed copy button — opacity-fade, never insert-on-hover
            // (SWIFTUI-RULES §4.5), so the row width never reflows.
            Button {
                copyLatex()
            } label: {
                Label(justCopied ? "Copied" : "Copy LaTeX",
                      systemImage: justCopied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .opacity(isHovered || justCopied ? 1 : 0)
            .allowsHitTesting(isHovered || justCopied)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: justCopied)
        }
    }

    private var kindChip: some View {
        Text(result.kind)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(chipColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: ProofMetrics.chipCornerRadius)
                    .fill(chipColor.opacity(0.14))
            )
            .fixedSize()
    }

    private var chipColor: Color {
        switch result.provenance {
        case .spec:    return .blue
        case .worker:  return .green
        case .inline:  return .purple
        case .invalid: return .red
        case .bulk:    return .secondary
        }
    }

    // MARK: Math body — the hero, through the MathRenderer abstraction
    //
    // Extracted into `MathHero` so header-state redraws (hover, copied) don't
    // churn the math view graph (swiftui-pro §6.3 / P2).

    private var mathBody: some View {
        MathHero(latex: result.latex,
                 displayStyle: result.displayStyle,
                 plain: result.plain)
    }

    // MARK: Plain fallback line

    private var plainFallback: some View {
        Text(result.plain)
            .font(.footnote)
            .fontDesign(.monospaced)
            .foregroundStyle(.tertiary)
            .lineLimit(2)
            .truncationMode(.tail)
            .accessibilityHidden(true)
    }

    // MARK: Copy

    private func copyLatex() {
        writePasteboard(result.latex)
        flashCopied()
    }

    private func copyPlain() {
        writePasteboard(result.plain)
        flashCopied()
    }

    private func writePasteboard(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }

    private func flashCopied() {
        justCopied = true
        // Cancellable reset tied to the view — a recycled LazyVStack row or a
        // rapid double-copy won't leave a stale closure flipping the wrong row
        // (swiftui-pro P2).
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(1.1))
            guard !Task.isCancelled else { return }
            justCopied = false
        }
    }
}

/// The rendered-math hero, isolated so its expensive view graph is decoupled
/// from the row's lightweight header/hover state. Block math is the full-size
/// centered result; inline math is woven into a sentence on the text baseline.
private struct MathHero: View {
    let latex: String
    let displayStyle: MathDisplayStyle
    let plain: String

    var body: some View {
        Group {
            if displayStyle == .inline {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("The value")
                    MathView(latex: latex, displayStyle: .inline)
                    Text("appears mid-sentence.")
                }
                .font(.body)
            } else {
                MathView(latex: latex, displayStyle: .block)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Breathing room so tall glyphs (∫, ∑, matrices) don't crowd
                    // the source caption above or the plain line below.
                    .padding(.vertical, 6)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(plain)
    }
}
