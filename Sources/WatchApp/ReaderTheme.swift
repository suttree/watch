import AppKit
import SwiftUI

struct EmbossedTextModifier: ViewModifier {
    @Environment(\.readerTheme) private var theme

    func body(content: Content) -> some View {
        content
            .shadow(color: .white.opacity(0.7), radius: 0.5, x: 0, y: -1)
            .shadow(color: theme.ink.opacity(0.3), radius: 0.6, x: 0, y: 1)
    }
}

extension View {
    func embossedText() -> some View {
        modifier(EmbossedTextModifier())
    }
}

/// One colour from a palette, kept as plain components rather than a `Color`
/// or an `NSColor` so it can be handed to SwiftUI and AppKit alike, and blended
/// without round-tripping through either one's colour space.
struct ThemeColor: Hashable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    static let white = ThemeColor(1, 1, 1)
    static let black = ThemeColor(0, 0, 0)

    var color: Color { Color(red: red, green: green, blue: blue) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }

    /// Rec. 709 luma — enough to judge what will read against what.
    var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }

    func mixed(with other: ThemeColor, amount: Double) -> ThemeColor {
        let t = min(max(amount, 0), 1)
        return ThemeColor(
            red + (other.red - red) * t,
            green + (other.green - green) * t,
            blue + (other.blue - blue) * t
        )
    }

    func lightened(_ amount: Double) -> ThemeColor { mixed(with: .white, amount: amount) }
    func darkened(_ amount: Double) -> ThemeColor { mixed(with: .black, amount: amount) }

    /// The same hue at a given lightness. Mixing linearly towards white or
    /// black scales luminance predictably, which is what lets every palette —
    /// a near-black green as readily as a pale yellow — produce surfaces of
    /// comparable contrast without hand-tuning each one.
    func normalized(toLuminance target: Double) -> ThemeColor {
        let current = luminance
        guard current > 0.001 else {
            return ThemeColor(target, target, target)
        }
        if current < target {
            return mixed(with: .white, amount: (target - current) / (1 - current))
        }
        return mixed(with: .black, amount: 1 - target / current)
    }
}

/// A named palette, carried over from the host app so the two read as siblings.
///
/// A theme is authored as nothing but a ramp of signature colours, ordered
/// light to dark. Every surface Read paints — paper, rules, the header tint,
/// the ink — is derived from that ramp rather than specified per theme, which
/// is what keeps a table this long consistent: no palette can accidentally
/// ship unreadable body text, and adding one means picking colours, not
/// re-deciding what a background should be.
///
/// The ramp itself only appears at full strength on the app icon. Read is for
/// reading, so the window stays pale whatever the theme; a dark palette shows
/// up as a tinted header and a coloured icon, not as dark paper.
struct ReaderTheme: Identifiable, Hashable {
    let id: String
    let title: String
    let accents: [ThemeColor]

    /// How the ramp is actually painted on the icon and the header bar. Most
    /// palettes are diagonal bands, which is the default when none is given;
    /// the rest carry the same style host gives them, down to the seed, so a
    /// theme's artwork is recognisably the same in both apps.
    private let explicitStyle: ThemePatternStyle?
    /// Scattered stars over the pattern, for the night-sky palettes.
    let starSeed: UInt64?

    init(id: String, title: String, accents: [ThemeColor], style: ThemePatternStyle? = nil, starSeed: UInt64? = nil) {
        self.id = id
        self.title = title
        self.accents = accents
        self.explicitStyle = style
        self.starSeed = starSeed
    }

    var style: ThemePatternStyle {
        explicitStyle ?? .stripes(accents.map(\.nsColor))
    }

    /// App icons use the palette midpoint as a soft pastel background, with
    /// the same restrained polka-dot texture as the reading surface.
    var iconStyle: ThemePatternStyle {
        return .finePolkaDots(
            background: iconBackground.nsColor,
            dots: [iconBackground.darkened(0.28).nsColor.withAlphaComponent(0.28)]
        )
    }

    /// A lightened midpoint keeps each theme recognisable while retaining
    /// enough colour for the icon's white inset border to show.
    var iconBackground: ThemeColor {
        midTone.lightened(0.68)
    }

    /// What the title bar gets, which is not always what the icon gets.
    ///
    /// The palettes with real pattern — waves, diamonds, packed circles, a
    /// mesh — keep it there: it's what makes them those themes. What doesn't
    /// survive the trip is a ramp of colour. Diagonal bands read as one
    /// graphic at icon size and as a row of hard-edged blocks stretched across
    /// a title bar, and a gradient becomes a smear, so those palettes get a
    /// single flat colour instead: the palette's own signature tone, taken as
    /// authored rather than normalised, which is what lets Silver stay pale
    /// and Galaxy stay dark enough to carry its stars.
    var headerStyle: ThemePatternStyle {
        switch style {
        case .stripes, .gradient, .radial:
            return .solid(signature.nsColor)
        default:
            return style
        }
    }

    /// Stars stay: on a flat colour dark enough to carry them, they're the
    /// whole point of Galaxy and Starry Night.
    var headerStarSeed: UInt64? { starSeed }

    static func == (lhs: ReaderTheme, rhs: ReaderTheme) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Derived surfaces

    /// The middle of the ramp, where a palette is most itself rather than
    /// washed out at one end or nearly black at the other.
    private var signature: ThemeColor {
        accents[accents.count / 2]
    }

    /// The signature pulled to a common lightness, so themes differ in hue
    /// here and not in how dark they land.
    private var midTone: ThemeColor {
        signature.normalized(toLuminance: 0.5)
    }

    private var inkColor: ThemeColor {
        let darkest = accents.min { $0.luminance < $1.luminance } ?? signature
        guard darkest.luminance > 0.16 else {
            return darkest
        }
        return darkest.darkened(1 - 0.16 / darkest.luminance)
    }

    var paper: Color { midTone.lightened(0.88).color }
    var paperInset: Color { midTone.lightened(0.95).color }
    var rule: Color { midTone.lightened(0.58).color }

    /// The window title bar — the one piece of chrome that wears the theme at
    /// something like full strength, kept light enough that the dark wordmark
    /// and the system toolbar glyphs still read on it.
    var headerTint: Color { midTone.lightened(0.55).color }

    /// The title bar wearing the theme's actual artwork rather than a flat
    /// tint — stripes as stripes, waves as waves. `ImagePaint` is what lets a
    /// rendered pattern stand in for a colour anywhere a ShapeStyle is asked
    /// for, `.toolbarBackground` included.
    @MainActor
    var headerPaint: ImagePaint {
        ImagePaint(image: Image(nsImage: headerImage()), scale: 1)
    }

    /// What to write on the title bar. The themes that paint it darkest —
    /// Galaxy, Hacker, Harlequin — would otherwise put near-black ink on a
    /// near-black band. Measured off the rendered artwork rather than guessed
    /// from the palette, since a style like Sea Foam is mostly its pale
    /// background while Water is mostly its dark one.
    @MainActor
    var headerInk: Color {
        ThemeArtwork.headerIsDark(self) ? .white : ink
    }

    var ink: Color { inkColor.color }
    var inkSecondary: Color { inkColor.mixed(with: midTone.lightened(0.88), amount: 0.45).color }

    /// Paper plus a faint tiled polka-dot texture — the same 4×4-unit,
    /// two-dot repeating pattern used as the background on duncangough.com
    /// (a small SVG data URI there), redrawn here tinted to each theme's ink
    /// tone rather than the site's fixed purple-grey.
    var texturedPaper: some View {
        paper.overlay(PolkaDotTexture(color: inkSecondary.opacity(0.06)))
    }

    // MARK: - Icon

    /// The app icon, and the strip of artwork behind the window's title bar.
    /// Both are cached: the patterns are seeded scatter fields that cost real
    /// work to draw, and the header is asked for on every view update.
    @MainActor
    func iconImage(size: CGFloat = 512) -> NSImage {
        ThemeArtwork.icon(self, size: size)
    }

    @MainActor
    func headerImage(width: CGFloat = 1600, height: CGFloat = 52) -> NSImage {
        ThemeArtwork.header(self, width: width, height: height)
    }

    /// Line art over the bands wants whichever of white or the theme's own ink
    /// stands out against most of the ramp.
    var iconArtworkTint: NSColor {
        return .black
    }

    // MARK: - Type

    /// +1pt over whatever size is asked for, applied here once rather than
    /// at every call site, so the whole app's type scale can move together.
    private static let sizeBump: CGFloat = 1

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BrandTypeface.appFont(size + sizeBump, weight: weight)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        BrandTypeface.appFont(size + sizeBump, weight: weight)
    }

    // MARK: - The palettes

    static func named(_ id: String?) -> ReaderTheme {
        all.first { $0.id == id } ?? standard
    }

    static var standard: ReaderTheme { all[0] }

    static let all: [ReaderTheme] = [
        ReaderTheme(id: "default", title: "Default", accents: [
            ThemeColor(0.97, 0.97, 0.97), ThemeColor(0.90, 0.90, 0.91), ThemeColor(0.80, 0.80, 0.82),
            ThemeColor(0.66, 0.66, 0.69), ThemeColor(0.50, 0.50, 0.53), ThemeColor(0.34, 0.34, 0.36),
            ThemeColor(0.18, 0.18, 0.19),
        ]),
        ReaderTheme(id: "sunset", title: "Sunset", accents: [
            ThemeColor(1.00, 0.98, 0.78), ThemeColor(1.00, 0.88, 0.40), ThemeColor(1.00, 0.76, 0.03),
            ThemeColor(1.00, 0.60, 0.00), ThemeColor(1.00, 0.44, 0.00), ThemeColor(0.90, 0.29, 0.10),
            ThemeColor(0.75, 0.21, 0.05),
        ]),
        ReaderTheme(id: "sunrise", title: "Sunrise", accents: [
            ThemeColor(0.98, 0.92, 0.68), ThemeColor(1.00, 0.79, 0.42), ThemeColor(0.98, 0.52, 0.34),
            ThemeColor(0.76, 0.30, 0.45), ThemeColor(0.24, 0.18, 0.45),
        ], style: .gradient([ThemeColor(0.24, 0.18, 0.45).nsColor, ThemeColor(0.76, 0.30, 0.45).nsColor, ThemeColor(0.98, 0.52, 0.34).nsColor, ThemeColor(1.00, 0.79, 0.42).nsColor, ThemeColor(0.98, 0.92, 0.68).nsColor])),
        ReaderTheme(id: "hot-pink", title: "Hot Pink", accents: [
            ThemeColor(1.00, 0.76, 0.89), ThemeColor(1.00, 0.40, 0.73), ThemeColor(1.00, 0.18, 0.66),
            ThemeColor(1.00, 0.08, 0.56), ThemeColor(0.91, 0.00, 0.48), ThemeColor(0.72, 0.00, 0.40),
        ]),
        ReaderTheme(id: "rainbow", title: "Rainbow", accents: [
            ThemeColor(0.93, 0.11, 0.14), ThemeColor(1.00, 0.50, 0.15), ThemeColor(1.00, 0.95, 0.00),
            ThemeColor(0.13, 0.69, 0.30), ThemeColor(0.00, 0.64, 0.91), ThemeColor(0.25, 0.28, 0.80),
            ThemeColor(0.64, 0.29, 0.64),
        ]),
        ReaderTheme(id: "meadow", title: "Meadow", accents: [
            ThemeColor(0.95, 0.98, 0.87), ThemeColor(0.86, 0.95, 0.69), ThemeColor(0.71, 0.88, 0.48),
            ThemeColor(0.50, 0.79, 0.31), ThemeColor(0.31, 0.66, 0.23), ThemeColor(0.18, 0.51, 0.21),
            ThemeColor(0.12, 0.37, 0.18),
        ]),
        ReaderTheme(id: "sunflowers", title: "Sunflowers", accents: [
            ThemeColor(1.00, 0.96, 0.76), ThemeColor(1.00, 0.87, 0.32), ThemeColor(1.00, 0.75, 0.09),
            ThemeColor(0.93, 0.58, 0.06), ThemeColor(0.60, 0.44, 0.10), ThemeColor(0.27, 0.40, 0.20),
            ThemeColor(0.18, 0.30, 0.16),
        ]),
        ReaderTheme(id: "brown", title: "Brown", accents: [
            ThemeColor(0.96, 0.90, 0.82), ThemeColor(0.91, 0.81, 0.66), ThemeColor(0.83, 0.69, 0.48),
            ThemeColor(0.73, 0.55, 0.33), ThemeColor(0.59, 0.41, 0.23), ThemeColor(0.44, 0.29, 0.16),
            ThemeColor(0.29, 0.19, 0.10),
        ]),
        ReaderTheme(id: "beige", title: "Beige", accents: [
            ThemeColor(0.96, 0.93, 0.85), ThemeColor(0.87, 0.81, 0.69), ThemeColor(0.73, 0.64, 0.51),
            ThemeColor(0.45, 0.38, 0.29), ThemeColor(0.25, 0.21, 0.16),
        ], style: .gradient([ThemeColor(0.96, 0.93, 0.85).nsColor, ThemeColor(0.87, 0.81, 0.69).nsColor, ThemeColor(0.73, 0.64, 0.51).nsColor])),
        ReaderTheme(id: "dune", title: "Dune", accents: [
            ThemeColor(0.96, 0.82, 0.59), ThemeColor(0.95, 0.72, 0.37), ThemeColor(0.77, 0.43, 0.22),
            ThemeColor(0.32, 0.20, 0.22), ThemeColor(0.09, 0.25, 0.31),
        ], style: .gradient([ThemeColor(0.95, 0.72, 0.37).nsColor, ThemeColor(0.77, 0.43, 0.22).nsColor,
                   ThemeColor(0.32, 0.20, 0.22).nsColor, ThemeColor(0.09, 0.25, 0.31).nsColor])),
        ReaderTheme(id: "lavender", title: "Lavender", accents: [
            ThemeColor(0.94, 0.91, 0.98), ThemeColor(0.79, 0.69, 0.91), ThemeColor(0.57, 0.43, 0.76),
            ThemeColor(0.34, 0.25, 0.52), ThemeColor(0.20, 0.13, 0.32),
        ], style: .gradient([ThemeColor(0.94, 0.91, 0.98).nsColor, ThemeColor(0.79, 0.69, 0.91).nsColor,
                   ThemeColor(0.57, 0.43, 0.76).nsColor, ThemeColor(0.34, 0.25, 0.52).nsColor])),
        ReaderTheme(id: "lavender-grey", title: "Lavender & Kitten Grey", accents: [
            ThemeColor(0.91, 0.86, 0.96), ThemeColor(0.75, 0.69, 0.82), ThemeColor(0.61, 0.60, 0.66),
            ThemeColor(0.43, 0.44, 0.48), ThemeColor(0.20, 0.18, 0.25),
        ], style: .gradient([ThemeColor(0.91, 0.86, 0.96).nsColor, ThemeColor(0.75, 0.69, 0.82).nsColor,
                   ThemeColor(0.61, 0.60, 0.66).nsColor, ThemeColor(0.43, 0.44, 0.48).nsColor])),
        ReaderTheme(id: "heather", title: "Heather", accents: [
            ThemeColor(0.78, 0.61, 0.76), ThemeColor(0.67, 0.46, 0.68), ThemeColor(0.50, 0.35, 0.58),
            ThemeColor(0.38, 0.45, 0.36), ThemeColor(0.19, 0.15, 0.24),
        ], style: .packedCircles(background: ThemeColor(0.19, 0.15, 0.24).nsColor,
                           circles: [ThemeColor(0.50, 0.35, 0.58).nsColor, ThemeColor(0.67, 0.46, 0.68).nsColor,
                                     ThemeColor(0.78, 0.61, 0.76).nsColor, ThemeColor(0.38, 0.45, 0.36).nsColor],
                           seed: 0x4EA74E2)),
        ReaderTheme(id: "galaxy", title: "Galaxy", accents: [
            ThemeColor(0.29, 0.16, 0.54), ThemeColor(0.24, 0.13, 0.47), ThemeColor(0.20, 0.10, 0.40),
            ThemeColor(0.16, 0.08, 0.33), ThemeColor(0.13, 0.06, 0.26), ThemeColor(0.09, 0.04, 0.19),
            ThemeColor(0.06, 0.03, 0.13),
        ], starSeed: 0x5EED),
        ReaderTheme(id: "starry-night", title: "Starry Night", accents: [
            ThemeColor(0.96, 0.83, 0.42), ThemeColor(0.16, 0.28, 0.53), ThemeColor(0.12, 0.23, 0.46),
            ThemeColor(0.09, 0.19, 0.39), ThemeColor(0.07, 0.16, 0.31), ThemeColor(0.05, 0.12, 0.25),
        ], starSeed: 0x57A22),
        ReaderTheme(id: "supernova", title: "Supernova", accents: [
            ThemeColor(1.00, 0.98, 0.72), ThemeColor(1.00, 0.68, 0.16), ThemeColor(0.94, 0.20, 0.17),
            ThemeColor(0.49, 0.10, 0.46), ThemeColor(0.08, 0.04, 0.19),
        ], style: .radial([ThemeColor(1.00, 0.98, 0.72).nsColor, ThemeColor(1.00, 0.68, 0.16).nsColor,
                 ThemeColor(0.94, 0.20, 0.17).nsColor, ThemeColor(0.49, 0.10, 0.46).nsColor,
                 ThemeColor(0.08, 0.04, 0.19).nsColor]), starSeed: 0x5A9E2A0A),
        ReaderTheme(id: "water", title: "Water", accents: [
            ThemeColor(0.76, 0.91, 0.91), ThemeColor(0.40, 0.76, 0.85), ThemeColor(0.16, 0.58, 0.76),
            ThemeColor(0.10, 0.42, 0.65), ThemeColor(0.05, 0.26, 0.43),
        ], style: .waves(background: ThemeColor(0.05, 0.26, 0.43).nsColor,
                   waves: [ThemeColor(0.10, 0.42, 0.65).nsColor, ThemeColor(0.16, 0.58, 0.76).nsColor,
                           ThemeColor(0.40, 0.76, 0.85).nsColor, ThemeColor(0.76, 0.91, 0.91).nsColor],
                   spacing: 1, amplitude: 1)),
        ReaderTheme(id: "gentle-water", title: "Gentle Water", accents: [
            ThemeColor(0.50, 0.72, 0.77), ThemeColor(0.27, 0.57, 0.67), ThemeColor(0.16, 0.45, 0.58),
            ThemeColor(0.10, 0.34, 0.48),
        ], style: .waves(background: ThemeColor(0.10, 0.34, 0.48).nsColor,
                   waves: [ThemeColor(0.16, 0.45, 0.58).nsColor, ThemeColor(0.27, 0.57, 0.67).nsColor,
                           ThemeColor(0.50, 0.72, 0.77).nsColor],
                   spacing: 2.4, amplitude: 0.30)),
        ReaderTheme(id: "sea-foam", title: "Sea Foam", accents: [
            ThemeColor(0.85, 0.94, 0.89), ThemeColor(0.58, 0.82, 0.75), ThemeColor(0.34, 0.68, 0.64),
            ThemeColor(0.18, 0.53, 0.56), ThemeColor(0.06, 0.29, 0.31),
        ], style: .waves(background: ThemeColor(0.85, 0.94, 0.89).nsColor,
                   waves: [ThemeColor(0.58, 0.82, 0.75).nsColor, ThemeColor(0.34, 0.68, 0.64).nsColor,
                           ThemeColor(0.18, 0.53, 0.56).nsColor],
                   spacing: 1.8, amplitude: 0.52)),
        ReaderTheme(id: "harlequin", title: "Harlequin", accents: [
            ThemeColor(0.98, 0.72, 0.08), ThemeColor(0.93, 0.10, 0.20), ThemeColor(0.20, 0.30, 0.74),
            ThemeColor(0.08, 0.56, 0.49), ThemeColor(0.08, 0.07, 0.11),
        ], style: .diamonds(background: ThemeColor(0.08, 0.07, 0.11).nsColor,
                      diamonds: [ThemeColor(0.93, 0.10, 0.20).nsColor, ThemeColor(0.98, 0.72, 0.08).nsColor,
                                 ThemeColor(0.08, 0.56, 0.49).nsColor, ThemeColor(0.20, 0.30, 0.74).nsColor])),
        ReaderTheme(id: "circle-packing", title: "Circle Packing", accents: [
            ThemeColor(0.99, 0.61, 0.17), ThemeColor(0.96, 0.25, 0.36), ThemeColor(0.70, 0.30, 0.86),
            ThemeColor(0.30, 0.45, 0.92), ThemeColor(0.14, 0.73, 0.65), ThemeColor(0.08, 0.08, 0.14),
        ], style: .packedCircles(background: ThemeColor(0.08, 0.08, 0.14).nsColor,
                           circles: [ThemeColor(0.96, 0.25, 0.36).nsColor, ThemeColor(0.99, 0.61, 0.17).nsColor,
                                     ThemeColor(0.14, 0.73, 0.65).nsColor, ThemeColor(0.30, 0.45, 0.92).nsColor,
                                     ThemeColor(0.70, 0.30, 0.86).nsColor], seed: 0xC1AC1E)),
        ReaderTheme(id: "delaunay", title: "Delaunay Triangles", accents: [
            ThemeColor(0.98, 0.84, 0.28), ThemeColor(0.99, 0.62, 0.18), ThemeColor(0.96, 0.32, 0.22),
            ThemeColor(0.19, 0.68, 0.62), ThemeColor(0.16, 0.43, 0.68), ThemeColor(0.39, 0.24, 0.59),
        ], style: .mesh([ThemeColor(0.96, 0.32, 0.22).nsColor, ThemeColor(0.99, 0.62, 0.18).nsColor,
               ThemeColor(0.98, 0.84, 0.28).nsColor, ThemeColor(0.19, 0.68, 0.62).nsColor,
               ThemeColor(0.16, 0.43, 0.68).nsColor, ThemeColor(0.39, 0.24, 0.59).nsColor],
              seed: 0xDE1A0A7)),
        ReaderTheme(id: "vim", title: "Vim", accents: [
            ThemeColor(0.08, 0.54, 0.29), ThemeColor(0.00, 0.38, 0.20), ThemeColor(0.14, 0.25, 0.36),
            ThemeColor(0.08, 0.15, 0.25), ThemeColor(0.02, 0.08, 0.12),
        ]),
        ReaderTheme(id: "silver", title: "Silver", accents: [
            ThemeColor(0.97, 0.97, 0.98), ThemeColor(0.91, 0.92, 0.94), ThemeColor(0.84, 0.86, 0.89),
            ThemeColor(0.76, 0.78, 0.82), ThemeColor(0.67, 0.70, 0.75), ThemeColor(0.57, 0.60, 0.66),
            ThemeColor(0.47, 0.50, 0.56),
        ]),
        ReaderTheme(id: "silver-black", title: "Silver / Black", accents: [
            ThemeColor(0.82, 0.83, 0.85), ThemeColor(0.48, 0.50, 0.54), ThemeColor(0.38, 0.39, 0.42),
            ThemeColor(0.22, 0.23, 0.25), ThemeColor(0.05, 0.05, 0.06),
        ]),
    ]
}

private struct ReaderThemeKey: EnvironmentKey {
    static let defaultValue: ReaderTheme = .standard
}

extension EnvironmentValues {
    var readerTheme: ReaderTheme {
        get { self[ReaderThemeKey.self] }
        set { self[ReaderThemeKey.self] = newValue }
    }
}

private struct PolkaDotTexture: View {
    var color: Color
    var unit: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let tile = unit * 4
            var y: CGFloat = -tile
            while y < size.height + tile {
                var x: CGFloat = -tile
                while x < size.width + tile {
                    context.fill(Path(CGRect(x: x + unit, y: y + unit * 3, width: unit, height: unit)), with: .color(color))
                    context.fill(Path(CGRect(x: x + unit * 3, y: y + unit, width: unit, height: unit)), with: .color(color))
                    x += tile
                }
                y += tile
            }
        }
        .allowsHitTesting(false)
    }
}

/// Generates and applies a themed app icon: a solid midpoint colour with the
/// winning candle artwork embossed over the top.
/// Persisted across relaunches since an icon override is otherwise just an
/// in-memory NSApplication property macOS has no reason to remember on its
/// own.
enum AppIconTheming {
    @MainActor private static var appearanceObserver: NSKeyValueObservation?

    private static let artwork: NSImage? = {
        guard let url = Bundle.module.url(forResource: "AppIconArtwork", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    @MainActor
    static func apply(_ theme: ReaderTheme) {
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        NSApplication.shared.applicationIconImage = windowIcon(dark: dark)
    }

    @MainActor
    static func applyStoredSelection() {
        apply(.named("default"))
        appearanceObserver = NSApplication.shared.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            Task { @MainActor in
                apply(.named("default"))
            }
        }
    }

    static func themedIcon(_ theme: ReaderTheme, size: CGFloat = 512) -> NSImage? {
        windowIcon(dark: false, size: size)
    }

    static func windowIcon(dark: Bool, size: CGFloat = 512) -> NSImage? {
        guard let artwork else { return nil }
        let result = NSImage(size: NSSize(width: size, height: size))
        result.lockFocus()
        defer { result.unlockFocus() }
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        (dark ? NSColor.white : NSColor.black).setFill()
        NSBezierPath(rect: rect).fill()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        return result
    }
}
/// each view update — regenerating either one per frame is the difference
/// between a themed window and a stuttering one.
@MainActor
enum ThemeArtwork {
    private static var icons: [String: NSImage] = [:]
    private static var headers: [String: NSImage] = [:]

    static func icon(_ theme: ReaderTheme, size: CGFloat) -> NSImage {
        let key = "\(theme.id)@\(Int(size))"
        if let cached = icons[key] {
            return cached
        }
        let image = AppIconTheming.themedIcon(theme, size: size) ?? NSImage(size: NSSize(width: size, height: size))
        icons[key] = image
        return image
    }

    /// The title-bar strip. Drawn wide and tiled through the palette rather
    /// than fitted once: a header is a long thin band, and fitting a seven-stop
    /// ramp across it end to end reads as a single smear of colour instead of
    /// the theme's pattern.
    static func header(_ theme: ReaderTheme, width: CGFloat, height: CGFloat) -> NSImage {
        let key = "\(theme.id)@\(Int(width))x\(Int(height))"
        if let cached = headers[key] {
            return cached
        }
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        ThemePatternRenderer.fill(theme.headerStyle, in: NSBezierPath(rect: rect), stripeWidth: 22, starSeed: theme.headerStarSeed)
        image.unlockFocus()
        headers[key] = image
        if luminances[theme.id] == nil {
            luminances[theme.id] = meanLuminance(of: image)
        }
        return image
    }

    private static var luminances: [String: Double] = [:]

    static func headerIsDark(_ theme: ReaderTheme) -> Bool {
        if let known = luminances[theme.id] {
            return known < 0.55
        }
        _ = header(theme, width: 1600, height: 52)
        return (luminances[theme.id] ?? 1) < 0.55
    }

    /// Redrawn into a known sRGB buffer and averaged from the raw bytes.
    /// `NSBitmapImageRep.colorAt` reads back through whatever colour space the
    /// lock-focus context happened to use and returns nonsense for some of
    /// these patterns — it had Sparkling Water, a pale cyan band, coming out
    /// dark enough to warrant white ink.
    private static func meanLuminance(of image: NSImage) -> Double {
        let width = 64
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return 1
        }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
        }
        return total / Double(width * height)
    }
}
