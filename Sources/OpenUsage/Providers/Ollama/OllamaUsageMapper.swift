import Foundation

/// Turns parsed Ollama Cloud data into `MetricLine`s. Pure/behavior-free, mirroring `ClaudeUsageMapper`'s
/// role for its provider.
enum OllamaUsageMapper {
    static let sessionPeriodDurationMs = 5 * 60 * 60 * 1000 // 5 hours (typical Ollama session window)
    static let weeklyPeriodDurationMs = 7 * 24 * 60 * 60 * 1000 // 7 days

    /// Model names that indicate the Pro tier when no explicit plan is otherwise known — a heuristic
    /// fallback only used on the API-key path, where there is nothing else to infer plan from. Update
    /// this list if Ollama's Pro-only lineup changes; it is not authoritative.
    static let proMarkerModelIDs: Set<String> = ["kimi-k2.5", "kimi-k2.6", "deepseek-v3.2", "qwen3-coder-next"]

    /// Session/Weekly meters + Plan badge from a settings-page scrape. `planHint` (an explicit
    /// `OLLAMA_PLAN` override) always wins over the scraped tier.
    static func buildSettingsLines(_ parsed: OllamaHTMLParser.SettingsUsage, planHint: String?) -> (plan: String?, lines: [MetricLine]) {
        var lines: [MetricLine] = []

        if let percent = parsed.sessionPercent {
            lines.append(.progress(
                label: "Session",
                used: percent,
                limit: 100,
                format: .percent,
                resetsAt: parsed.sessionResetsAt,
                periodDurationMs: sessionPeriodDurationMs
            ))
        }
        if let percent = parsed.weeklyPercent {
            lines.append(.progress(
                label: "Weekly",
                used: percent,
                limit: 100,
                format: .percent,
                resetsAt: parsed.weeklyResetsAt,
                periodDurationMs: weeklyPeriodDurationMs
            ))
        }

        let plan = planHint ?? parsed.plan
        if let plan {
            lines.append(.badge(label: "Plan", text: plan))
        }
        return (plan, lines)
    }

    static func modelsBadge(count: Int) -> MetricLine {
        .badge(label: "Models", text: "\(count) available")
    }

    /// API-key-fallback plan inference: no usage endpoint exists on this path, so the tier is guessed
    /// from whether any known Pro-only model is present in the catalog. Defaults to "Free" — mirrors the
    /// legacy plugin's "priority: explicit override > model-list inference > Free fallback".
    static func inferredPlan(planHint: String?, modelIDs: [String]) -> String {
        if let planHint { return planHint }
        let idSet = Set(modelIDs)
        if !idSet.isDisjoint(with: proMarkerModelIDs) { return "Pro" }
        return "Free"
    }
}
