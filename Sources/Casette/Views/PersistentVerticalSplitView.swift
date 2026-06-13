import SwiftUI

/// A two-pane vertical split with an app-owned persisted dimension. SwiftUI's
/// `VSplitView` provides the right drag behavior, but not a stable autosave
/// hook, so this keeps the tiny bit of state explicit and testable.
struct PersistentVerticalSplitView<Top: View, Bottom: View>: View {
    enum PersistedPane {
        case top
        case bottom
    }

    @Binding var persistedDimension: Double
    let persistedPane: PersistedPane
    let minimumTopHeight: CGFloat
    let minimumBottomHeight: CGFloat
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    @State private var dragStartDimension: Double?

    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            let divider = UILayout.splitHandleThickness
            let dimension = clampedDimension(totalHeight: totalHeight)
            let topHeight = topHeight(
                dimension: dimension,
                totalHeight: totalHeight,
                divider: divider
            )
            let bottomHeight = max(
                minimumBottomHeight,
                totalHeight - topHeight - divider
            )

            VStack(spacing: 0) {
                top()
                    .frame(height: topHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
                SplitResizeHandle()
                    .gesture(resizeGesture(totalHeight: totalHeight))
                bottom()
                    .frame(height: bottomHeight)
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            .onAppear {
                persistedDimension = dimension
            }
            .onChange(of: totalHeight) {
                persistedDimension = clampedDimension(totalHeight: totalHeight)
            }
        }
    }

    private func resizeGesture(totalHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartDimension == nil {
                    dragStartDimension = persistedDimension
                }
                let start = dragStartDimension ?? persistedDimension
                let translated = switch persistedPane {
                case .top:
                    start + value.translation.height
                case .bottom:
                    start - value.translation.height
                }
                persistedDimension = clampedDimension(
                    translated,
                    totalHeight: totalHeight
                )
            }
            .onEnded { _ in
                dragStartDimension = nil
            }
    }

    private func topHeight(
        dimension: Double,
        totalHeight: CGFloat,
        divider: CGFloat
    ) -> CGFloat {
        switch persistedPane {
        case .top:
            CGFloat(dimension)
        case .bottom:
            max(
                minimumTopHeight,
                totalHeight - divider - CGFloat(dimension)
            )
        }
    }

    private func clampedDimension(totalHeight: CGFloat) -> Double {
        clampedDimension(persistedDimension, totalHeight: totalHeight)
    }

    private func clampedDimension(
        _ dimension: Double,
        totalHeight: CGFloat
    ) -> Double {
        switch persistedPane {
        case .top:
            UILayout.clampedSplitDimension(
                dimension,
                total: Double(totalHeight),
                minimumPrimary: Double(minimumTopHeight),
                minimumSecondary: Double(minimumBottomHeight)
            )
        case .bottom:
            UILayout.clampedSplitDimension(
                dimension,
                total: Double(totalHeight),
                minimumPrimary: Double(minimumBottomHeight),
                minimumSecondary: Double(minimumTopHeight)
            )
        }
    }
}

#Preview {
    PersistentVerticalSplitView(
        persistedDimension: .constant(120),
        persistedPane: .bottom,
        minimumTopHeight: 180,
        minimumBottomHeight: 72
    ) {
        Color.blue.opacity(0.2)
    } bottom: {
        Color.green.opacity(0.2)
    }
    .frame(width: 420, height: 360)
}
