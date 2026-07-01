import Foundation

/// Extracts usage figures from the rendered `ollama.com/settings` HTML. There is no documented usage API
/// for Ollama Cloud, so this mirrors the legacy Tauri plugin's approach exactly: find a section label,
/// then regex-match within a fixed-size window right after it. Fragile by nature (a page redesign breaks
/// it silently) — this is a known, accepted trade-off, not a defect to "fix" by generalizing the parsing.
enum OllamaHTMLParser {
    struct SettingsUsage: Equatable {
        var sessionPercent: Double?
        var sessionResetsAt: Date?
        var weeklyPercent: Double?
        var weeklyResetsAt: Date?
        var plan: String?
    }

    static func parse(_ html: String) -> SettingsUsage {
        SettingsUsage(
            sessionPercent: percent(in: html, after: "Session usage</span>"),
            sessionResetsAt: resetDate(in: html, after: "Session usage</span>"),
            weeklyPercent: percent(in: html, after: "Weekly usage</span>"),
            weeklyResetsAt: resetDate(in: html, after: "Weekly usage</span>"),
            plan: plan(in: html)
        )
    }

    /// e.g. `<span class="text-sm">14.6% used</span>` — the marker is the preceding label span, and the
    /// percent lives a short way after it.
    private static func percent(in html: String, after marker: String) -> Double? {
        guard let window = window(in: html, after: marker, length: 300) else { return nil }
        guard let raw = firstMatch(pattern: #"([0-9]+(?:\.[0-9]+)?)% used"#, in: window),
              let value = Double(raw), value.isFinite
        else {
            return nil
        }
        return value
    }

    /// e.g. `<div ... data-time="2026-04-27T02:00:00Z" ...></div>` — a wider window than `percent` since
    /// the reset element sits further from the label.
    private static func resetDate(in html: String, after marker: String) -> Date? {
        guard let window = window(in: html, after: marker, length: 600) else { return nil }
        guard let raw = firstMatch(pattern: #"data-time="([^"]+)""#, in: window) else { return nil }
        return OpenUsageISO8601.date(from: raw)
    }

    /// e.g. `Cloud Usage ... class="... capitalize" ...>pro</span` (Cloud Usage section, tier name).
    private static func plan(in html: String) -> String? {
        guard let raw = firstMatch(
            pattern: #"Cloud Usage[\s\S]{0,400}?capitalize[\s\S]{0,50}?>([a-zA-Z0-9 -]+)<\/span"#,
            in: html
        ) else {
            return nil
        }
        let tier = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !tier.isEmpty else { return nil }
        return tier.prefix(1).uppercased() + tier.dropFirst()
    }

    /// The substring starting at `marker`'s end, up to `length` UTF-16 characters (or the end of the
    /// string, whichever comes first). Matches the legacy plugin's `html.indexOf(marker)` + `slice`.
    private static func window(in html: String, after marker: String, length: Int) -> String? {
        guard let markerRange = html.range(of: marker) else { return nil }
        let end = html.index(markerRange.upperBound, offsetBy: length, limitedBy: html.endIndex) ?? html.endIndex
        return String(html[markerRange.upperBound..<end])
    }

    private static func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[groupRange])
    }
}
