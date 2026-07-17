import Foundation

/// Raw `/v1/models` result: the model ids (lower-cased, for plan inference) and the total count (for the
/// "Models available" badge).
struct OllamaModelsResponse: Sendable {
    var modelIDs: [String]
    var count: Int
}

/// All network I/O for Ollama Cloud. There is no documented usage API, so the primary path scrapes the
/// rendered `ollama.com/settings` HTML using a session cookie; `/v1/models` (a real, documented endpoint)
/// backs the API-key fallback and the best-effort "Models available" badge.
struct OllamaUsageClient: Sendable {
    static let settingsURL = URL(string: "https://ollama.com/settings")!
    static let modelsURL = URL(string: "https://ollama.com/v1/models")!
    // A real browser UA — ollama.com's settings page is gated behind bot-detection heuristics that a
    // bare Foundation UA fails.
    static let browserUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    /// Never follows redirects — see `NoRedirectHTTPClient`.
    var settingsHTTP: HTTPClient
    var http: HTTPClient

    init(
        settingsHTTP: HTTPClient = NoRedirectHTTPClient(),
        http: HTTPClient = URLSessionHTTPClient()
    ) {
        self.settingsHTTP = settingsHTTP
        self.http = http
    }

    /// GET `ollama.com/settings` with the session cookie. Redirects are NOT followed: a 302/303 to the
    /// sign-in page is how a stale cookie is detected, and silently following it would return the sign-in
    /// page's own 200 instead.
    func fetchSettings(cookie: String) async throws -> HTTPResponse {
        let request = HTTPRequest(
            method: "GET",
            url: Self.settingsURL,
            headers: [
                "Cookie": "__Secure-session=\(cookie)",
                "User-Agent": Self.browserUserAgent,
                "Accept": "text/html"
            ],
            timeout: 15
        )
        do {
            return try await settingsHTTP.send(request)
        } catch {
            throw OllamaUsageError.connectionFailed
        }
    }

    /// GET `/v1/models` with the API key. Used both as the full fallback path (infer plan from the model
    /// list) and, on the cookie path, as a best-effort "Models available" badge.
    func fetchModels(apiKey: String) async throws -> OllamaModelsResponse {
        let request = HTTPRequest(
            method: "GET",
            url: Self.modelsURL,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json",
                "User-Agent": "OpenUsage"
            ],
            timeout: 10
        )
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw OllamaUsageError.connectionFailed
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw OllamaUsageError.invalidKey
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OllamaUsageError.requestFailed(response.statusCode)
        }
        guard let object = ProviderParse.jsonObject(response.body) else {
            throw OllamaUsageError.invalidResponse
        }
        let list = (object["data"] as? [[String: Any]]) ?? (object["models"] as? [[String: Any]]) ?? []
        let ids = list.compactMap { entry in
            (entry["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().nilIfEmpty
        }
        return OllamaModelsResponse(modelIDs: ids, count: list.count)
    }
}

/// A dedicated `HTTPClient` that never follows redirects (plain `URLSessionHTTPClient` always does).
/// Needed only by `fetchSettings`: a 302/303 IS the signal a stale session cookie sends, so it must come
/// back as the redirect response itself rather than resolved to the sign-in page it points at.
struct NoRedirectHTTPClient: HTTPClient {
    private static let session: URLSession = {
        URLSession(configuration: .ephemeral, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }()

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await Self.session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key).lowercased()] = String(describing: value)
        }

        // Same redaction discipline as `URLSessionHTTPClient`: never log the Cookie header or body.
        AppLog.debug(.http, "\(request.method) \(LogRedaction.redactURL(request.url.absoluteString)) -> \(http.statusCode)")
        return HTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
    }
}

/// Declines every redirect so the caller sees the redirect response's own status code (e.g. 302 to
/// sign-in) instead of the URLSession-followed destination. Holds no mutable state, so it's safe to share.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
