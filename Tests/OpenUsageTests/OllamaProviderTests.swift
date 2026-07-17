import XCTest
@testable import OpenUsage

// MARK: - OllamaHTMLParser

final class OllamaHTMLParserTests: XCTestCase {
    private let sampleSettingsHTML = """
    <html><body>
    <div class="usage-card">
      <span class="text-sm">Session usage</span>
      <span class="text-sm">14.6% used</span>
      <div class="reset" data-time="2026-04-27T02:00:00Z"></div>
    </div>
    <div class="usage-card">
      <span class="text-sm">Weekly usage</span>
      <span class="text-sm">62.3% used</span>
      <div class="reset" data-time="2026-05-01T00:00:00Z"></div>
    </div>
    <div class="cloud-usage">Cloud Usage
      <span
        class="foo capitalize"
        >pro</span
      >
    </div>
    </body></html>
    """

    func testParsesSessionWeeklyAndPlan() {
        let parsed = OllamaHTMLParser.parse(sampleSettingsHTML)
        XCTAssertEqual(parsed.sessionPercent, 14.6)
        XCTAssertEqual(parsed.weeklyPercent, 62.3)
        XCTAssertEqual(parsed.sessionResetsAt, OpenUsageISO8601.date(from: "2026-04-27T02:00:00Z"))
        XCTAssertEqual(parsed.weeklyResetsAt, OpenUsageISO8601.date(from: "2026-05-01T00:00:00Z"))
        XCTAssertEqual(parsed.plan, "Pro")
    }

    func testMissingMarkersYieldNilRatherThanCrash() {
        let parsed = OllamaHTMLParser.parse("<html><body>nothing usable here</body></html>")
        XCTAssertNil(parsed.sessionPercent)
        XCTAssertNil(parsed.weeklyPercent)
        XCTAssertNil(parsed.sessionResetsAt)
        XCTAssertNil(parsed.plan)
    }

    func testWholeNumberPercent() {
        let html = #"<span class="text-sm">Session usage</span><span>100% used</span>"#
        XCTAssertEqual(OllamaHTMLParser.parse(html).sessionPercent, 100)
    }

    func testLooksLikeSignInPageDetectsCommonGiveaways() {
        XCTAssertTrue(OllamaHTMLParser.looksLikeSignInPage("<h1>Sign in to Ollama</h1>"))
        XCTAssertTrue(OllamaHTMLParser.looksLikeSignInPage(#"<form action="/signin" method="post">"#))
        XCTAssertTrue(OllamaHTMLParser.looksLikeSignInPage(#"<input name="password" type="password">"#))
    }

    func testLooksLikeSignInPageFalseOnRealSettingsHTML() {
        XCTAssertFalse(OllamaHTMLParser.looksLikeSignInPage(sampleSettingsHTML))
    }
}

// MARK: - OllamaUsageMapper

final class OllamaUsageMapperTests: XCTestCase {
    private func used(_ line: MetricLine?) -> Double? {
        guard case .progress(_, let used, _, _, _, _, _)? = line else { return nil }
        return used
    }

    func testBuildSettingsLinesProducesSessionWeeklyAndPlanBadge() {
        let parsed = OllamaHTMLParser.SettingsUsage(
            sessionPercent: 14.6, sessionResetsAt: nil,
            weeklyPercent: 62.3, weeklyResetsAt: nil,
            plan: "Pro"
        )
        let (plan, lines) = OllamaUsageMapper.buildSettingsLines(parsed, planHint: nil)
        XCTAssertEqual(plan, "Pro")
        XCTAssertEqual(used(lines.first { $0.label == "Session" }), 14.6)
        XCTAssertEqual(used(lines.first { $0.label == "Weekly" }), 62.3)
        XCTAssertTrue(lines.contains { $0.label == "Plan" })
    }

    func testExplicitPlanHintBeatsScrapedPlan() {
        let parsed = OllamaHTMLParser.SettingsUsage(sessionPercent: nil, sessionResetsAt: nil, weeklyPercent: nil, weeklyResetsAt: nil, plan: "Team")
        let (plan, _) = OllamaUsageMapper.buildSettingsLines(parsed, planHint: "Enterprise")
        XCTAssertEqual(plan, "Enterprise")
    }

    func testNoUsageMarkersProducesNoLines() {
        let parsed = OllamaHTMLParser.SettingsUsage(sessionPercent: nil, sessionResetsAt: nil, weeklyPercent: nil, weeklyResetsAt: nil, plan: nil)
        let (plan, lines) = OllamaUsageMapper.buildSettingsLines(parsed, planHint: nil)
        XCTAssertNil(plan)
        XCTAssertTrue(lines.isEmpty)
    }

    func testInferredPlanDetectsProMarkerModel() {
        XCTAssertEqual(OllamaUsageMapper.inferredPlan(planHint: nil, modelIDs: ["llama3", "kimi-k2.6"]), "Pro")
    }

    func testInferredPlanDefaultsToFreeWithoutMarkers() {
        XCTAssertEqual(OllamaUsageMapper.inferredPlan(planHint: nil, modelIDs: ["llama3"]), "Free")
    }

    func testInferredPlanHintOverridesInference() {
        XCTAssertEqual(OllamaUsageMapper.inferredPlan(planHint: "Team", modelIDs: ["kimi-k2.6"]), "Team")
    }
}

// MARK: - OllamaProvider

@MainActor
final class OllamaProviderTests: XCTestCase {
    func testRefreshWithNoCredentialsReportsNotSignedIn() async {
        let provider = OllamaProvider(
            authStore: OllamaAuthStore(keychain: ServiceKeychain(), environment: FakeEnvironment()),
            usageClient: OllamaUsageClient(
                settingsHTTP: RoutingHTTPClient { _ in
                    XCTFail("should not hit the network without any credential")
                    return HTTPResponse(statusCode: 200, headers: [:], body: Data())
                }
            )
        )

        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .notLoggedIn)
    }

    func testRefreshWithCookieScrapesSettingsPage() async {
        let html = """
        <span class="text-sm">Session usage</span><span>14.6% used</span>
        <span class="text-sm">Weekly usage</span><span>62.3% used</span>
        """
        let provider = OllamaProvider(
            authStore: OllamaAuthStore(
                keychain: ServiceKeychain(values: ["ollama-session-cookie": "cookie-value"]),
                environment: FakeEnvironment()
            ),
            usageClient: OllamaUsageClient(
                settingsHTTP: RoutingHTTPClient { request in
                    XCTAssertEqual(request.headers["Cookie"], "__Secure-session=cookie-value")
                    return HTTPResponse(statusCode: 200, headers: [:], body: Data(html.utf8))
                }
            )
        )

        let snapshot = await provider.refresh()
        XCTAssertNil(snapshot.errorCategory)
        XCTAssertNotNil(snapshot.line(label: "Session"))
        XCTAssertNotNil(snapshot.line(label: "Weekly"))
    }

    func testRefreshTreatsRedirectAsExpiredSession() async {
        let provider = OllamaProvider(
            authStore: OllamaAuthStore(
                keychain: ServiceKeychain(values: ["ollama-session-cookie": "stale-cookie"]),
                environment: FakeEnvironment()
            ),
            usageClient: OllamaUsageClient(
                settingsHTTP: RoutingHTTPClient { _ in
                    HTTPResponse(statusCode: 302, headers: ["location": "/signin"], body: Data())
                }
            )
        )

        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .authExpired)
    }

    /// Regression: some deployments serve the sign-in page directly under a 200 instead of a 302/303
    /// redirect. Without the defensive check this fell through to a silent "No data" badge instead of
    /// surfacing "session expired" — the reviewer-flagged gap this test locks in the fix for.
    func testRefreshTreats200SignInPageAsExpiredSession() async {
        let signInHTML = "<html><body><h1>Sign in to Ollama</h1></body></html>"
        let provider = OllamaProvider(
            authStore: OllamaAuthStore(
                keychain: ServiceKeychain(values: ["ollama-session-cookie": "stale-cookie"]),
                environment: FakeEnvironment()
            ),
            usageClient: OllamaUsageClient(
                settingsHTTP: RoutingHTTPClient { _ in
                    HTTPResponse(statusCode: 200, headers: [:], body: Data(signInHTML.utf8))
                }
            )
        )

        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .authExpired)
    }

    func testRefreshFallsBackToAPIKeyWithoutCookie() async {
        let modelsJSON = #"{"data":[{"id":"llama3"},{"id":"kimi-k2.6"}]}"#
        let provider = OllamaProvider(
            authStore: OllamaAuthStore(
                keychain: ServiceKeychain(values: ["ollama-api-key": "key-value"]),
                environment: FakeEnvironment()
            ),
            usageClient: OllamaUsageClient(
                http: RoutingHTTPClient { request in
                    XCTAssertEqual(request.headers["Authorization"], "Bearer key-value")
                    return HTTPResponse(statusCode: 200, headers: [:], body: Data(modelsJSON.utf8))
                }
            )
        )

        let snapshot = await provider.refresh()
        XCTAssertNil(snapshot.errorCategory)
        XCTAssertEqual(snapshot.plan, "Pro")
        XCTAssertNotNil(snapshot.line(label: "Models"))
    }
}
