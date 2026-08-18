import Foundation

/// The single Higgsfield datum v1 reads: the account's remaining credits and its subscription plan slug.
/// There is no allowance/quota or reset field anywhere in the API, so this carries balance + plan only.
struct HiggsfieldBalance: Equatable, Sendable {
    var credits: Double
    /// The raw lowercase plan slug (e.g. "plus"); the mapper title-cases it for the Plan badge.
    var planSlug: String?
}

/// Network I/O for Higgsfield. One documented call: `GET /agents/balance` on `fnf.higgsfield.ai` with a
/// Bearer access token, returning `{"email":…,"credits":Double,"subscription_plan_type":slug}`. Other
/// `/account`,`/me`,`/balance` paths 404 and `/agents/transactions` 403, so they aren't used.
struct HiggsfieldUsageClient: Sendable {
    static let balanceURL = URL(string: "https://fnf.higgsfield.ai/agents/balance")!

    var http: HTTPClient

    init(http: HTTPClient = URLSessionHTTPClient()) {
        self.http = http
    }

    func fetchBalance(accessToken: String) async throws -> HiggsfieldBalance {
        let request = HTTPRequest(
            method: "GET",
            url: Self.balanceURL,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Accept": "application/json",
                "User-Agent": "OpenUsage"
            ],
            timeout: 10
        )
        let response: HTTPResponse
        do {
            response = try await http.send(request)
        } catch {
            throw HiggsfieldUsageError.connectionFailed
        }

        if response.statusCode == 401 {
            throw HiggsfieldUsageError.loginExpired
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HiggsfieldUsageError.requestFailed(response.statusCode)
        }
        guard let object = ProviderParse.jsonObject(response.body),
              let credits = ProviderParse.number(object["credits"])
        else {
            throw HiggsfieldUsageError.invalidResponse
        }
        let planSlug = (object["subscription_plan_type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        return HiggsfieldBalance(credits: credits, planSlug: planSlug)
    }
}
