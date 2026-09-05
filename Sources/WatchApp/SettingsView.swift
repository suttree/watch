import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: WatchAppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerTheme) private var theme

    @State private var newSourceURL = ""
    @State private var editingSourceID: UUID?
    @State private var editingSourceURL = ""
    @State private var section: Section = .sources

    private enum Section: String, CaseIterable, Identifiable {
        case sources = "Sources"
        case themes = "Themes"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings")
                    .font(ReaderTheme.serif(20, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .embossedText()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            Picker("", selection: $section) {
                ForEach(Section.allCases) { Text($0.rawValue).embossedText().tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch section {
            case .sources:
                VStack(alignment: .leading, spacing: 14) {
                    Text("Firefox bookmarks").font(.headline)
                    Text("Watch reads the tv folder in Firefox's Bookmarks Toolbar or Menu, including its subfolders. If several folders share that name, the one closest to the toolbar or menu wins. Add or remove bookmarks in Firefox, then refresh Watch.")
                    Text(model.bookmarkStatus).foregroundStyle(.secondary)
                    Text("Videos shows saved YouTube videos. All includes your other bookmarks. Bookmark order uses the date you saved each link.")
                    Button("Sync now") { Task { await model.refresh() } }
                        .disabled(model.isRefreshing)
                    if let error = model.lastRefreshError { Text(error).foregroundStyle(.red) }
                }
            case .themes:
                ThemeGallery(selected: model.theme) { model.theme = $0 }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 520, height: 560)
        .background(theme.texturedPaper)
        .preferredColorScheme(.light)
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text("Tracked Sources")
                    .font(ReaderTheme.sans(13, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .embossedText()
                Text("Paste a website URL or an RSS/Atom feed URL. Read will pull stories from either.")
                    .font(ReaderTheme.sans(12))
                    .foregroundStyle(theme.inkSecondary)
                    .embossedText()

                List {
                    ForEach(model.sources.sorted {
                        $0.url.localizedStandardCompare($1.url) == .orderedAscending
                    }) { source in
                        if editingSourceID == source.id {
                            VStack(alignment: .leading, spacing: 6) {
                                TextField("Source URL", text: $editingSourceURL)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { saveSource(source.id) }
                                HStack(spacing: 8) {
                                    Button("Save") { saveSource(source.id) }
                                    Button("Cancel") { cancelEditing() }
                                    Spacer()
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                        } else {
                            HStack {
                                Text(source.url)
                                    .lineLimit(1)
                                    .embossedText()
                                Spacer()
                                Button {
                                    editingSourceID = source.id
                                    editingSourceURL = source.url
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.plain)
                                .help("Edit source URL")
                                Button(role: .destructive) {
                                    model.removeSource(source.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(height: 260)
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                HStack {
                    TextField("https://example.com or https://example.com/feed.xml", text: $newSourceURL)
                        .textFieldStyle(.roundedBorder)
                        .padding(.vertical, 2)
                        .onSubmit(addSource)
                    Button("Add", action: addSource)
                        .disabled(newSourceURL.trimmingCharacters(in: .whitespaces).isEmpty)
                }
        }
    }

    private func addSource() {
        model.addSource(urlString: newSourceURL)
        newSourceURL = ""
    }

    private func saveSource(_ id: UUID) {
        model.updateSourceURL(id, urlString: editingSourceURL)
        cancelEditing()
    }

    private func cancelEditing() {
        editingSourceID = nil
        editingSourceURL = ""
    }
}

/// The theme picker: every palette as it will actually look, rather than as a
/// name in a menu. Each card shows the two surfaces a theme decides — the
/// patterned header bar and the paper underneath it — alongside the app icon
/// that comes with it, because the icon is the most visible consequence of the
/// choice and the hardest to picture from a name like "Delaunay Triangles".
private struct ThemeGallery: View {
    let selected: ReaderTheme
    let choose: (ReaderTheme) -> Void

    @Environment(\.readerTheme) private var theme

    private let columns = [GridItem(.adaptive(minimum: 208), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(ReaderTheme.all) { candidate in
                    Button {
                        choose(candidate)
                    } label: {
                        ThemeCard(candidate: candidate, isSelected: candidate.id == selected.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: .infinity)
    }
}

private struct ThemeCard: View {
    let candidate: ReaderTheme
    let isSelected: Bool

    @Environment(\.readerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The header strip, drawn with the same renderer the window uses,
            // with the icon overlapping it the way it does in the Dock.
            ZStack(alignment: .leading) {
                Image(nsImage: candidate.headerImage(width: 420, height: 44))
                    .resizable()
                    .frame(height: 34)
                    .clipped()

                Image(nsImage: candidate.iconImage(size: 128))
                    .resizable()
                    .frame(width: 30, height: 30)
                    .padding(.leading, 6)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(ReaderTheme.sans(12, weight: .semibold))
                    .foregroundStyle(candidate.ink)
                    .embossedText()
                    .lineLimit(1)
                Text("Aa headline, and the body copy under it.")
                    .font(ReaderTheme.serif(11))
                    .foregroundStyle(candidate.inkSecondary)
                    .embossedText()
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(candidate.paper)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? theme.ink : theme.rule, lineWidth: isSelected ? 2 : 1)
        )
    }
}
