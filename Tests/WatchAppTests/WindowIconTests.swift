import AppKit
import XCTest
@testable import WatchApp

final class WindowIconTests: XCTestCase {
    @MainActor
    func testLightAndDarkIconsKeepMatchingTransparency() throws {
        let light = try XCTUnwrap(AppIconTheming.windowIcon(dark: false))
        let dark = try XCTUnwrap(AppIconTheming.windowIcon(dark: true))
        let black = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(light.tiffRepresentation)))
        let white = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(dark.tiffRepresentation)))
        XCTAssertEqual(black.pixelsWide, white.pixelsWide)
        var transparent = 0
        var ink = 0
        for y in stride(from: 0, to: black.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: black.pixelsWide, by: 4) {
                let a = try XCTUnwrap(black.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try XCTUnwrap(white.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertEqual(a.alphaComponent, b.alphaComponent, accuracy: 0.01)
                if a.alphaComponent < 0.01 { transparent += 1 }
                if a.alphaComponent > 0.99 {
                    ink += 1
                    XCTAssertLessThan(a.redComponent, 0.01)
                    XCTAssertGreaterThan(b.redComponent, 0.99)
                }
            }
        }
        XCTAssertGreaterThan(transparent, ink)
        XCTAssertGreaterThan(ink, 100)
    }
}
