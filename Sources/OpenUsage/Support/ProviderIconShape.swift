import SwiftUI

/// A provider's copied vector mark, keyed by provider id.
struct IconSource: Hashable {
    let providerID: String

    /// Named constructor retained at call sites so the stored string's meaning stays explicit.
    static func providerMark(_ providerID: String) -> IconSource {
        IconSource(providerID: providerID)
    }
}

/// Renders an `IconSource` in monochrome (`Theme.iconGray`): on the glass popover, icon color
/// reads as noise (WWDC25 — monochrome reduces it), and provider identity comes from the name
/// beside the mark.
struct ProviderIcon: View {
    let source: IconSource
    /// Margin kept around a vector provider mark, forwarded to `ProviderIconShape`. Defaults to the
    /// breathing-room value used in list contexts (e.g. Settings); callers that want the mark to
    /// fill its box — like the section header matching the menu-bar strip glyph — pass a smaller value.
    var inset: CGFloat = 0.14

    var body: some View {
        if let mark = ProviderMarks.mark(for: source.providerID) {
            ProviderIconShape(pathData: mark.path, inset: inset)
                .fill(Theme.iconGray)
        } else {
            Image(systemName: ProviderMarks.symbolFallback(for: source.providerID))
                .foregroundStyle(Theme.iconGray)
        }
    }
}

/// A SwiftUI `Shape` built from an SVG path `d` string, scaled to fit the frame and centered.
///
/// It normalizes by the artwork's **true bounding box** (not the declared `viewBox`): some source SVGs
/// bake whitespace into their viewBox (Claude/Codex/Cursor sit ~10% inside a 100×100 box) while others
/// run edge-to-edge (Devin, Grok). Fitting the real path bounds gives every provider mark the same
/// optical weight, then a single shared `inset` adds consistent breathing room so none touch the edge.
struct ProviderIconShape: Shape {
    let pathData: String
    /// Fraction of the frame kept as margin on every side, so normalized marks have uniform padding.
    var inset: CGFloat = 0.14

    func path(in rect: CGRect) -> Path {
        let raw = SVGPath.parse(pathData)
        let bounds = raw.cgPath.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return raw }
        let target = rect.insetBy(dx: rect.width * inset, dy: rect.height * inset)
        let scale = min(target.width / bounds.width, target.height / bounds.height)
        let dx = target.midX - bounds.midX * scale
        let dy = target.midY - bounds.midY * scale
        return raw
            .applying(CGAffineTransform(scaleX: scale, y: scale))
            .applying(CGAffineTransform(translationX: dx, y: dy))
    }
}

/// A provider vector mark: the combined SVG path data. `ProviderIconShape` normalizes by the path's
/// true bounding box, so the source `viewBox` isn't needed.
struct ProviderMark: Hashable {
    let path: String
}

/// Loads copied provider SVGs from the bundle and extracts their path data (cached).
@MainActor
enum ProviderMarks {
    private static var cache: [String: ProviderMark] = [:]
    private static var missing: Set<String> = []

    static func mark(for id: String) -> ProviderMark? {
        if let cached = cache[id] { return cached }
        if missing.contains(id) { return nil }
        guard
            let url = Bundle.openUsageResources.url(forResource: id, withExtension: "svg", subdirectory: "ProviderIcons"),
            let text = try? String(contentsOf: url, encoding: .utf8),
            let d = extractD(text)
        else {
            missing.insert(id)
            return nil
        }
        let mark = ProviderMark(path: d)
        cache[id] = mark
        return mark
    }

    static func symbolFallback(for id: String) -> String {
        switch id {
        case "antigravity": return "paperplane"
        case "claude": return "sparkle"
        case "codex": return "circle.hexagongrid"
        case "cursor": return "cube"
        case "grok": return "bolt.fill"
        // Placeholder: no real Higgsfield logo asset ships yet. Drop `ProviderIcons/higgsfield.svg` into
        // the resource bundle and `mark(for:)` supersedes this SF Symbol automatically.
        case "higgsfield": return "wand.and.stars"
        case "opencode": return "chevron.left.forwardslash.chevron.right"
        case "ollama": return "cloud"
        case "openrouter": return "point.3.connected.trianglepath.dotted"
        case "zai": return "z.signal"
        default: return "app.dashed"
        }
    }

    private static func extractD(_ svg: String) -> String? {
        var values: [String] = []
        var searchStart = svg.startIndex
        while let start = svg[searchStart...].range(of: "d=\"") {
            let rest = svg[start.upperBound...]
            guard let end = rest.firstIndex(of: "\"") else { break }
            values.append(String(rest[..<end]))
            searchStart = end
        }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }
}

/// Minimal SVG path parser supporting M/L/H/V/C/S/Q/T/A/Z (absolute + relative, implicit repeats).
/// Elliptical arcs (A/a) are converted to cubic Béziers so arc-heavy marks (e.g. the Ollama llama)
/// render fully instead of breaking at the first unsupported command.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let chars = Array(d)
        let n = chars.count
        var i = 0

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var lastCommand: Character = " "
        var prevWasCubic = false
        var prevWasQuad = false

        func skipSeparators() {
            while i < n {
                let c = chars[i]
                if c == " " || c == "," || c == "\n" || c == "\t" || c == "\r" { i += 1 } else { break }
            }
        }

        func readNumber() -> CGFloat? {
            skipSeparators()
            var s = ""
            if i < n, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
            var sawDot = false
            while i < n {
                let c = chars[i]
                if c.isNumber {
                    s.append(c); i += 1
                } else if c == "." && !sawDot {
                    sawDot = true; s.append(c); i += 1
                } else if c == "e" || c == "E" {
                    s.append(c); i += 1
                    if i < n, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
                } else {
                    break
                }
            }
            guard let value = Double(s) else { return nil }
            return CGFloat(value)
        }

        func readPoint(relative: Bool) -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        // Arc flags are a single '0' or '1' and may abut the next value with no separator
        // (e.g. "0 0 0-.558"), so they must be read one character at a time, not as full numbers.
        func readFlag() -> Bool? {
            skipSeparators()
            guard i < n else { return nil }
            switch chars[i] {
            case "0": i += 1; return false
            case "1": i += 1; return true
            default: return nil
            }
        }

        func reflected() -> CGPoint {
            guard let lc = lastControl else { return current }
            return CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
        }

        while i < n {
            skipSeparators()
            if i >= n { break }

            if chars[i].isLetter {
                lastCommand = chars[i]
                i += 1
            }

            let cmd = lastCommand
            var failed = false
            var isCubic = false
            var isQuad = false

            switch cmd {
            case "M", "m":
                if let p = readPoint(relative: cmd == "m") {
                    path.move(to: p)
                    current = p
                    subpathStart = p
                    lastCommand = (cmd == "m") ? "l" : "L"
                } else { failed = true }

            case "L", "l":
                if let p = readPoint(relative: cmd == "l") {
                    path.addLine(to: p); current = p
                } else { failed = true }

            case "H", "h":
                if let x = readNumber() {
                    let nx = (cmd == "h") ? current.x + x : x
                    let p = CGPoint(x: nx, y: current.y)
                    path.addLine(to: p); current = p
                } else { failed = true }

            case "V", "v":
                if let y = readNumber() {
                    let ny = (cmd == "v") ? current.y + y : y
                    let p = CGPoint(x: current.x, y: ny)
                    path.addLine(to: p); current = p
                } else { failed = true }

            case "C", "c":
                if let c1 = readPoint(relative: cmd == "c"),
                   let c2 = readPoint(relative: cmd == "c"),
                   let end = readPoint(relative: cmd == "c") {
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end; lastControl = c2; isCubic = true
                } else { failed = true }

            case "S", "s":
                if let c2 = readPoint(relative: cmd == "s"),
                   let end = readPoint(relative: cmd == "s") {
                    let c1 = prevWasCubic ? reflected() : current
                    path.addCurve(to: end, control1: c1, control2: c2)
                    current = end; lastControl = c2; isCubic = true
                } else { failed = true }

            case "Q", "q":
                if let c = readPoint(relative: cmd == "q"),
                   let end = readPoint(relative: cmd == "q") {
                    path.addQuadCurve(to: end, control: c)
                    current = end; lastControl = c; isQuad = true
                } else { failed = true }

            case "T", "t":
                if let end = readPoint(relative: cmd == "t") {
                    let c = prevWasQuad ? reflected() : current
                    path.addQuadCurve(to: end, control: c)
                    current = end; lastControl = c; isQuad = true
                } else { failed = true }

            case "A", "a":
                // rx ry x-axis-rotation large-arc-flag sweep-flag x y. Only the endpoint is affected
                // by relative mode; the radii and rotation are always absolute magnitudes.
                if let rx = readNumber(),
                   let ry = readNumber(),
                   let rotation = readNumber(),
                   let largeArc = readFlag(),
                   let sweep = readFlag(),
                   let end = readPoint(relative: cmd == "a") {
                    SVGPath.appendArc(
                        to: &path, from: current, rx: rx, ry: ry, xRotationDeg: rotation,
                        largeArc: largeArc, sweep: sweep, end: end
                    )
                    current = end
                    lastControl = nil
                } else { failed = true }

            case "Z", "z":
                path.closeSubpath()
                current = subpathStart

            default:
                failed = true
            }

            if failed { break }
            prevWasCubic = isCubic
            prevWasQuad = isQuad
        }

        return path
    }

    /// Appends an SVG elliptical arc as a sequence of ≤90° cubic-Bézier segments, using the
    /// endpoint-to-center parameterization from the SVG spec (F.6.5). Handles ellipses and rotation.
    static func appendArc(
        to path: inout Path,
        from start: CGPoint,
        rx rxIn: CGFloat,
        ry ryIn: CGFloat,
        xRotationDeg: CGFloat,
        largeArc: Bool,
        sweep: Bool,
        end: CGPoint
    ) {
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        // Degenerate radii or a zero-length arc collapse to a straight line (per spec).
        guard rx > 0, ry > 0, start != end else {
            path.addLine(to: end)
            return
        }

        let phi = xRotationDeg * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        // Midpoint transform: (x1', y1').
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Scale radii up if they can't span the endpoints.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }

        // Center in the transformed space: (cx', cy').
        let rx2 = rx * rx, ry2 = ry * ry
        let x1p2 = x1p * x1p, y1p2 = y1p * y1p
        let num = max(0, rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2)
        let den = rx2 * y1p2 + ry2 * x1p2
        let coef = (largeArc == sweep ? -1.0 : 1.0) * sqrt(den == 0 ? 0 : num / den)
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * (-ry * x1p / rx)

        // Center in user space.
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var angle = acos(min(max(len == 0 ? 1 : dot / len, -1), 1))
            if ux * vy - uy * vx < 0 { angle = -angle }
            return angle
        }

        let ux = (x1p - cxp) / rx, uy = (y1p - cyp) / ry
        let vx = (-x1p - cxp) / rx, vy = (-y1p - cyp) / ry
        let theta1 = vectorAngle(1, 0, ux, uy)
        var dTheta = vectorAngle(ux, uy, vx, vy)
        if !sweep, dTheta > 0 { dTheta -= 2 * .pi }
        if sweep, dTheta < 0 { dTheta += 2 * .pi }

        // One cubic per ≤90° slice keeps the Bézier approximation error negligible.
        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / CGFloat(segments)
        let kappa = (4.0 / 3.0) * tan(delta / 4)

        func point(_ theta: CGFloat) -> CGPoint {
            let cosT = cos(theta), sinT = sin(theta)
            return CGPoint(
                x: cx + rx * cosT * cosPhi - ry * sinT * sinPhi,
                y: cy + rx * cosT * sinPhi + ry * sinT * cosPhi
            )
        }
        func derivative(_ theta: CGFloat) -> CGPoint {
            let cosT = cos(theta), sinT = sin(theta)
            return CGPoint(
                x: -rx * sinT * cosPhi - ry * cosT * sinPhi,
                y: -rx * sinT * sinPhi + ry * cosT * cosPhi
            )
        }

        var thetaStart = theta1
        for _ in 0..<segments {
            let thetaEnd = thetaStart + delta
            let p1 = point(thetaStart)
            let p2 = point(thetaEnd)
            let d1 = derivative(thetaStart)
            let d2 = derivative(thetaEnd)
            let control1 = CGPoint(x: p1.x + kappa * d1.x, y: p1.y + kappa * d1.y)
            let control2 = CGPoint(x: p2.x - kappa * d2.x, y: p2.y - kappa * d2.y)
            path.addCurve(to: p2, control1: control1, control2: control2)
            thetaStart = thetaEnd
        }
    }
}
