import SwiftUI

/// The whole rating control, on both the feed rail and the permalink page: a
/// bolt that's either lit or not. Lit means the story counts as interesting —
/// because you said so, or because the ranker predicted it for you. Unlit
/// means it doesn't. Clicking flips it, which is the only rating gesture in
/// the app; there's no third "no opinion" state to land in by accident.
///
/// Named for the job rather than the glyph, so swapping the icon again
/// doesn't mean renaming everything that uses it.
struct RatingButton: View {
    let isLit: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.readerTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: isLit ? "bolt.fill" : "bolt")
                .font(BrandTypeface.appFont(16, weight: isLit ? .semibold : .regular))
                .foregroundStyle(color)
                .background(Circle().fill(theme.paper).frame(width: 14, height: 14))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovering ? 1.2 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { hovering in isHovering = hovering }
        .help(isLit ? "In your feed — click to drop it" : "Not in your feed — click to keep it")
    }

    private var color: Color {
        if isLit {
            return theme.ink
        }
        return isHovering ? theme.inkSecondary : theme.rule
    }
}
