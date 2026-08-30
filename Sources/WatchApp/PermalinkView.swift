import WatchCore
import SwiftUI

struct PermalinkView: View {
    @ObservedObject var model: WatchAppModel
    let story: Story

    @Environment(\.readerTheme) private var theme
    @State private var article: Article?
    @State private var isLoadingArticle = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear
                        .frame(height: 1)
                        .id("top")

                Text(story.sourceName.uppercased())
                    .font(ReaderTheme.sans(11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.inkSecondary)
                    .embossedText()

                Text(article?.title ?? story.title)
                    .font(ReaderTheme.serif(30, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .shadow(color: .white, radius: 1, x: 0, y: 1)

                if isLoadingArticle {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Fetching article…")
                            .font(ReaderTheme.sans(13))
                            .foregroundStyle(theme.inkSecondary)
                            .embossedText()
                    }
                    .padding(.top, 12)
                } else {
                    // The vote buttons sit outside the "did the text load"
                    // branch on purpose: a story whose page never loaded is
                    // often exactly the kind you want to downvote — site
                    // chrome, a paywall, a link roundup — and that signal is
                    // lost if the only way to give it is on stories that
                    // worked.
                    HStack(spacing: 10) {
                        Rectangle().fill(theme.rule).frame(height: 1)
                        RatingButton(isLit: model.isRated(story)) {
                            model.toggleRating(story)
                        }
                        .layoutPriority(1)
                        Rectangle().fill(theme.rule).frame(height: 1)
                    }

                    if let article {
                        if let imageURL = article.imageURL ?? story.imageURL,
                           let url = URL(string: imageURL) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFit()
                                        .saturation(0)
                                        .contrast(1.04)
                                        .overlay(theme.ink.opacity(0.08))
                                        .frame(maxWidth: 660, maxHeight: 360, alignment: .leading)
                                } else if phase.error != nil {
                                    EmptyView()
                                } else {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 120)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .padding(.vertical, 4)
                        }

                        Text(article.bodyText)
                        .font(ReaderTheme.serif(17))
                            .foregroundStyle(theme.ink)
                            .lineSpacing(7)
                            .textSelection(.enabled)
                            .embossedText()
                    } else {
                        Text("Couldn't load the full text for this story.")
                            .font(ReaderTheme.sans(13))
                            .foregroundStyle(theme.inkSecondary)
                            .embossedText()
                    }
                }

                if let url = URL(string: story.storyURL) {
                    Link(destination: url) {
                        Label("Read Original", systemImage: "arrow.up.right.square")
                    }
                    .font(ReaderTheme.sans(13, weight: .medium))
                    .padding(.top, 12)
                }

                if previousStory != nil || nextStory != nil {
                    HStack(alignment: .top, spacing: 16) {
                        ArticleNavigationButton(
                            title: previousStory.map { "← \($0.title)" } ?? "Previous",
                            isEnabled: previousStory != nil,
                            isLeading: true
                        ) {
                            model.showAdjacentStory(from: story, offset: -1)
                        }

                        Spacer(minLength: 0)

                        ArticleNavigationButton(
                            title: nextStory.map { "\($0.title) →" } ?? "Next",
                            isEnabled: nextStory != nil,
                            isLeading: false
                        ) {
                            model.showAdjacentStory(from: story, offset: 1)
                        }
                    }
                    .padding(.top, 24)
                }

                Color.clear
                    .frame(height: 1)
                    .id("bottom")
            }
            .padding(32)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onKeyPress { press in
                handleKeyPress(press, proxy: scrollProxy)
            }
            }
        }
        .background(theme.texturedPaper)
        .preferredColorScheme(.light)
        // Left empty rather than set to the story title: the header shows
        // its own composed title (wordmark + middot + article title) via
        // PermalinkBrandToolbarItem below, and a non-empty navigationTitle
        // here would have macOS draw its own plain-text title right next to
        // that — the two running together with no separator at all was
        // exactly the problem.
        .navigationTitle("")
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(theme.headerPaint, for: .windowToolbar)
        .toolbar {
            PermalinkBrandToolbarItem {
                model.goHome()
            }
            ToolbarItem(placement: .automatic) {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 24, height: 20)
                } else {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .foregroundStyle(theme.headerInk)
                    .disabled(model.sources.isEmpty)
                }
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    model.isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .foregroundStyle(theme.headerInk)
            }
        }
        .sheet(isPresented: $model.isShowingSettings) {
            SettingsView(model: model)
        }
        .onAppear {
            isFocused = true
            // Opening a story is what takes it off the Feed queue — the
            // permalink is the one place in the app that's unambiguously "you
            // read this."
            model.markRead(story)
        }
        .task {
            await loadArticle()
        }
    }

    private var previousStory: Story? {
        model.adjacentStory(to: story, offset: -1)
    }

    private var nextStory: Story? {
        model.adjacentStory(to: story, offset: 1)
    }

    /// j/k step to the next/previous story without returning to the list, x
    /// flips the bolt — the same key that rates the selected card on the feed,
    /// so rating is one key wherever you are — r toggles read/unread (opening
    /// the story already marked it read; this is for undoing that), and Esc or
    /// Backspace jumps straight back to the feed. A story's own page acts as a mini reading session rather than
    /// a one-off page you always have to go back to the list from.
    private func handleKeyPress(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            switch press.key {
            case .upArrow:
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("top", anchor: .top)
                }
                return .handled
            case .downArrow:
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                return .handled
            default:
                break
            }
        }

        switch press.characters {
        case "j":
            model.showAdjacentStory(from: story, offset: 1)
            return .handled
        case "k":
            model.showAdjacentStory(from: story, offset: -1)
            return .handled
        case "x":
            model.toggleRating(story)
            return .handled
        case "r":
            model.toggleRead(story)
            return .handled
        default:
            // Backspace reports as `.delete` (forward delete is
            // `.deleteForward`), but some keyboard layouts deliver it as the
            // raw control character with no key name attached, so both spellings
            // are accepted rather than trusting one.
            if press.key == .delete || press.key == .escape
                || press.characters == "\u{8}" || press.characters == "\u{7F}" {
                model.goBack()
                return .handled
            }
            return .ignored
        }
    }

    private func loadArticle() async {
        if let cached = model.article(for: story) {
            article = cached
            return
        }
        isLoadingArticle = true
        article = await model.loadArticle(for: story)
        isLoadingArticle = false
    }
}

private struct ArticleNavigationButton: View {
    let title: String
    let isEnabled: Bool
    let isLeading: Bool
    let action: () -> Void

    @Environment(\.readerTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ReaderTheme.serif(13, weight: .medium))
                .foregroundStyle(isEnabled ? theme.ink : theme.rule)
                .multilineTextAlignment(isLeading ? .leading : .trailing)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: isLeading ? .leading : .trailing)
                .embossedText()
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
