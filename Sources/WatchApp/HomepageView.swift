import WatchCore
import AppKit
import SwiftUI

struct HomepageView: View {
    @ObservedObject var model: WatchAppModel
    @Environment(\.readerTheme) private var theme

    @State private var currentPage = 0
    private let pageSize = 5

    /// Vim-style navigation on the current page — j/k move the selection down
    /// and up, scrolling the selected card into view, h/l page backwards and
    /// forwards, Space opens the selected card, x flips its bolt, and r marks
    /// it read without opening it.
    @State private var selectedStoryID: String?
    @State private var selectedAllSourceID: UUID?
    @FocusState private var isListFocused: Bool

    /// How far the top of the content sits from the top of the scroll view,
    /// plus the pull-to-refresh state derived from it.
    @State private var pullOffset: CGFloat = 0
    /// The ScrollView's own visible height, measured so the "Alles clear"
    /// empty state can center itself in it. `containerRelativeFrame` looked
    /// like the natural tool for this but rendered nothing at all in an
    /// isolated check — measuring the frame directly, the same way
    /// `pullOffset` below is measured, is the same technique already proven
    /// to work in this view.
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var isPullArmed = true
    private static let scrollSpace = "feed"
    /// The marker now sits at the very top of the content, so at rest it
    /// reports zero and a pull is simply how far past that it has been dragged.
    private static let contentInset: CGFloat = 0
    private static let pullTriggerDistance: CGFloat = 90
    private static let pullRearmDistance: CGFloat = 12

    private var filteredStories: [Story] {
        let stories = model.visibleStories(from: model.stories)
        guard model.feedMode == .all, let selectedAllSourceID else {
            return stories
        }
        return stories.filter { $0.sourceID == selectedAllSourceID }
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(filteredStories.count) / Double(pageSize))))
    }

    private var pagedStories: [Story] {
        let stories = filteredStories
        let start = currentPage * pageSize
        guard start < stories.count else {
            return []
        }
        let end = min(start + pageSize, stories.count)
        return Array(stories[start..<end])
    }

    private var selectedAllSource: TrackedSource? {
        guard let selectedAllSourceID else {
            return nil
        }
        return model.sources.first { $0.id == selectedAllSourceID }
    }

    var body: some View {
        GeometryReader { rootProxy in
            content(rootProxy: rootProxy)
        }
    }

    /// Split out from `body` only so the `GeometryReader` wrapping it reads
    /// cleanly — the reader's own closure is where `scrollViewportHeight`
    /// gets its value, since that turned out to be the reliable way to learn
    /// this view's own size. A `.background(GeometryReader { ... })` hung off
    /// the `ScrollView` itself — the more targeted-looking option — silently
    /// never updated in the running app, for reasons that didn't reproduce in
    /// isolation; reading the size this view was actually given by its parent
    /// is the standard, dependable version of the same idea.
    private func content(rootProxy: GeometryProxy) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    // Above the padding, deliberately. With the marker inside
                    // it, scrolling "to the top" meant scrolling *past* the
                    // page's own top margin — a position the animation had to
                    // overshoot the resting offset to reach, and kept landing
                    // short of when a pop or a page reset changed the layout
                    // mid-flight. Out here it's the content's true origin, so
                    // the target is offset zero and there is nothing to miss.
                    Color.clear
                        .frame(height: 1)
                        .id("top")
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: PullOffsetKey.self,
                                    value: geo.frame(in: .named(Self.scrollSpace)).minY
                                )
                            }
                        )

                VStack(alignment: .leading, spacing: 0) {

                    // Page 1 only: the filter is a way into the feed, not a
                    // control you need again once you're paging through it.
                    if currentPage == 0 {
                        FeedModeBar(mode: $model.feedMode)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.bottom, 20)
                    }

                    if let error = model.lastRefreshError {
                        Text(error)
                            .font(ReaderTheme.sans(13))
                            .foregroundStyle(.red)
                            .embossedText()
                            .padding(.bottom, 16)
                    }

                    if let status = model.refreshStatus {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(status)
                                .font(ReaderTheme.sans(13))
                                .foregroundStyle(theme.inkSecondary)
                                .embossedText()
                        }
                        .padding(.bottom, 16)
                    }

                    if model.sources.isEmpty {
                        emptyState
                    } else {
                        HStack(alignment: .top, spacing: 24) {
                                if model.feedMode == .all {
                                    AllSourceSidebar(
                                        sources: model.sources,
                                        selectedSourceID: selectedAllSourceID,
                                        select: { sourceID in
                                            selectedAllSourceID = sourceID
                                            currentPage = 0
                                            selectedStoryID = nil
                                            scrollToTop(scrollProxy)
                                        }
                                    )
                                    .frame(width: 150, alignment: .leading)
                                }

                                VStack(alignment: .leading, spacing: 0) {
                                    if model.feedMode == .all {
                                        Text(selectedAllSource?.url ?? "All sources")
                                            .font(ReaderTheme.serif(18, weight: .semibold))
                                            .foregroundStyle(theme.ink)
                                            .embossedText()
                                            .textSelection(.enabled)
                                            .padding(.bottom, 16)
                                    }

                                    if model.stories.isEmpty, !model.isRefreshing {
                                        Text("No bookmarks yet. Add videos to Firefox's tv folder, then refresh.")
                                            .font(ReaderTheme.sans(14))
                                            .foregroundStyle(theme.inkSecondary)
                                            .embossedText()
                                    } else if filteredStories.isEmpty, model.feedMode == .feed {
                                        allClearState
                                    } else if filteredStories.isEmpty {
                                        Text("No stories from this source yet.")
                                            .font(ReaderTheme.sans(14))
                                            .foregroundStyle(theme.inkSecondary)
                                            .embossedText()
                                    } else {
                                        if currentPage > 0 {
                                            paginationControls(proxy: scrollProxy)
                                                .padding(.bottom, 20)
                                        }

                                        VStack(spacing: 0) {
                                            ForEach(pagedStories) { story in
                                                StoryRow(
                                                    story: story,
                                                    isEnriching: story.excerpt == nil && model.isRefreshing,
                                                    isSelected: story.id == selectedStoryID,
                                                    isRated: model.isRated(story),
                                                    isRead: model.isRead(story),
                                                    select: { model.openStory(story) },
                                                    toggleRating: { model.toggleRating(story) }
                                                )
                                                .id(story.id)
                                            }
                                        }

                                        if filteredStories.count > pageSize {
                                            paginationControls(proxy: scrollProxy)
                                                .padding(.top, 20)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 32)
                .padding(.top, 12)
                .padding(.bottom, 32)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                }
            }
            .coordinateSpace(name: Self.scrollSpace)
            .onPreferenceChange(PullOffsetKey.self) { offset in
                pullOffset = offset
            }
            .onChange(of: pullOffset) {
                handlePull()
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isListFocused)
            .onKeyPress { press in
                handleKeyPress(press, proxy: scrollProxy)
            }
            .onAppear {
                isListFocused = true
            }
            .onChange(of: currentPage) {
                selectedStoryID = nil
                scrollToTop(scrollProxy)
            }
            .onChange(of: model.homeRequestID) {
                currentPage = 0
                selectedStoryID = nil
                scrollToTop(scrollProxy)
            }
            .onChange(of: model.feedMode) {
                currentPage = 0
                selectedStoryID = nil
                if model.feedMode == .feed {
                    selectedAllSourceID = nil
                }
                scrollToTop(scrollProxy)
            }
        }
        .background(theme.texturedPaper)
        .preferredColorScheme(.light)
        .navigationTitle("")
        .toolbarBackground(theme.headerPaint, for: .windowToolbar)
        .onAppear {
            scrollViewportHeight = rootProxy.size.height
        }
        .onChange(of: rootProxy.size.height) {
            scrollViewportHeight = rootProxy.size.height
        }
        .onChange(of: model.isRefreshing) {
            if model.isRefreshing {
                currentPage = 0
                selectedStoryID = nil
            }
        }
        .toolbar {
            BrandToolbarItem { model.goHome() }
            ToolbarItem(placement: .automatic) {
                if model.isRefreshing {
                    // Sized to the refresh button it stands in for, so the
                    // toolbar doesn't close up around it and leave the spinner
                    // crowding the gear next to it.
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
        .task {
            if model.stories.isEmpty {
                await model.refresh()
            }
        }
    }

    /// Drag the top of page 1 down far enough and the refresh fires — macOS
    /// has no built-in pull-to-refresh, so this watches how far the content
    /// has been pulled past its resting offset by the scroll view's rubber
    /// banding. `isPullArmed` keeps one long drag from firing repeatedly: it
    /// only rearms once the content has sprung back near the top.
    private func handlePull() {
        let pull = pullOffset - Self.contentInset
        if pull < Self.pullRearmDistance {
            isPullArmed = true
        }
        guard isPullArmed,
              pull > Self.pullTriggerDistance,
              currentPage == 0,
              !model.isRefreshing,
              !model.sources.isEmpty else {
            return
        }
        isPullArmed = false
        Task { await model.refresh() }
    }

    private func handleKeyPress(_ press: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        if press.modifiers.contains(.command) {
            switch press.key {
            case .upArrow:
                scrollToTop(proxy)
                return .handled
            case .downArrow:
                scrollToBottom(proxy)
                return .handled
            default:
                break
            }
        }

        guard !pagedStories.isEmpty else {
            return .ignored
        }
        switch press.characters {
        case "j":
            moveSelection(by: 1, proxy: proxy)
            return .handled
        case "k":
            moveSelection(by: -1, proxy: proxy)
            return .handled
        case " ":
            openSelectedStory()
            return .handled
        case "x":
            if let story = selectedStory {
                model.toggleRating(story)
            }
            return .handled
        case "r":
            markSelectedRead()
            return .handled
        case "h":
            changePage(to: currentPage - 1)
            return .handled
        case "l":
            changePage(to: currentPage + 1)
            return .handled
        default:
            // Return arrives as a character rather than a name, so it can't
            // be matched alongside the letters above.
            if press.key == .return {
                openSelectedStory()
                return .handled
            }
            return .ignored
        }
    }

    private func openSelectedStory() {
        guard let story = selectedStory else {
            return
        }
        model.openStory(story)
    }

    /// Both the Previous/Next buttons and h/l come through here, so paging
    /// always lands at the top of the new page rather than leaving you halfway
    /// down it at whatever offset the previous page was scrolled to.
    private func changePage(to page: Int) {
        let clamped = min(max(page, 0), pageCount - 1)
        guard clamped != currentPage else {
            return
        }
        currentPage = clamped
    }

    /// Deferred a runloop pass: the new page's rows are still being built when
    /// the page changes, and scrolling into content mid-rebuild lands at an
    /// arbitrary offset — or nowhere at all, which is what clicking Next at the
    /// bottom of a page used to do.
    ///
    /// Then snapped again once the animation has run. Every caller here also
    /// changes what the page contains — resetting to page 1 brings the
    /// Feed/All bar back, which grows the content above the fold while the
    /// scroll is still animating towards a position measured before it
    /// appeared. The result was a scroll that stopped a little short of the
    /// top every time. The second call costs nothing when the first one
    /// already landed.
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("top", anchor: .top)
            }
            try? await Task.sleep(for: .milliseconds(260))
            proxy.scrollTo("top", anchor: .top)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private var selectedStory: Story? {
        pagedStories.first { $0.id == selectedStoryID }
    }

    /// Marks the selected story read and slides the selection onto whatever
    /// takes its place. In Feed that story drops out of the list immediately
    /// — "r, r, r" walks down the page clearing it — so the selection has to
    /// move onto the next story rather than following the one that just
    /// vanished.
    private func markSelectedRead() {
        guard let story = selectedStory else {
            return
        }
        let index = pagedStories.firstIndex { $0.id == story.id }
        model.markRead(story)

        if currentPage >= pageCount {
            currentPage = max(0, pageCount - 1)
        }
        let remaining = pagedStories
        guard let index, !remaining.isEmpty else {
            selectedStoryID = remaining.first?.id
            return
        }
        selectedStoryID = remaining[min(index, remaining.count - 1)].id
    }

    private func moveSelection(by delta: Int, proxy: ScrollViewProxy) {
        let ids = pagedStories.map(\.id)
        guard !ids.isEmpty else {
            return
        }
        let currentIndex = selectedStoryID.flatMap { ids.firstIndex(of: $0) } ?? -1
        let newIndex = min(max(currentIndex + delta, 0), ids.count - 1)
        selectedStoryID = ids[newIndex]
        withAnimation {
            proxy.scrollTo(ids[newIndex], anchor: .center)
        }
    }

    private func paginationControls(proxy: ScrollViewProxy) -> some View {
        HStack {
            PaginationButton(title: "Previous", systemImage: "chevron.left", iconLeading: true, isDisabled: currentPage == 0) {
                changePage(to: currentPage - 1)
            }

            Spacer()

            Text("Page \(currentPage + 1) of \(pageCount)")
                .font(ReaderTheme.sans(12, weight: .medium))
                .foregroundStyle(theme.inkSecondary)
                .embossedText()

            Spacer()

            PaginationButton(title: "Next", systemImage: "chevron.right", iconLeading: false, isDisabled: currentPage >= pageCount - 1) {
                changePage(to: currentPage + 1)
            }
        }
        .padding(.top, 20)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing tracked yet")
                .font(ReaderTheme.serif(20, weight: .semibold))
                .foregroundStyle(theme.ink)
                .embossedText()
            Text("Add a few sites in Settings and Watch will find the videos hiding in them.")
                .font(ReaderTheme.sans(14))
                .foregroundStyle(theme.inkSecondary)
                .embossedText()
            Button("Open Settings") {
                model.isShowingSettings = true
            }
            .padding(.top, 4)
        }
        .padding(.top, 40)
    }

    /// What an empty Feed looks like — everything's either read or hasn't
    /// earned its place, and either way there's nothing to hand you, which
    /// isn't a problem to explain so much as a good place to land. The horse
    /// stands in the same spot it does on the lock and loading screens, so an
    /// empty feed reads as a quiet moment rather than a dead end.
    /// Everything around this view's own box that also eats into
    /// `scrollViewportHeight`: 10pt top padding on the content column, the
    /// Feed/All pill itself (13pt semibold text at roughly a 16pt line
    /// height, plus 5pt top/bottom padding), 20pt padding below the pill, and
    /// the 28pt bottom padding the whole content column carries regardless of
    /// which branch is showing. Missing that last one the first time through
    /// is exactly what left a sliver of unnecessary scroll room below an
    /// otherwise-correctly-centered block. Computed rather than measured at
    /// runtime — two attempts at measuring pieces of this dynamically (the
    /// ScrollView's own frame via `.background`, then the tab bar's via the
    /// same technique that already works for `pullOffset` in this file) both
    /// failed to visibly take effect for reasons that didn't reproduce in
    /// isolation, so this trades "adapts to a future layout change
    /// automatically" for "reliably correct against the layout as it exists."
    /// The trailing `+ 6` is a deliberate small over-subtraction: landing a
    /// touch short of the viewport is invisible, landing even a pixel over it
    /// draws a scrollbar (as the unpadded sum did), so the constant is biased
    /// toward the side with no visible cost.
    private static let allClearChromeFootprint: CGFloat = 10 + 26 + 20 + 28 + 6

    private var allClearState: some View {
        VStack(spacing: 14) {
                            CandleMark(height: 58, opacity: 0.5)
            LetterpressText("Alles klar", size: 30)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: max(scrollViewportHeight - Self.allClearChromeFootprint, 0)
        )
    }
}

/// Text stamped into the paper rather than printed on it — the classic
/// letterpress trick of a highlight below and a shadow above on type coloured
/// to all but disappear into the background, so only the impression shows.
/// Reserved for a single calm word or two; at body-text sizes the missing
/// contrast would just read as illegible.
private struct LetterpressText: View {
    let text: String
    let size: CGFloat

    @Environment(\.readerTheme) private var theme

    init(_ text: String, size: CGFloat) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(ReaderTheme.serif(size, weight: .bold))
            // A plain light grey rather than the theme's own tones — this is
            // one calm, colour-neutral moment rather than another surface
            // that follows the palette. Still embossed on top: the shadow
            // pair below is what does the "pressed into the paper" work,
            // independent of whatever the letters are filled with.
            .foregroundStyle(Color(white: 0.75))
            .shadow(color: .white.opacity(0.8), radius: 0.5, x: 0, y: 1.5)
            .shadow(color: theme.ink.opacity(0.28), radius: 0.5, x: 0, y: -1)
    }
}

/// One entry in the news "river" — a node on a connecting rail down the left
/// edge, the story itself, and the bolt on the rail that trains the ranker on
/// what you like.
private struct StoryRow: View {
    let story: Story
    let isEnriching: Bool
    let isSelected: Bool
    let isRated: Bool
    let isRead: Bool
    let select: () -> Void
    let toggleRating: () -> Void

    @Environment(\.readerTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TimelineRail(isRated: isRated, toggleRating: toggleRating)
                .frame(width: 26)

            // Only the headline is the link. The excerpt is there to be read
            // in place, and making the whole card clickable meant every stray
            // click while reading one navigated away from the feed.
            VStack(alignment: .leading, spacing: 7) {
                Text(story.sourceName.uppercased())
                    .font(ReaderTheme.sans(11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(theme.inkSecondary)
                    .embossedText()

                if let video = story.video {
                    if let address = story.imageURL, let url = URL(string: address) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Rectangle().fill(theme.paperInset).overlay(Image(systemName: "play.rectangle"))
                        }
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onTapGesture(perform: select)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("VIDEO")
                        if let duration = video.durationLabel { Text(duration) }
                    }
                    .font(ReaderTheme.sans(10, weight: .semibold))
                    .foregroundStyle(theme.headerInk)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(theme.headerTint.opacity(0.45), in: Capsule())
                }

                Button(action: select) {
                    Text(story.title)
                        .font(ReaderTheme.serif(19, weight: .semibold))
                        .foregroundStyle(theme.ink)
                        .embossedText()
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                // Only visible in All — Feed drops a read story rather than
                // showing it — where it answers "have I seen this" without
                // needing its own tab to do it.
                .opacity(isRead ? 0.55 : 1)

                if let excerpt = story.excerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(ReaderTheme.serif(15))
                        .foregroundStyle(theme.inkSecondary)
                        .embossedText()
                        .multilineTextAlignment(.leading)
                        .lineLimit(12)
                        .lineSpacing(4)
                } else if isEnriching {
                    HStack(spacing: 8) {
                        RefinedLoader()
                        Text("Loading…")
                            .font(ReaderTheme.sans(11, weight: .medium))
                            .foregroundStyle(theme.inkSecondary)
                            .embossedText()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .background(isSelected ? theme.paperInset : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Each row draws its own line segment spanning its own full height; since
/// rows stack with no spacing between them, the segments join into one
/// continuous rail down the whole list without any cross-row coordination.
/// The bolt sits directly on the rail, in place of a plain node dot, so
/// rating reads as part of the same "stream" rather than a separate control
/// bolted onto the side.
private struct TimelineRail: View {
    let isRated: Bool
    let toggleRating: () -> Void

    @Environment(\.readerTheme) private var theme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.rule)
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            RatingButton(isLit: isRated) {
                toggleRating()
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct AllSourceSidebar: View {
    let sources: [TrackedSource]
    let selectedSourceID: UUID?
    let select: (UUID?) -> Void

    @Environment(\.readerTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources")
                .font(ReaderTheme.serif(16, weight: .semibold))
                .foregroundStyle(theme.ink)
                .embossedText()
                .padding(.bottom, 6)

            SourceFilterButton(title: "All sources", isSelected: selectedSourceID == nil) {
                select(nil)
            }

            ForEach(sources.sorted { lhs, rhs in
                displayName(for: lhs).localizedStandardCompare(displayName(for: rhs)) == .orderedAscending
            }) { source in
                SourceFilterButton(
                    title: displayName(for: source),
                    isSelected: selectedSourceID == source.id
                ) {
                    select(source.id)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private func displayName(for source: TrackedSource) -> String {
        if !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return source.name
        }
        guard let host = URL(string: source.url)?.host else {
            return source.url
        }
        return host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
    }
}

private struct SourceFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.readerTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ReaderTheme.sans(12, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.ink : theme.inkSecondary)
                .embossedText()
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(isSelected ? theme.paperInset : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}

/// Feed / All — two views onto the same `model.stories`, so switching between
/// them is instant and never needs a refetch. Feed is the ranked
/// recommendation stream with read stories dropped; All is the plain list.
private struct FeedModeBar: View {
    @Binding var mode: WatchAppModel.FeedMode
    @Environment(\.readerTheme) private var theme

    private let options: [(WatchAppModel.FeedMode, String)] = [
        (.feed, "Videos"), (.all, "All")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { option, title in
                Button {
                    mode = option
                } label: {
                    Text(title)
                        .font(ReaderTheme.sans(12, weight: .semibold))
                        .foregroundStyle(mode == option ? theme.ink : theme.inkSecondary)
                        .embossedText()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(mode == option ? theme.paperInset : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .help(title)
            }
        }
    }
}

private struct PaginationButton: View {
    let title: String
    let systemImage: String
    let iconLeading: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.readerTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if iconLeading {
                    Image(systemName: systemImage)
                }
                Text(title)
                if !iconLeading {
                    Image(systemName: systemImage)
                }
            }
            .font(ReaderTheme.sans(12, weight: .medium))
            .embossedText()
            .foregroundStyle(isDisabled ? theme.rule : (isHovering ? theme.inkSecondary : theme.ink))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isHovering && !isDisabled ? theme.paperInset : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.1), value: isHovering)
    }
}

/// A calm, minimal loading indicator — three small dots pulsing in
/// sequence — in place of the earlier blocky pixel-grid animation.
private struct RefinedLoader: View {
    @State private var activeIndex = 0
    @Environment(\.readerTheme) private var theme

    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(theme.inkSecondary)
                    .frame(width: 4, height: 4)
                    .opacity(index == activeIndex ? 0.9 : 0.25)
            }
        }
        .onReceive(timer) { _ in
            activeIndex = (activeIndex + 1) % 3
        }
    }
}

/// Reports how far the top of the feed has been dragged past its resting
/// position, which is the whole of the pull-to-refresh gesture on macOS.
private struct PullOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
