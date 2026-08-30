import AppKit
import SwiftUI

/// The wordmark's typeface. Playfair Display isn't a system font on macOS, so
/// it ships with the app and is registered into the process at first use —
/// there's no plist key that loads fonts for a bundle assembled by hand the
/// way this one is.
///
/// Falls back to a system serif when the file isn't there, so a missing font
/// is a slightly different wordmark rather than a blank one.
enum BrandTypeface {
    private static let familyName = "Playfair Display"

    /// Registered once. `CTFontManagerRegisterFontsForURL` with `.process`
    /// scope makes the face resolvable by name for this process only, which is
    /// what an app bundling its own font wants — nothing is installed for the
    /// user or left behind.
    private static let isRegistered: Bool = {
        // Both the bundle root and the copied Resources directory: SPM's
        // `.copy` preserves the folder, and which of the two a lookup lands in
        // isn't worth depending on.
        var urls: [URL] = []
        for ext in ["ttf", "otf"] {
            for subdirectory in [nil, "Resources"] as [String?] {
                urls += Bundle.module.urls(forResourcesWithExtension: ext, subdirectory: subdirectory) ?? []
            }
        }
        var registeredAny = false
        for url in Set(urls) where CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) {
            registeredAny = true
        }
        return registeredAny
    }()

    /// True when the bundled face actually resolved, so callers can fall back
    /// rather than silently rendering in the system font.
    static var isAvailable: Bool {
        _ = isRegistered
        return NSFont(name: familyName, size: 12) != nil
            || NSFontManager.shared.availableFontFamilies.contains(familyName)
    }

    /// The shared typeface for every app surface. Keeping this here means the
    /// font registration and fallback behaviour are identical for headings,
    /// controls, settings, and article text.
    static func appFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard isAvailable else {
            return .system(size: size, weight: weight, design: .serif)
        }
        return .custom(familyName, size: size).weight(weight)
    }

    static func wordmark(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        appFont(size, weight: weight)
    }
}
