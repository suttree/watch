import AppKit
import SwiftUI

/// Transparent window artwork, tinted to match its surrounding controls.
struct WindowMark: View {
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
