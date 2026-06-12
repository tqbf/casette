import SwiftUI

/// The large results pane: a scrolling tape of evaluation rows, newest at
/// the bottom (calculator-tape semantics — the view rests at the bottom and
/// follows appends).
struct SessionTapeView: View {
    var model: ShellModel

    var body: some View {
        if model.rows.isEmpty {
            ContentUnavailableView(
                "No Calculations Yet",
                systemImage: "function",
                description: Text("Type an expression below and press Return.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.tapeRowSpacing) {
                        ForEach(model.rows) { row in
                            TapeRowView(
                                row: row,
                                isSelected: model.selectedRowID == row.id,
                                isKernelConnected: model.kernelState.isConnected,
                                provenanceMark: model.provenanceMark(for: row),
                                onSelect: { model.select(row.id) },
                                onToggleExpanded: { model.toggleExpanded(rowID: row.id) },
                                onRerun: { model.rerun(rowID: row.id) },
                                onApproximate: { model.approximateNumerically(rowID: row.id) }
                            )
                            .id(row.id)
                        }
                    }
                    .padding([.horizontal, .top], Theme.tapeInset)
                }
                // Bottom clearance is a CONTENT MARGIN (not padding on the
                // stack and not a spacer): the scroll geometry itself ends
                // above the input pane, so resting at the bottom anchor —
                // and `scrollTo(anchor: .bottom)` — always leaves the last
                // row's full height (matrix bottom rows included) visible.
                .contentMargins(.bottom, Theme.tapeBottomMargin, for: .scrollContent)
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.rows.count) {
                    scrollToBottom(proxy)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = model.rows.last else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }
}

#Preview {
    SessionTapeView(model: ShellModel(rows: PlaceholderData.rows))
        .frame(width: 700, height: 600)
}
