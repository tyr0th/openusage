import Foundation

/// A provider metric's identity and presentation template. Live provider lines supply the values;
/// `sample` carries stable display metadata such as title, icon, kind, and descriptor opt-ins.
struct WidgetDescriptor: Identifiable, Hashable {
    let id: String                 // "claude.session"
    let providerID: String
    let metricLabel: String
    let sample: WidgetData
    /// Whether this widget can be pinned to the menu-bar strip. False for tiles the tray can't render as
    /// a value — the Usage Trend chart — so the pin affordance never offers a pin that would read "0".
    var pinnable: Bool = true
    /// True only for the `SpendTileMapper`-backed spend-history tiles (see `WidgetDescriptor.spendTiles`).
    /// The Total Spend card keys on this to decide which providers feed the ring — a title match would
    /// wrongly rope in look-alike rows like OpenRouter's API-spend "Today".
    var isSpendTile: Bool = false
    /// Stable scalar resources exported by `/v1/limits`. Empty for UI-only/history widgets.
    var limitResources: [LimitResourceDescriptor] = []
    /// Explicit aggregation semantics for this provider's normalized daily history. Exactly one
    /// descriptor carries it for every provider that exposes the shared spend tiles.
    var historyResource: UsageHistoryDescriptor? = nil

    /// The metric's single display name.
    var title: String { sample.title }

    static func == (lhs: WidgetDescriptor, rhs: WidgetDescriptor) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension WidgetDescriptor {
    /// Fork-local front-end suppression (Ty's build). He doesn't want to *see* any dollar-denominated
    /// metric or any "Extra Usage" / credit-balance tile in the UI. This flag is read only at the
    /// LayoutStore display seams (`visiblePlaced`, `orderedSupportedMetrics`, `metricCount`), so the
    /// hidden rows drop out of the dashboard, Customize, and the menu-bar strip — while the
    /// `WidgetRegistry` object itself stays fully intact. The pricing engine, provider fetch/mappers,
    /// the local API/CLI (`UsageReader`), and the Total Spend aggregator (which reads
    /// `dataStore.snapshots` + `isSpendTile`, never the rendered list) are all untouched, so upstream
    /// merges from robinebers/openusage stay clean.
    ///
    /// Dollar tiles are caught by `rendersCurrency`. The three "Extra Usage"-family tiles that are *not*
    /// dollar-denominated — Copilot's count-based Extra Usage and Org Credits, and Grok's pay-as-you-go
    /// badge — are listed explicitly. Consequence, per the blanket rule: a provider whose every metric is
    /// dollar-denominated (OpenRouter) vanishes from the UI entirely, and dollar-quota providers
    /// (OpenCode's `.boundedDollars` session/weekly/monthly) lose those meter rows. Both are disabled
    /// for Ty.
    static let uiSuppressedMetricIDs: Set<String> = [
        "copilot.extra", "copilot.orgCredits", "grok.payAsYouGo"
    ]

    /// Fork-local exception set, a sibling of `uiSuppressedMetricIDs`: `.values(.all)` tiles whose backing
    /// values are count-denominated and so must *not* be treated as currency. The `.values` factory
    /// (see `WidgetDescriptor+Factories.values`) seeds `sample.kind = .dollars` for any tile whose
    /// `selection` isn't a single explicit `.kind`, so a count-only `.all` tile inherits `.dollars`
    /// without ever rendering currency. `codex.rateLimitResets`'s sole value is a count ("N available").
    /// This is an explicit, greppable id list — not a heuristic read off an unrelated cosmetic field
    /// (the old `traySuffix != nil` proxy) — precisely so it cannot silently absorb a future descriptor:
    /// a new dollar-seeded `.values(.all)` tile is currency (and therefore suppressed) unless it is
    /// deliberately listed here. `LayoutStoreTests.testEverySelectAllDescriptorHasExpectedSuppression`
    /// locks the verdict for every such descriptor so an accidental drop fails loudly.
    static let uiCountDenominatedMetricIDs: Set<String> = ["codex.rateLimitResets"]

    /// Whether this metric is hidden from every rendered widget list (see `uiSuppressedMetricIDs`).
    var isSuppressedFromUI: Bool {
        if WidgetDescriptor.uiSuppressedMetricIDs.contains(id) { return true }
        return rendersCurrency
    }

    /// Whether this tile actually renders a dollar amount. `sample.kind == .dollars` alone is not proof:
    /// the `.values` factory (see `WidgetDescriptor+Factories.values`) seeds `.dollars` as a *fallback*
    /// for any tile whose `selection` isn't a single explicit kind — so a `.values(.all)` tile that only
    /// ever shows a count (e.g. `codex.rateLimitResets`, whose one value is `"N available"`) inherits
    /// `.dollars` without ever displaying currency. Resolve the real rendered kind instead of trusting
    /// the seed: an `.all` selection renders every backing value and so *is* dollar-denominated, unless
    /// the tile is explicitly listed in `uiCountDenominatedMetricIDs`. Explicit `.kind` selections already
    /// carry a truthful `sample.kind`, so they need no special-casing.
    private var rendersCurrency: Bool {
        guard sample.kind == .dollars else { return false }
        if case .all = sample.selection {
            return !WidgetDescriptor.uiCountDenominatedMetricIDs.contains(id)
        }
        return true
    }
}
