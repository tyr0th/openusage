import Foundation

/// Factory for the "Claude (Account 2)" provider: a second, independent Claude Code login tracked
/// alongside the primary `ClaudeProvider`. There is no separate refresh/mapping implementation here —
/// `ClaudeProvider` already takes its `id`/`displayName`/`authStore` as init parameters, so this is just
/// that same provider constructed with a distinct identity and an `authStore` scoped to a second Claude
/// Code home (`~/.claude-2nd`) via `ClaudeSecondaryEnvironmentReader`. See `docs/providers/claude.md`
/// ("Tracking a second account") for the one-time setup this depends on.
@MainActor
enum ClaudeSecondaryProvider {
    static let id = "claude-2"
    static let displayName = "Claude (Account 2)"

    static func make() -> ClaudeProvider {
        ClaudeProvider(
            id: id,
            displayName: displayName,
            authStore: ClaudeAuthStore(environment: ClaudeSecondaryEnvironmentReader())
        )
    }
}
