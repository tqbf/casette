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
    static let tapeMinHeight: CGFloat = 180
    static let tapeInset: CGFloat = 16
    /// Bottom content margin of the tape's scroll view (a scroll-content
    /// inset, not a spacer view), so the last row — including multi-line
    /// math heroes like matrices — always rests fully clear of the input
    /// pane at the default window size.
    static let tapeBottomMargin: CGFloat = 24
    static let tapeRowSpacing: CGFloat = 2
    static let rowCornerRadius: CGFloat = 8
    static let rowPaddingHorizontal: CGFloat = 12
    static let rowPaddingVertical: CGFloat = 10
    static let rowInnerSpacing: CGFloat = 5
    // MARK: Plot cards (V1.7)
    /// The quiet fixed-size box shown while a plot PNG decodes and when it's
    /// missing (the honest restored/failed state) — fixed so the tape never
    /// jumps while an image loads.
    static let plotPlaceholderWidth: CGFloat = 260
    static let plotPlaceholderHeight: CGFloat = 150
    /// Tallest an inline plot image renders in a card (aspect-preserving,
    /// never upscaled past its natural size; click to expand for full size).
    static let plotMaxHeight: CGFloat = 280
    /// The zoom sheet: floors, ideal-size caps, and chrome paddings.
    static let plotZoomMinWidth: CGFloat = 520
    static let plotZoomMinHeight: CGFloat = 420
    static let plotZoomMaxIdealWidth: CGFloat = 1000
    static let plotZoomMaxIdealHeight: CGFloat = 760
    static let plotZoomChromePadding: CGFloat = 12
    static let plotZoomImagePadding: CGFloat = 16

    // MARK: Math (SwiftMath point sizes)
    //
    // The one place hardcoded point sizes are allowed: `MTMathUILabel` takes
    // a raw `fontSize`, not a semantic style (documented deviation from
    // §5.1). Block math is the tape's hero — set ABOVE the title3 text hero
    // (15pt) because typeset math (fractions, scripts, matrices) reads
    // optically smaller than mono text at equal point size.
    /// Hero math in a result card.
    static let mathBlockPointSize: CGFloat = 19
    /// Small math woven into chrome (the Inspector's LaTeX preview).
    static let mathInlinePointSize: CGFloat = 13

    // MARK: Result card (V1.5)
    /// Vertical gap between an expanded card's sections (8-grid).
    static let cardSectionSpacing: CGFloat = 8
    /// Gap between a section's label and its value.
    static let cardSectionLabelSpacing: CGFloat = 2
    /// Inset of the expanded detail block from the row's leading edge.
    static let cardExpandedInset: CGFloat = 14
    /// Max height of a traceback disclosure before it scrolls.
    static let tracebackMaxHeight: CGFloat = 180

    // MARK: Input pane
    static let inputMinHeight: CGFloat = 72
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
    /// Optical alignment of the pane's small CONTROLS (the V1.8 numeric
    /// toggle + precision menu) — controls carry their own chrome height,
    /// so they sit a touch higher than bare-text accessories.
    static let inputControlTopPadding: CGFloat = 2
    /// Leading inset for formula and preview lanes so they line up with the
    /// editor text after the prompt chevron.
    static let inputFormulaLeadingInset: CGFloat = 24

    // MARK: Formula autocomplete bar
    static let formulaTokenCornerRadius: CGFloat = 7

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
    static let sidebarTabStripMinHeight: CGFloat = 44
    static let sidebarContentMinHeight: CGFloat = 160
    /// Indent of an action row's command preview under its title, aligning
    /// it with the title text after the Label's icon column.
    static let actionCommandIndent: CGFloat = 24

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
        /// Section labels in an expanded card ("Input", "Generated Sage",
        /// "Plain") — chrome at the metadata scale, weight for structure.
        static let cardSectionLabel = Font.caption.weight(.semibold)
        /// Sage/math text inside an expanded card's sections and captured
        /// stdout — content voice (mono), one step under the result hero.
        static let cardMono = Font.callout.monospaced()
        /// Traceback text — diagnostic content, dense, smallest mono scale.
        static let tracebackMono = Font.caption.monospaced()
        /// The truncation note under a capped result (metadata voice).
        static let truncationNote = Font.caption
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
        /// Formula function token, like Numbers' function dropdown.
        static let formulaFunction = Font.callout.weight(.semibold)
        /// Formula argument labels are chrome, not content.
        static let formulaTokenLabel = Font.caption.weight(.medium)
        /// Formula argument values are editable math/source fragments.
        static let formulaTokenValue = Font.callout.monospaced()
        /// Formula punctuation between tokens.
        static let formulaPunctuation = Font.callout.weight(.semibold).monospaced()
        /// Help window title.
        static let helpTitle = Font.title2.weight(.semibold)
        /// Help section headings.
        static let helpSectionTitle = Font.title3.weight(.semibold)
        /// Help explanatory prose.
        static let helpBody = Font.callout
        /// Help table labels.
        static let helpColumnLabel = Font.caption.weight(.semibold)
        /// Friendly input examples.
        static let helpCommand = Font.callout.weight(.medium).monospaced()
        /// Generated Sage examples.
        static let helpSage = Font.caption.monospaced()
        /// Matrix table window title.
        static let matrixTableTitle = Font.title3.weight(.semibold)
        /// Matrix table column/row headers.
        static let matrixTableHeader = Font.caption.weight(.semibold).monospacedDigit()
        /// Matrix table values.
        static let matrixTableCell = Font.callout.monospaced()
        /// Hovered matrix coordinate badge.
        static let matrixTableHover = Font.caption.weight(.medium)
    }
}
