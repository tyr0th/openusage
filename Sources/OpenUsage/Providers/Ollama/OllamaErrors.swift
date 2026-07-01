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
    /// `ollama.com/settings` redirected to sign-in (302/303) — the session cookie is stale. The external
    /// `ollama-session-refresher` LaunchAgent re-seeds the Keychain entry on its own schedule; this is
    /// surfaced as a friendly wait rather than "not signed in" since credentials do exist, they're just expired.
    case sessionExpired
    case requestFailed(Int)
    case connectionFailed
    case invalidResponse
    /// The API key fallback path got a 401/403 from `/v1/models`.
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Session cookie expired. Refresher will update on next tick, or run scripts/ollama-cookie-refresher/refresh_session.py manually."
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
