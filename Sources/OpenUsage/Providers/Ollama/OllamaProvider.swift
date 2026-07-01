import Foundation

/// Tracks Ollama Cloud (`ollama.com`) usage. Unlike every other provider in this app, there is no
/// documented usage API and no companion CLI/app credential to read — OpenUsage reads a browser session
/// cookie that an external, independently-run LaunchAgent (`scripts/ollama-cookie-refresher/`) keeps
/// fresh in Keychain, and scrapes the rendered `ollama.com/settings` page with it. See
/// `docs/providers/ollama.md` for the full setup and the fragility trade-offs this implies.
@MainActor
final class OllamaProvider: ProviderRuntime {
    let provider = Provider(id: "ollama", displayName: "Ollama", icon: .providerMark("ollama"))

    let authStore: OllamaAuthStore
    let usageClient: OllamaUsageClient
    let now: @Sendable () -> Date

    init(
        authStore: OllamaAuthStore = OllamaAuthStore(),
        usageClient: OllamaUsageClient = OllamaUsageClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authStore = authStore
        self.usageClient = usageClient
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .percent(id: "ollama.session", provider: provider, title: "Session"),
            .percent(id: "ollama.weekly", provider: provider, title: "Weekly"),
            .badge(id: "ollama.plan", provider: provider, title: "Plan"),
            .badge(id: "ollama.models", provider: provider, title: "Models")
        ]
    }

    func refresh() async -> ProviderSnapshot {
        do {
            let (plan, lines) = try await probe()
            var mutableLines = lines
            MetricLine.appendNoDataIfNeeded(&mutableLines)
            return ProviderSnapshot.make(provider: provider, plan: plan, lines: mutableLines, refreshedAt: now())
        } catch {
            return ProviderSnapshot.error(provider: provider, error: error)
        }
    }

    private func probe() async throws -> (plan: String?, lines: [MetricLine]) {
        let authStore = self.authStore
        let credentials = await loadOffMainActor { authStore.loadCredentials() }

        if let cookie = credentials.sessionCookie {
            return try await probeSettings(cookie: cookie, apiKey: credentials.apiKey, planHint: credentials.planHint)
        }

        guard let apiKey = credentials.apiKey else {
            AppLog.error(LogTag.auth("ollama"), "probe failed: no session cookie or api key")
            throw OllamaAuthError.notSignedIn
        }
        AppLog.info(LogTag.plugin("ollama"), "no session cookie — falling back to API key + /v1/models inference")
        return try await probeModelsFallback(apiKey: apiKey, planHint: credentials.planHint)
    }

    /// Primary path: scrape `ollama.com/settings` with the session cookie for Session/Weekly/Plan, then
    /// best-effort append a Models badge if an API key also happens to be configured (non-fatal on failure).
    private func probeSettings(cookie: String, apiKey: String?, planHint: String?) async throws -> (plan: String?, lines: [MetricLine]) {
        let response = try await usageClient.fetchSettings(cookie: cookie)

        if response.statusCode == 302 || response.statusCode == 303 {
            throw OllamaUsageError.sessionExpired
        }
        guard (200..<300).contains(response.statusCode) else {
            AppLog.error(LogTag.plugin("ollama"), "settings returned HTTP \(response.statusCode)")
            throw OllamaUsageError.requestFailed(response.statusCode)
        }

        let html = String(decoding: response.body, as: UTF8.self)
        let parsed = OllamaHTMLParser.parse(html)
        if parsed.sessionPercent == nil {
            AppLog.warn(LogTag.plugin("ollama"), "session usage not found in settings HTML")
        }
        if parsed.weeklyPercent == nil {
            AppLog.warn(LogTag.plugin("ollama"), "weekly usage not found in settings HTML")
        }

        var (plan, lines) = OllamaUsageMapper.buildSettingsLines(parsed, planHint: planHint)

        if let apiKey {
            do {
                let models = try await usageClient.fetchModels(apiKey: apiKey)
                lines.append(OllamaUsageMapper.modelsBadge(count: models.count))
            } catch {
                AppLog.warn(LogTag.plugin("ollama"), "models fetch failed (non-fatal): \(error.localizedDescription)")
            }
        }

        if lines.isEmpty {
            AppLog.warn(LogTag.plugin("ollama"), "settings HTML parsed but no usage markers found")
        }
        return (plan, lines)
    }

    /// Fallback path when no session cookie is configured: infer the plan tier from the `/v1/models`
    /// catalog (a heuristic, not authoritative — there's no usage endpoint on this path at all).
    private func probeModelsFallback(apiKey: String, planHint: String?) async throws -> (plan: String?, lines: [MetricLine]) {
        let models = try await usageClient.fetchModels(apiKey: apiKey)
        let plan = OllamaUsageMapper.inferredPlan(planHint: planHint, modelIDs: models.modelIDs)
        return (plan, [.badge(label: "Plan", text: plan), OllamaUsageMapper.modelsBadge(count: models.count)])
    }
}
