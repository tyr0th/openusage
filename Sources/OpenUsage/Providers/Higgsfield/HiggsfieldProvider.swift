import Foundation

/// Tracks Higgsfield credits and plan. Reads the access token the `higgsfield` CLI stored on disk and
/// calls `GET fnf.higgsfield.ai/agents/balance` for the account's remaining credits and subscription
/// plan. The API exposes no allowance/quota or reset, so v1 shows a Credits count + a Plan badge only —
/// no invented Session/Weekly meter or reset. See `docs/providers/higgsfield.md`.
///
/// Token refresh is intentionally not implemented in v1: the CLI owns the device-auth refresh flow
/// (`fnf-device-auth.higgsfield.ai`), so an expired token surfaces a friendly "run `higgsfield auth
/// login`" prompt (`HiggsfieldUsageError.loginExpired`) rather than a silent blank.
@MainActor
final class HiggsfieldProvider: ProviderRuntime {
    let provider = Provider(
        id: "higgsfield",
        displayName: "Higgsfield",
        icon: .providerMark("higgsfield"),
        links: [ProviderLink(label: "Dashboard", url: "https://higgsfield.ai")]
    )

    let authStore: HiggsfieldAuthStore
    let usageClient: HiggsfieldUsageClient
    let now: @Sendable () -> Date

    init(
        authStore: HiggsfieldAuthStore = HiggsfieldAuthStore(),
        usageClient: HiggsfieldUsageClient = HiggsfieldUsageClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authStore = authStore
        self.usageClient = usageClient
        self.now = now
    }

    var widgetDescriptors: [WidgetDescriptor] {
        [
            .values(id: "higgsfield.credits", provider: provider, title: "Credits",
                    selection: .kind(.count), traySuffix: "credits"),
            .badge(id: "higgsfield.plan", provider: provider, title: "Plan")
        ]
    }

    func hasLocalCredentials() async -> Bool {
        // Cheap, local-only probe (a single file read, no network), mirroring exactly what `refresh()`
        // reads. A `credentials.json` carrying a non-empty access token counts as a usable local login.
        // An unreadable-but-present file is itself a Higgsfield footprint — enable the provider (return
        // true) and log, so `refresh()` can surface the actionable error instead of the provider staying
        // permanently off with no diagnostic (the new-provider probe runs once). Mirrors OpenCodeProvider.
        let authStore = self.authStore
        return await loadOffMainActor {
            do {
                return try authStore.loadCredentials()?.hasUsableAccessToken ?? false
            } catch {
                AppLog.warn(LogTag.auth("higgsfield"), "hasLocalCredentials: credentials.json unreadable: \(error.localizedDescription)")
                return true
            }
        }
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
        guard let credentials = try await loadOffMainActor({ try authStore.loadCredentials() }),
              let accessToken = credentials.accessToken
        else {
            AppLog.error(LogTag.auth("higgsfield"), "probe failed: no access token")
            throw HiggsfieldAuthError.notSignedIn
        }

        let balance = try await usageClient.fetchBalance(accessToken: accessToken)
        return HiggsfieldUsageMapper.buildLines(balance)
    }
}
