import SwiftUI

/// Centralized layout metrics + type system (SWIFTUI-RULES §2.4, §5.1).
///
/// Typography is a two-axis system:
/// - **Scale** comes from semantic SwiftUI text styles only (caption →
///   callout → body → title3 on macOS), never hardcoded point sizes, so
///   Dynamic Type and OS metric updates keep working.
/// - **Voice** separates math/Sage content (monospaced design) from chrome
///   (default UI face). Weight carries emphasis (medium for the result hero,
///   semibold for symbol names); de-emphasis is color
///   (.secondary/.tertiary), never a lighter weight.
enum Theme {
    // MARK: Window
    static let windowMinWidth: CGFloat = 720
    static let windowMinHeight: CGFloat = 480

    // MARK: Sidebar (inspector column)
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarIdealWidth: CGFloat = 280
    static let sidebarMaxWidth: CGFloat = 400

    // MARK: Tape
    static let tapeInset: CGFloat = 16
    static let tapeRowSpacing: CGFloat = 2
    static let rowCornerRadius: CGFloat = 8
    static let rowPaddingHorizontal: CGFloat = 12
    static let rowPaddingVertical: CGFloat = 10
    static let rowInnerSpacing: CGFloat = 5
    static let plotPlaceholderWidth: CGFloat = 220
    static let plotPlaceholderHeight: CGFloat = 130

    // MARK: Input pane
    static let inputPaddingHorizontal: CGFloat = 16
    static let inputPaddingVertical: CGFloat = 12
    static let inputElementSpacing: CGFloat = 8
    /// Vertical gap between the input field and the compile-preview line.
    static let inputPreviewSpacing: CGFloat = 4
    /// The expanding editor's height ceiling (~6 input lines); content
    /// beyond it scrolls inside the editor.
    static let inputMaxHeight: CGFloat = 140
    /// The editor's internal text insets (mirrored by the sizing text so the
    /// field grows exactly with its content).
    static let inputEditorInsetVertical: CGFloat = 4
    static let inputEditorInsetHorizontal: CGFloat = 5
    /// Reserved height of the compile-preview line (stable while typing).
    static let inputPreviewMinHeight: CGFloat = 16
    /// Optical alignment of the pane's accessories (chevron, hints, status)
    /// against the editor's first text line.
    static let inputAccessoryTopPadding: CGFloat = 6

    // MARK: Ambiguity panel (the inline suggestion panel above the input)
    /// Gap between the panel's bottom edge and the input pane's top edge.
    static let ambiguityPanelGap: CGFloat = 6
    static let ambiguityPanelCornerRadius: CGFloat = 10
    static let ambiguityPanelPadding: CGFloat = 6
    static let ambiguityRowCornerRadius: CGFloat = 6
    static let ambiguityRowPaddingHorizontal: CGFloat = 8
    static let ambiguityRowPaddingVertical: CGFloat = 5

    // MARK: Sidebar content
    static let sidebarSectionPadding: CGFloat = 10

    // MARK: Row background priority (selected > hovered > clear; §7.2)
    static func rowBackground(isSelected: Bool, isHovered: Bool) -> AnyShapeStyle {
        if isSelected {
            AnyShapeStyle(Color.accentColor.opacity(0.12))
        } else if isHovered {
            AnyShapeStyle(Color.gray.opacity(0.08))
        } else {
            AnyShapeStyle(Color.clear)
        }
    }

    // MARK: Type scale
    enum Fonts {
        /// The echoed command at the top of a tape row — a label, not the hero.
        static let rowInput = Font.callout.monospaced()
        /// The primary result line — the hero of a tape row.
        static let resultPrimary = Font.title3.weight(.medium).monospaced()
        /// The secondary `≈ …` approximation line.
        static let resultSecondary = Font.callout.monospaced()
        /// Timestamps and other row metadata.
        static let meta = Font.caption
        /// Error type name above an error message.
        static let errorType = Font.caption.weight(.semibold)
        /// Symbol name in the Symbols tab.
        static let symbolName = Font.body.weight(.semibold).monospaced()
        /// Symbol summary / history entries — Sage text in chrome contexts.
        static let sidebarMono = Font.callout.monospaced()
        /// Symbol kind label.
        static let symbolKind = Font.caption
        /// The bottom input field — prominent, calculator-like.
        static let input = Font.title3.monospaced()
        /// The live generated-Sage preview under the input — Sage text in a
        /// chrome context, one scale below the field (callout + mono, the
        /// same voice as `sidebarMono`).
        static let inputPreviewSage = Font.callout.monospaced()
        /// Inline compile-issue prose under the input (metadata scale,
        /// default face — it's guidance, not math).
        static let inputPreviewIssue = Font.caption
        /// The `Try: …` suggestion inside a compile issue — example input,
        /// so it keeps the mono voice at the metadata scale.
        static let inputPreviewSuggestion = Font.caption.monospaced()
    }
}
