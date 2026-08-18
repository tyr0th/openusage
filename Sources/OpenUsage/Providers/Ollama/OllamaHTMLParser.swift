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

    /// The reset element is a `local-time` div, e.g.
    /// `<div class="text-xs text-neutral-500 mt-1 local-time" data-time="2026-07-27T00:00:00Z" > Resets in 2 days. </div>`.
    /// Ollama's `settings` redesign now inserts a large `data-usage-meter` hover-bubble block between each
    /// `% used` label and its reset element, so the reset `data-time` sits far from the marker: measured
    /// against the live page it's ~2,893 chars after the "Session usage" marker and ~6,267 chars after the
    /// "Weekly usage" marker — well past the old 600-char window, which is why resets were coming back nil
    /// and the UI fell back to the hardcoded period durations. Widen the window to 8,000 to safely clear the
    /// weekly offset. There are exactly two `data-time` attributes on the page and they appear in document
    /// order (session's precedes the Weekly marker; weekly's follows it), so a first-match-after-marker scan
    /// stays correct. Anchor on the `local-time"` reset element specifically so a future `data-time` added
    /// elsewhere in the window can't hijack the match; fall back to the generic attribute only if the
    /// anchored form misses.
    private static func resetDate(in html: String, after marker: String) -> Date? {
        guard let window = window(in: html, after: marker, length: 8000) else { return nil }
        let raw = firstMatch(pattern: #"local-time"\s+data-time="([^"]+)""#, in: window)
            ?? firstMatch(pattern: #"data-time="([^"]+)""#, in: window)
        guard let raw else { return nil }
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

    /// Defensive fallback for `OllamaProvider.probeSettings`: the legacy plugin (and this port) detect an
    /// expired session cookie via a 302/303 redirect to sign-in, but some deployments serve the sign-in
    /// page directly under a 200 instead of redirecting. Only meaningful when neither usage marker parsed
    /// — a genuine settings response always carries at least the "Session usage" label, so this never
    /// fires against a legitimate partial response. Checks generic sign-in-page giveaways rather than one
    /// unverifiable exact string, since there's no captured real expired-session response to check this
    /// against; revisit if a real one ever surfaces false positives/negatives.
    static func looksLikeSignInPage(_ html: String) -> Bool {
        let markers = ["sign in to ollama", "action=\"/signin\"", "name=\"password\""]
        let lowered = html.lowercased()
        return markers.contains { lowered.contains($0) }
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
