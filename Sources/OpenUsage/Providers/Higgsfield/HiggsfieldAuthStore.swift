import Foundation

/// The access token the `higgsfield` CLI stores on `higgsfield auth login`. Only `access_token` is used
/// here; `refresh_token` is read so the shape matches the file, but v1 does not implement token refresh
/// (an expired token surfaces a friendly re-auth message — see `HiggsfieldProvider`).
struct HiggsfieldCredentials: Hashable, Sendable {
    var accessToken: String?
    var refreshToken: String?

    /// The bar `refresh()` requires and `hasLocalCredentials()` mirrors: a non-empty access token.
    var hasUsableAccessToken: Bool {
        accessToken?.isEmpty == false
    }
}

/// Reads the Higgsfield access token already on the machine. Like every other file-based provider,
/// OpenUsage never asks the user to paste a token — it reads `~/.config/higgsfield/credentials.json`
/// (mode 0600), the same file the `higgsfield` CLI maintains. There is no Keychain entry and no second
/// credential path, so `hasLocalCredentials()` reuses this exact loader.
struct HiggsfieldAuthStore: Sendable {
    /// Directory the `higgsfield` CLI stores credentials in. `HIGGSFIELD_CONFIG_DIR` overrides it (useful
    /// for tests and non-standard installs); otherwise `~/.config/higgsfield`.
    static let defaultConfigDir = "~/.config/higgsfield"
    private static let credentialsFile = "credentials.json"

    var environment: EnvironmentReading
    var files: TextFileAccessing

    init(
        environment: EnvironmentReading = ProcessEnvironmentReader(),
        files: TextFileAccessing = LocalTextFileAccessor()
    ) {
        self.environment = environment
        self.files = files
    }

    /// Blocking file read — call off the main actor. Returns `nil` only for the absent-file / empty-token
    /// "not logged in" case. A file that *exists* but can't be read (permissions, encoding) or doesn't
    /// parse as JSON throws `credentialsUnreadable` so broken storage surfaces loudly rather than being
    /// mistaken for a logout — mirrors `OpenCodeAuthStore.goAPIKey()`.
    func loadCredentials() throws -> HiggsfieldCredentials? {
        let text: String?
        do {
            text = try files.readTextIfPresent(credentialsPath())
        } catch {
            throw HiggsfieldAuthError.credentialsUnreadable(detail: error.localizedDescription)
        }
        guard let text else { return nil }
        guard let object = ProviderParse.jsonObject(Data(text.utf8)) else {
            throw HiggsfieldAuthError.credentialsUnreadable(detail: "credentials.json is not valid JSON")
        }
        let credentials = HiggsfieldCredentials(
            accessToken: (object["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            refreshToken: (object["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        guard credentials.hasUsableAccessToken else { return nil }
        AppLog.info(LogTag.auth("higgsfield"), "access token loaded from credentials.json")
        return credentials
    }

    func credentialsPath() -> String {
        let dir = environment.value(for: "HIGGSFIELD_CONFIG_DIR")?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? Self.defaultConfigDir
        return dir.trimmingTrailingSlashes + "/" + Self.credentialsFile
    }
}
