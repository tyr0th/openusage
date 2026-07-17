import Foundation

/// The installed provider set and its canonical order. Both the menu-bar app and one-shot CLI build
/// their runtimes here so credentials, refresh behavior, pricing, and normalization can never drift.
@MainActor
enum ProviderCatalog {
    static func make(defaults: UserDefaults = .standard) -> [ProviderRuntime] {
        // Default provider order (see AGENTS.md "## Providers"): the three established providers first,
        // then every other provider alphabetically by display name.
        [
            ClaudeProvider(),
            // Same provider as Claude, a second independent Claude Code login (`~/.claude-2nd`) —
            // registered right after the primary account rather than in the alphabetical tail below,
            // since it's a variant of Claude, not a distinct provider. See ClaudeSecondaryProvider.
            ClaudeSecondaryProvider.make(),
            CodexProvider(),
            CursorProvider(),
            AntigravityProvider(),
            CopilotProvider(defaults: defaults),
            DevinProvider(),
            GrokProvider(),
            OllamaProvider(),
            OpenCodeProvider(),
            OpenRouterProvider(),
            ZAIProvider()
        ]
    }
}
