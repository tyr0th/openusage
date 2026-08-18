import Foundation

/// Turns a Higgsfield balance into `MetricLine`s. Pure/behavior-free, mirroring the other providers'
/// mappers. v1 is honest about what the API exposes: a Credits count (no denominator, so a count row —
/// not a percent meter) and a Plan badge. No Session/Weekly bar or reset is invented.
enum HiggsfieldUsageMapper {
    static func buildLines(_ balance: HiggsfieldBalance) -> (plan: String?, lines: [MetricLine]) {
        var lines: [MetricLine] = []

        // Credits remaining as an unbounded count — there is no allowance ceiling to make a meter, so a
        // raw count is the honest shape (see `docs/providers/higgsfield.md`).
        lines.append(.values(
            label: "Credits",
            values: [MetricValue(number: max(0, balance.credits), kind: .count, label: "credits")]
        ))

        let plan = titleCasedPlan(balance.planSlug)
        if let plan {
            lines.append(.badge(label: "Plan", text: plan))
        }
        return (plan, lines)
    }

    /// "plus" -> "Plus", "pro_plus" -> "Pro Plus". `nil`/empty stays `nil` so no Plan badge renders for an
    /// account without a slug. Uses the shared `titleCased` helper so multi-word slugs read correctly.
    static func titleCasedPlan(_ slug: String?) -> String? {
        guard let slug = slug?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        return slug.titleCased(separator: { $0 == "_" || $0 == " " || $0 == "-" }, lowercasingTail: true)
    }
}
