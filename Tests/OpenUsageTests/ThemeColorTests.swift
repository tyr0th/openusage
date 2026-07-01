import XCTest
import SwiftUI
@testable import OpenUsage

/// Covers the Catalyst Digital brand palette (palette A) applied to the meter severity bands.
/// `MeterSeverityTests` already covers which band a given usage level falls into; this covers what
/// color each band actually renders as, since that's the one thing a `swift test` run can assert
/// without a screenshot.
final class ThemeColorTests: XCTestCase {
    /// Extracts 0-255 RGB components from a `Color` via its `NSColor` bridge, converted to the
    /// device RGB color space first so a `.sRGB`-constructed color reads back exact 8-bit values.
    /// Returned as `[r, g, b]` (not a tuple) so `XCTAssertEqual` has an `Equatable` to compare.
    private func rgb(_ color: Color) -> [Int] {
        let ns = NSColor(color).usingColorSpace(.deviceRGB) ?? NSColor(color)
        return [
            Int((ns.redComponent * 255).rounded()),
            Int((ns.greenComponent * 255).rounded()),
            Int((ns.blueComponent * 255).rounded())
        ]
    }

    func testHexInitializerProducesExactComponents() {
        XCTAssertEqual(rgb(Color(hex: 0x00D9FF)), [0x00, 0xD9, 0xFF])
        XCTAssertEqual(rgb(Color(hex: 0xFF6B9D)), [0xFF, 0x6B, 0x9D])
    }

    /// `.normal` (a healthy meter) is electric cyan #00D9FF — palette A's primary brand color.
    func testNormalSeverityIsCatalystCyan() {
        XCTAssertEqual(rgb(Theme.catalystPrimary), [0x00, 0xD9, 0xFF])
    }

    /// `.critical` (the "you're over" alarm) is neon pink #FF6B9D — a distinct on-brand alarm color,
    /// not stock red, but still visually set apart from the warning band.
    func testCriticalSeverityIsCatalystPink() {
        XCTAssertEqual(rgb(Theme.catalystCritical), [0xFF, 0x6B, 0x9D])
    }

    func testWarningSeverityIsYellow() {
        XCTAssertEqual(rgb(Theme.catalystWarning), [0xFF, 0xD6, 0x0A])
    }

    /// The three bands must remain visually distinct from each other — palette A must not
    /// accidentally collapse the alarm state into the warning state or vice versa.
    func testAllThreeBandsAreDistinctColors() {
        let bands: Set<[Int]> = [
            rgb(Theme.catalystPrimary),
            rgb(Theme.catalystWarning),
            rgb(Theme.catalystCritical)
        ]
        XCTAssertEqual(bands.count, 3)
    }
}
