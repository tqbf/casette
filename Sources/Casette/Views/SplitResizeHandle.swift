import SwiftUI

struct SplitResizeHandle: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .frame(height: UILayout.splitHandleThickness)
            .contentShape(Rectangle())
            .background(.bar)
            .accessibilityLabel("Resize split")
    }
}

#Preview {
    SplitResizeHandle()
        .frame(width: 320)
}
