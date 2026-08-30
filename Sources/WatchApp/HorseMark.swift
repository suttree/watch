import AppKit
import SwiftUI

/// The candle artwork used on the lock, loading, and empty-feed screens.
///
/// The source art is black ink on a white page. It's converted at build-prep
/// time into a template PNG whose alpha *is* the ink — white page dropped out,
/// stroke antialiasing preserved — which is what lets it take the theme's tint
/// here instead of arriving as a black rectangle.
struct CandleMark: View {
    var height: CGFloat
    var opacity: Double = 1
    var tint: Color?

    @Environment(\.readerTheme) private var theme

    /// Loaded once so decoding it per frame in the
    /// refresh screen's animation loop would be wasteful.
    static let artwork: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIconArtwork", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }()

    var body: some View {
        if let artwork = Self.artwork {
            Image(nsImage: artwork)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .foregroundStyle((tint ?? theme.inkSecondary).opacity(opacity))
        }
    }
}
