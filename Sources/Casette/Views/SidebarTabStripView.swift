import SwiftUI

struct SidebarTabStripView: View {
    @Binding var selection: SidebarTab

    var body: some View {
        VStack(spacing: 0) {
            Picker("Sidebar Tab", selection: $selection) {
                ForEach(SidebarTab.allCases) { tab in
                    Image(systemName: tab.systemImage)
                        .accessibilityLabel(tab.title)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(Theme.sidebarSectionPadding)

            Spacer(minLength: 0)
        }
        .background(.bar)
    }
}

#Preview {
    SidebarTabStripView(selection: .constant(.symbols))
        .frame(width: 280, height: 80)
}
