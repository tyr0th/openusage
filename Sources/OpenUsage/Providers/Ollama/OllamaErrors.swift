import Foundation

/// No usable credential anywhere: no session cookie in Keychain/env, and no API key either.
enum OllamaAuthError: Error, LocalizedError, Equatable {
    case notSignedIn

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "No Ollama API key found. Add to Keychain (service=ollama-api-key, account=catalyst) or set OLLAMA_API_KEY."
        }
    }
}

enum OllamaUsageError: Error, LocalizedError, Equatable {
    /// `ollama.com/settings` redirected to sign-in (302/303), or returned 200 with a sign-in page body —
    /// either way the session cookie is stale. The cookie-refresher LaunchAgent that maintains this
    /// Keychain entry lives outside this app, in the `scripts/ollama-cookie-refresher/` directory of the
    /// Catalyst `openusage` repo (not this SwiftPM tree) — it re-seeds the cookie on its own schedule; this
    /// is surfaced as a friendly wait rather than "not signed in" since credentials do exist, they're just expired.
    case sessionExpired
    case requestFailed(Int)
    case connectionFailed
    case invalidResponse
    /// The API key fallback path got a 401/403 from `/v1/models`.
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Session cookie expired. The cookie-refresher LaunchAgent should update it on its next tick, or run its refresh_session.py manually from the Catalyst openusage repo."
        case .requestFailed(let status):
            return "Request failed (HTTP \(status)). Try again later."
        case .connectionFailed:
            return "Usage request failed. Check your connection."
        case .invalidResponse:
            return "Response invalid. Try again later."
        case .invalidKey:
            return "API key invalid. Check your Ollama Cloud API key."
        }
    }
}
