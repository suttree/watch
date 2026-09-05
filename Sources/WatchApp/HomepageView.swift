import AppKit
import SwiftUI
import WatchCore

struct HomepageView: View {
    @ObservedObject var model: WatchAppModel
    @Environment(\.readerTheme) private var theme
    @State private var currentPage = 0
    @State private var selectedStoryID: String?
    @State private var activeVideoID: String?
    @State private var pullArmed = true
    @FocusState private var listFocused: Bool
    private let pageSize = 5

    private var filteredStories: [Story] { model.visibleStories(from: model.stories) }
    private var pageCount: Int { max(1, (filteredStories.count + pageSize - 1) / pageSize) }
    private var page: [Story] {
        Array(filteredStories.dropFirst(currentPage * pageSize).prefix(pageSize))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Color.clear.frame(height: 1).id("top")
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: PullOffsetKey.self,
                                value: geometry.frame(in: .named("feed")).minY)
                        })

                    HStack(spacing: 6) {
                        ForEach(BookmarkFeedMode.allCases, id: \.self) { mode in
                            Button(mode.title) { model.feedMode = mode }
                                .buttonStyle(.plain)
                                .font(ReaderTheme.sans(13, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(model.feedMode == mode ? theme.paperInset : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                                .accessibilityAddTraits(model.feedMode == mode ? [.isSelected] : [])
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if let error = model.lastRefreshError {
                        Text(error).foregroundStyle(.red).font(ReaderTheme.sans(13))
                    }
                    if let status = model.refreshStatus {
                        HStack { ProgressView().controlSize(.small); Text(status) }
                            .font(ReaderTheme.sans(13))
                    }
                    if filteredStories.isEmpty, !model.isRefreshing {
                        Text(model.feedMode == .youtube
                             ? "No YouTube videos in your Firefox tv folder."
                             : "No other bookmarks in your Firefox tv folder.")
                            .foregroundStyle(theme.inkSecondary)
                            .padding(.vertical, 40)
                    } else {
                        if pageCount > 1 { pagination(proxy) }
                        VStack(spacing: 24) {
                            ForEach(page) { story in
                                FeedBookmarkRow(
                                    story: story,
                                    isSelected: story.id == selectedStoryID,
                                    isActive: story.id == activeVideoID,
                                    activate: { activate(story) },
                                    playbackChanged: { playing in
                                        if activeVideoID == story.id { model.setVideoPlaying(playing) }
                                    }
                                )
                                .id(story.id)
                            }
                        }
                        if pageCount > 1 { pagination(proxy) }
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 32)
                .frame(maxWidth: 780).frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "feed")
            .onPreferenceChange(PullOffsetKey.self) { offset in
                if offset < 12 { pullArmed = true }
                if offset > 90, pullArmed, !model.isRefreshing {
                    pullArmed = false
                    Task { await model.refresh() }
                }
            }
            .focusable().focusEffectDisabled().focused($listFocused)
            .onKeyPress { press in
                // Let a focused player handle its own playback shortcuts.
                guard listFocused else { return .ignored }
                switch press.characters {
                case "j", "k":
                    let index = page.firstIndex { $0.id == selectedStoryID } ?? -1
                    let next = max(0, min(page.count - 1, index + (press.characters == "j" ? 1 : -1)))
                    guard page.indices.contains(next) else { return .ignored }
                    selectedStoryID = page[next].id
                    withAnimation { proxy.scrollTo(page[next].id, anchor: .top) }
                    return .handled
                case "h": changePage(currentPage - 1, proxy); return .handled
                case "l": changePage(currentPage + 1, proxy); return .handled
                case " ":
                    if let story = page.first(where: { $0.id == selectedStoryID }) { activate(story) }
                    return .handled
                default:
                    if press.key == .return,
                       let story = page.first(where: { $0.id == selectedStoryID }) {
                        activate(story)
                        return .handled
                    }
                    return .ignored
                }
            }
            .onChange(of: model.feedMode) { reset(proxy) }
            .onChange(of: model.homeRequestID) { reset(proxy) }
        }
        .foregroundStyle(theme.ink)
        .background(theme.texturedPaper)
        .preferredColorScheme(.light)
        .navigationTitle("")
        .toolbarBackground(theme.headerPaint, for: .windowToolbar)
        .toolbar {
            BrandToolbarItem { model.goHome() }
            ToolbarItem {
                Button { Task { await model.refresh() } } label: {
                    Label("Refresh bookmarks", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)
            }
            ToolbarItem {
                Button { model.isShowingSettings = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $model.isShowingSettings) { SettingsView(model: model) }
        .onAppear { listFocused = true }
        .onDisappear { stopPlayback() }
        .task { if model.stories.isEmpty { await model.refresh() } }
    }

    private func activate(_ story: Story) {
        selectedStoryID = story.id
        guard let url = URL(string: story.storyURL) else { return }
        if YouTubeVideo(url: url) != nil {
            if activeVideoID != story.id {
                stopPlayback()
                activeVideoID = story.id
            }
        } else { NSWorkspace.shared.open(url) }
    }

    private func stopPlayback() {
        activeVideoID = nil
        model.setVideoPlaying(false)
    }

    private func reset(_ proxy: ScrollViewProxy) {
        stopPlayback()
        currentPage = 0
        selectedStoryID = nil
        proxy.scrollTo("top", anchor: .top)
    }

    private func changePage(_ number: Int, _ proxy: ScrollViewProxy) {
        let next = min(max(number, 0), pageCount - 1)
        guard next != currentPage else { return }
        stopPlayback()
        currentPage = next
        selectedStoryID = nil
        proxy.scrollTo("top", anchor: .top)
    }

    private func pagination(_ proxy: ScrollViewProxy) -> some View {
        HStack {
            Button("Previous") { changePage(currentPage - 1, proxy) }.disabled(currentPage == 0)
            Spacer()
            Text("Page \(currentPage + 1) of \(pageCount)").font(ReaderTheme.sans(12))
            Spacer()
            Button("Next") { changePage(currentPage + 1, proxy) }.disabled(currentPage + 1 >= pageCount)
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.inkSecondary)
    }
}

private struct FeedBookmarkRow: View {
    let story: Story
    let isSelected: Bool
    let isActive: Bool
    let activate: () -> Void
    let playbackChanged: (Bool) -> Void
    @Environment(\.readerTheme) private var theme
    @State private var playbackError: String?

    private var url: URL? { URL(string: story.storyURL) }
    private var video: YouTubeVideo? { url.flatMap(YouTubeVideo.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: activate) {
                    Text(story.title)
                        .font(ReaderTheme.serif(19, weight: .semibold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help(video == nil ? "Open original" : "Play here")

                if let url {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 15))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open original: \(story.title)")
                    .help("Open original")
                }
            }

            if let video {
                if isActive {
                    BookmarkVideoPlayer(video: video, autoplay: true,
                                        playbackChanged: playbackChanged,
                                        failed: { playbackError = $0 })
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(minHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Button(action: activate) {
                        Color.black
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .overlay {
                                AsyncImage(url: URL(string: video.thumbnailURL)) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: { Color.black }
                            }
                            .clipped()
                            .overlay {
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 58))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 6)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play \(story.title)")
                }
                if isActive, let playbackError {
                    Text(playbackError).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(url?.host ?? story.sourceName)
                    .font(ReaderTheme.sans(12)).foregroundStyle(theme.inkSecondary)
            }

            Rectangle().fill(theme.rule).frame(height: 1).padding(.top, 12)
        }
        .padding(8)
        .background(isSelected ? theme.paperInset : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .onChange(of: isActive) { playbackError = nil }
    }
}

private struct PullOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
