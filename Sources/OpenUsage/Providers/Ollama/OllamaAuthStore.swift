import Foundation

/// Credentials for tracking Ollama Cloud (`ollama.com`) usage. Unlike every other provider here, Ollama
/// Cloud has no companion CLI/app that stores a long-lived local session the way `claude`/`codex`/Cursor
/// do — so OpenUsage reads a browser session cookie that an external, independently-maintained
/// Playwright-based LaunchAgent keeps fresh in Keychain. That refresher lives in the Catalyst `openusage`
/// repo (`scripts/ollama-cookie-refresher/`), not this SwiftPM tree — it's out of scope for this app and
/// is not rebuilt here; this auth store only reads what it leaves behind.
///
/// Two credential kinds, tried in order:
/// - **Session cookie** (`ollama-session-cookie` / account `catalyst`) — the primary path. It authenticates
///   an HTML scrape of `ollama.com/settings`, which is the only place Session/Weekly usage percentages and
///   the plan tier are exposed; there is no documented usage API.
/// - **API key** (`ollama-api-key` / account `catalyst`) — used as a best-effort "Models available" badge
///   alongside the cookie path, and as a full fallback (infers plan tier from the model list) when no
///   cookie is present.
struct OllamaCredentials: Sendable {
    var sessionCookie: String?
    var apiKey: String?
    /// An explicit `OLLAMA_PLAN` override — takes precedence over anything scraped/inferred.
    var planHint: String?
}

struct OllamaAuthStore: Sendable {
    static let cookieKeychainService = "ollama-session-cookie"
    static let cookieKeychainAccount = "catalyst"
    static let apiKeyKeychainService = "ollama-api-key"
    static let apiKeyKeychainAccount = "catalyst"
    private static let knownPlans: Set<String> = ["free", "pro", "team", "enterprise"]

    var keychain: KeychainAccessing
    var environment: EnvironmentReading

    init(
        keychain: KeychainAccessing = SecurityKeychainAccessor(),
        environment: EnvironmentReading = ProcessEnvironmentReader()
    ) {
        self.keychain = keychain
        self.environment = environment
    }

    /// Blocking Keychain/env reads — call off the main actor.
    func loadCredentials() -> OllamaCredentials {
        OllamaCredentials(
            sessionCookie: loadSessionCookie(),
            apiKey: loadAPIKey(),
            planHint: loadPlanHint()
        )
    }

    private func loadSessionCookie() -> String? {
        if let cookie = (try? keychain.readGenericPassword(service: Self.cookieKeychainService, account: Self.cookieKeychainAccount))?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            AppLog.info(LogTag.auth("ollama"), "session cookie loaded from keychain")
            return cookie
        }
        if let cookie = environment.value(for: "OLLAMA_SESSION_COOKIE")?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            AppLog.info(LogTag.auth("ollama"), "session cookie loaded from env OLLAMA_SESSION_COOKIE")
            return cookie
        }
        return nil
    }

    private func loadAPIKey() -> String? {
        if let key = (try? keychain.readGenericPassword(service: Self.apiKeyKeychainService, account: Self.apiKeyKeychainAccount))?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            AppLog.info(LogTag.auth("ollama"), "api key loaded from keychain")
            return key
        }
        if let key = environment.value(for: "OLLAMA_API_KEY")?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
            AppLog.info(LogTag.auth("ollama"), "api key loaded from env OLLAMA_API_KEY")
            return key
        }
        return nil
    }

    /// An explicit plan override, restricted to the known Ollama Cloud tiers so a typo doesn't propagate
    /// an arbitrary string into the Plan badge.
    private func loadPlanHint() -> String? {
        guard let raw = environment.value(for: "OLLAMA_PLAN")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        guard Self.knownPlans.contains(lower) else {
            AppLog.warn(LogTag.auth("ollama"), "unknown OLLAMA_PLAN: \(raw); ignoring")
            return nil
        }
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
