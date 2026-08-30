import SwiftUI

/// The "Watch" wordmark in the window's title bar, doubling as a home link.
/// shared by the feed and permalink pages so the header looks identical on
/// both. macOS 26 draws a glass background capsule behind every toolbar item,
/// which around a bare wordmark reads as a stray bubble rather than a logo, so
/// there that shared background is hidden and the text sits directly on the
/// header tint.
struct BrandToolbarItem: ToolbarContent {
    let goHome: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            content.sharedBackgroundVisibility(.hidden)
        } else {
            content
        }
    }

    @ToolbarContentBuilder
    private var content: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            BackPill(isEnabled: false) {}
        }
        ToolbarItem(placement: .principal) {
            HomeCandleButton(action: goHome)
        }
    }
}

/// The permalink page's header: the active back link followed by Home. Built
/// as one toolbar item so the two labels read as a single navigation group.
struct PermalinkBrandToolbarItem: ToolbarContent {
    let goHome: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            content.sharedBackgroundVisibility(.hidden)
        } else {
            content
        }
    }

    @ToolbarContentBuilder
    private var content: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            BackPill(isEnabled: true, action: goHome)
        }
        ToolbarItem(placement: .principal) {
            HomeCandleButton(action: goHome)
        }
    }
}

private struct BackPill: View {
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.readerTheme) private var theme
    @State private var isHovering = false

    init(isEnabled: Bool, action: @escaping () -> Void) {
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: "chevron.left")
                .font(BrandTypeface.appFont(15, weight: .medium))
                .foregroundStyle(theme.headerInk.opacity(isHovering ? 0.46 : 0.78))
                .frame(width: 34, height: 28)
        }
        .buttonStyle(.plain)
        .background(Capsule().fill(Color.white.opacity(0.82)))
        .allowsHitTesting(isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Back")
    }
}

private struct HomeCandleButton: View {
    let action: () -> Void

    @Environment(\.readerTheme) private var theme
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            CandleMark(
                height: 40,
                opacity: isHovering ? 0.46 : 0.78,
                tint: theme.headerInk
            )
            .frame(width: 46, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovering = hovering }
        .help("Home")
    }
}
