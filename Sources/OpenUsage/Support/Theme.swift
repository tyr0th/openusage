import SwiftUI
import AppKit

/// Central palette + surface styles. Surfaces stay adaptive (light/dark).
///
/// The popover is always a solid, opaque panel — glass is reserved for the footer chrome (its frosted
/// bar and the controls on it), never the data region behind it (Apple's guidance: glass for
/// navigation/controls, content on an opaque surface). The data region mirrors the macOS System
/// Settings grouped look: a bright page "tray" with borderless grouped cards lifted off it by the
/// system's own `.fill.quaternary` (the same subtle fill Settings' grouped boxes use — no hand-tuned
/// values), so it adapts to light/dark like every other Mac app.
enum Theme {
    /// Hierarchical secondary tint for the provider marks.
    static let iconGray = AnyShapeStyle(.secondary)

    /// Catalyst Digital brand palette (palette A, approved) for the meter severity bands — electric
    /// cyan for a healthy meter, neon pink for the "you're over" alarm state, kept visually distinct
    /// from the warning band so the over-limit signal still pops on-brand instead of stock red. Fixed
    /// brand hexes rather than adaptive system colors (the prior `.systemBlue`/`.systemYellow`/
    /// `.systemRed`), so the reskin reads identically in light and dark.
    static let catalystPrimary = Color(hex: 0x00D9FF)
    static let catalystWarning = Color(hex: 0xFFD60A)
    static let catalystCritical = Color(hex: 0xFF6B9D)

    /// Meter fill for a severity band. Full strength: on the opaque surface there's no glass to temper
    /// against.
    static func meterFill(_ severity: WidgetData.MeterSeverity) -> AnyShapeStyle {
        AnyShapeStyle(meterColor(severity))
    }

    private static func meterColor(_ severity: WidgetData.MeterSeverity) -> Color {
        switch severity {
        case .normal: return catalystPrimary
        case .warning: return catalystWarning
        case .critical: return catalystCritical
        }
    }

    /// Inline notice/alert tint (refresh warning triangle, pin-limit notice, settings errors) — the
    /// system orange at full strength, matching the meter fills.
    static let notice = AnyShapeStyle(Color(nsColor: .systemOrange))

    /// Inline success tint (the "screenshot copied to clipboard" confirmation) — the system green at
    /// full strength, the positive counterpart to `notice`'s orange.
    static let positive = AnyShapeStyle(Color(nsColor: .systemGreen))

    // MARK: - Surfaces

    /// The popover's opaque backdrop ("tray") behind the grouped cards — `textBackgroundColor`, the
    /// bright page surface document/Notes views use (white in light, near-black in dark; it does not
    /// pick up desktop wallpaper tint). Exposed as an `NSColor` so the panel's AppKit backdrop
    /// (`StatusItemController`) and the SwiftUI surface (`DashboardView.PopoverSurface`) are one color.
    /// The footer's frosted glass bar samples this opaque tray (in-window), so it reads as glass chrome
    /// over solid content, never a hole to the desktop. The grouped cards sit on it (see `cardSurface`).
    static let trayNSColor: NSColor = .textBackgroundColor
    static var traySurface: Color { Color(nsColor: trayNSColor) }

    /// The semantic fill that lifts a grouped card off the `traySurface` page — `.fill.quaternary`, the
    /// system's own subtle grouped fill (≈ the macOS System Settings grouped box: `#F9F9F9` over white
    /// in light, a step lighter than the page in dark). No hand-tuned values; it tracks light/dark and
    /// Increase Contrast. Composited over the opaque page in `cardSurface`, so the card is opaque (a
    /// lifted drag preview stays solid while it floats).
    static let cardFill = AnyShapeStyle(.fill.quaternary)

    /// The single corner radius for every metric/settings card surface and its lifted twin, so the
    /// floating drag preview always matches the live card's shape.
    static let cardCornerRadius: CGFloat = 12

    /// The rounded rectangle shared by every card surface (live and lifted), so the shape is defined once.
    static var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
    }
}

extension View {
    /// The grouped-card surface used for provider/settings cards, in the shared rounded shape: the
    /// bright page base lifted by the system's `.fill.quaternary` (the System Settings grouped-box
    /// look), borderless — the subtle fill carries the grouping the way Settings does, in both light
    /// and dark. Drawing the opaque page base first keeps a lifted drag preview solid while it floats.
    /// `lifted` is accepted for call-site symmetry; live and lifted cards share one surface (the lift's
    /// depth comes from `ReorderLiftPreview`'s shadow, not a different fill).
    func cardSurface(lifted: Bool = false) -> some View {
        modifier(CardSurfaceModifier(lifted: lifted))
    }

    /// A single-row lifted preview surface: the card surface plus a thin separator hairline that fences
    /// a free-floating one-row chip off from the rows beneath it (the multi-row provider previews don't
    /// take the hairline — their shadow alone reads as detached).
    func liftedRowSurface() -> some View {
        cardSurface(lifted: true)
            .overlay { Theme.cardShape.strokeBorder(.separator, lineWidth: 0.5) }
    }

    /// The trailing on/off switch styling shared by every settings + Customize row toggle: no inline
    /// label (the row's leading text is the label), the native switch style, small control size.
    func settingsSwitchStyle() -> some View {
        labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// Backs `cardSurface`. The grouped card surface: the opaque page base (`traySurface`) with the
/// system's `.fill.quaternary` composited on top — borderless, matching the macOS System Settings
/// grouped box in both light and dark. The opaque base means a lifted drag preview stays solid while
/// it floats; the page base under a live card is the same color as the tray behind it, so it's
/// invisible there. `lifted` is unused — both paths share the one surface.
private struct CardSurfaceModifier: ViewModifier {
    let lifted: Bool

    func body(content: Content) -> some View {
        content.background {
            Theme.cardShape
                .fill(Theme.traySurface)
                .overlay { Theme.cardShape.fill(Theme.cardFill) }
        }
    }
}

extension Color {
    /// A `Color` from a packed `0xRRGGBB` value, full opacity — the app's one hex→Color path, so a
    /// fixed brand color (`Theme.catalystPrimary` and friends) is never built from raw per-call math.
    /// `MetricLine`'s `colorHex` strings stay `String` at the model boundary (so the type stays
    /// Codable/platform-agnostic for the local HTTP API) and are a separate, string-keyed concern from
    /// this — this initializer only backs the fixed `Theme` constants.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
