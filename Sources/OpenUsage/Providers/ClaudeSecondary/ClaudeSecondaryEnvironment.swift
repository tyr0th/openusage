import Foundation

/// Points a `ClaudeAuthStore` at a second, independent Claude Code login for the account-2 provider.
///
/// Claude Code's own multi-login mechanism is `CLAUDE_CONFIG_DIR`: pointing a `claude` login session at a
/// separate config directory gives it its own credentials file and (on macOS) its own hashed Keychain
/// service name. This reader always answers `CLAUDE_CONFIG_DIR` with that second directory — regardless
/// of whatever the real process environment has set — and defers every other lookup to the real
/// environment, so nothing else about credential resolution (custom OAuth URLs, staging flags, an
/// explicit `CLAUDE_CODE_OAUTH_TOKEN`, etc.) changes for the secondary account.
///
/// The override MUST be the fully expanded, absolute path — never the literal `"~/.claude-2nd"` string.
/// `ClaudeAuthStore.keychainServiceCandidates()` hashes whatever this returns
/// (`sha256(value.precomposedStringWithCanonicalMapping).prefix(8)`) to find the Keychain service Claude
/// Code itself wrote the second login under. `CLAUDE_CONFIG_DIR` is a real shell environment variable,
/// and shells expand `~` before exporting it (e.g. `CLAUDE_CONFIG_DIR=~/.claude-2nd claude`), so the hash
/// Claude Code computed at login time was always over the absolute path. Returning the literal tilde form
/// here would hash to a different value and silently fail to find the real Keychain entry — this is
/// exactly the manual-lookup step the legacy Tauri plugin needed (a hardcoded, machine-specific keychain
/// service string) and this reader is designed to make unnecessary.
struct ClaudeSecondaryEnvironmentReader: EnvironmentReading {
    /// Directory name for the second account's Claude Code home, sibling to the primary `~/.claude`.
    static let configDirName = ".claude-2nd"

    private let base: EnvironmentReading

    init(base: EnvironmentReading = ProcessEnvironmentReader()) {
        self.base = base
    }

    func value(for name: String) -> String? {
        guard name == "CLAUDE_CONFIG_DIR" else { return base.value(for: name) }
        return expandHome("~/\(Self.configDirName)")
    }
}
