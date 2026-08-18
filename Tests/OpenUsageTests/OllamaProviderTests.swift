import XCTest
@testable import OpenUsage

// MARK: - OllamaHTMLParser

final class OllamaHTMLParserTests: XCTestCase {
    /// Synthetic stand-ins for the `data-usage-meter` hover-bubble block that Ollama's redesigned
    /// `settings` page now inserts between each `% used` label and its reset element. No real account
    /// HTML/PII. Their only job is to push the reset `data-time` far past the old 600-char window so the
    /// fixture reflects the real page's structure (which the pre-fix fixture did not, letting the bug ship).
    /// The two cards get DIFFERENT sizes to mirror the measured live page: the Session reset sits ~2,893
    /// chars past its marker and the Weekly reset ~6,267 — so the Weekly filler is roughly double, letting
    /// the test actually exercise the far end of the 8,000-char window. Both deliberately contain NO
    /// `data-time` attribute of their own.
    private static func usageMeter(cells: Int) -> String {
        let cell = #"<div class="data-usage-meter-cell h-2 w-2 rounded-sm bg-neutral-200" role="presentation"></div>"#
        return #"<div class="data-usage-meter absolute z-10 hidden group-hover:block rounded-lg border p-3 shadow">"#
            + String(repeating: cell, count: cells)
            + "</div>"
    }
    // ~2,900 chars — Session reset lands just past its marker (~2,893 on the live page).
    private static let sessionUsageMeterFiller = usageMeter(cells: 30)
    // ~6,400 chars — Weekly reset lands past ~6,300, mirroring the ~6,267 live offset and stressing the
    // widened window's far end (a 600- or 3,000-char window would miss it).
    private static let weeklyUsageMeterFiller = usageMeter(cells: 66)

    // Real reset markup is a `local-time` div, e.g.
    // `<div class="text-xs text-neutral-500 mt-1 local-time" data-time="2026-07-24T23:00:00Z" > Resets in 1 hour. </div>`
    private let sampleSettingsHTML = """
    <html><body>
    <div class="usage-card">
      <span class="text-sm">Session usage</span>
      <span class="text-sm">14.6% used</span>
      \(OllamaHTMLParserTests.sessionUsageMeterFiller)
      <div class="text-xs text-neutral-500 mt-1 local-time" data-time="2026-04-27T02:00:00Z" > Resets in 1 hour. </div>
    </div>
    <div class="usage-card">
      <span class="text-sm">Weekly usage</span>
      <span class="text-sm">62.3% used</span>
      \(OllamaHTMLParserTests.weeklyUsageMeterFiller)
      <div class="text-xs text-neutral-500 mt-1 local-time" data-time="2026-05-01T00:00:00Z" > Resets in 2 days. </div>
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

    /// Regression for the reset-time parsing bug: the redesigned `settings` page pushes each reset element
    /// ~3,000+ chars past its `% used` label (behind the `data-usage-meter` tooltip). The old 600-char
    /// window missed both `data-time`s, so `resetsAt` came back nil and the UI showed the hardcoded 5h/7d
    /// fallback. This asserts both resets parse to their own distinct instants and that Session does NOT
    /// bleed into Weekly's `data-time`.
    func testParsesResetTimesPastUsageMeterBlock() {
        // Guard the fixture actually reproduces the real page: the Session reset sits well past the old
        // 600-char window, and the Weekly reset sits past ~6,300 — matching the live ~6,267 offset. This
        // is what makes the test bite the widened 8,000-char window (a 600- or 3,000-char window fails it).
        let sessionMarkerEnd = sampleSettingsHTML.range(of: "Session usage</span>")!.upperBound
        let sessionResetStart = sampleSettingsHTML.range(of: "data-time=\"2026-04-27T02:00:00Z\"")!.lowerBound
        let sessionOffset = sampleSettingsHTML.distance(from: sessionMarkerEnd, to: sessionResetStart)
        XCTAssertGreaterThan(sessionOffset, 600, "Session reset must sit past the old 600-char window")

        let weeklyMarkerEnd = sampleSettingsHTML.range(of: "Weekly usage</span>")!.upperBound
        let weeklyResetStart = sampleSettingsHTML.range(of: "data-time=\"2026-05-01T00:00:00Z\"")!.lowerBound
        let weeklyOffset = sampleSettingsHTML.distance(from: weeklyMarkerEnd, to: weeklyResetStart)
        XCTAssertGreaterThan(weeklyOffset, 6000, "Weekly reset must sit past ~6,000 chars, mirroring the live page")

        let parsed = OllamaHTMLParser.parse(sampleSettingsHTML)
        let session = OpenUsageISO8601.date(from: "2026-04-27T02:00:00Z")
        let weekly = OpenUsageISO8601.date(from: "2026-05-01T00:00:00Z")
        XCTAssertEqual(parsed.sessionResetsAt, session)
        XCTAssertEqual(parsed.weeklyResetsAt, weekly)
        XCTAssertNotNil(parsed.sessionResetsAt)
        XCTAssertNotNil(parsed.weeklyResetsAt)
        // Session must resolve to its own reset, not accidentally pick up Weekly's later data-time.
        XCTAssertNotEqual(parsed.sessionResetsAt, weekly)
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
