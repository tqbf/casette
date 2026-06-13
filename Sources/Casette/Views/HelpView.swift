import SwiftUI

struct HelpView: View {
    @State private var searchText = ""

    private var filteredSections: [HelpSection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return HelpReference.sections }

        return HelpReference.sections.compactMap { section in
            let matchingExamples = section.examples.filter { example in
                example.command.localizedCaseInsensitiveContains(query)
                    || example.detail.localizedCaseInsensitiveContains(query)
                    || example.sage.localizedCaseInsensitiveContains(query)
            }

            if section.title.localizedCaseInsensitiveContains(query)
                || section.summary.localizedCaseInsensitiveContains(query) {
                return section
            }

            guard !matchingExamples.isEmpty else { return nil }
            return HelpSection(
                title: section.title,
                summary: section.summary,
                examples: matchingExamples
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    overview

                    if filteredSections.isEmpty {
                        ContentUnavailableView.search
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(filteredSections) { section in
                            HelpSectionView(section: section)
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 680, minHeight: 520)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(HelpReference.title)
                    .font(Theme.Fonts.helpTitle)
                Text("Complete reference for Casette's command-first calculator syntax")
                    .font(Theme.Fonts.helpBody)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(HelpReference.overview, id: \.self) { line in
                Text(line)
                    .font(Theme.Fonts.helpBody)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    HelpView()
        .frame(width: 820, height: 620)
}
