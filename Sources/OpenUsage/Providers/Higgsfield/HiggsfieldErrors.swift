import Foundation

/// No usable Higgsfield credential on disk: `~/.config/higgsfield/credentials.json` is missing, empty,
/// or carries no access token.
enum HiggsfieldAuthError: Error, LocalizedError, Equatable {
    case notSignedIn
    /// `credentials.json` exists but couldn't be read or parsed (permissions, encoding, corrupt JSON) —
    /// broken storage, distinct from a genuine logout, so it never masquerades as "not signed in".
    case credentialsUnreadable(detail: String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to Higgsfield. Run `higgsfield auth login`."
        case .credentialsUnreadable:
            return "Couldn't read Higgsfield's credentials.json. Check its permissions, or run `higgsfield auth login` again."
        }
    }
}

enum HiggsfieldUsageError: Error, LocalizedError, Equatable {
    /// The balance endpoint returned 401 — the stored access token expired. v1 does not refresh tokens
    /// (the CLI's device-auth flow lives outside this app), so this surfaces as a friendly re-auth prompt
    /// rather than a silent blank, mirroring Ollama's expired-session handling.
    case loginExpired
    case requestFailed(Int)
    case connectionFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .loginExpired:
            return "Higgsfield login expired — run `higgsfield auth login`."
        case .requestFailed(let status):
            return "Request failed (HTTP \(status)). Try again later."
        case .connectionFailed:
            return "Usage request failed. Check your connection."
        case .invalidResponse:
            return "Response invalid. Try again later."
        }
    }
}
