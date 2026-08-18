import XCTest
@testable import OpenUsage

// MARK: - HiggsfieldUsageMapper

final class HiggsfieldUsageMapperTests: XCTestCase {
    private func countValue(_ line: MetricLine?) -> MetricValue? {
        guard case .values(_, let values, _, _, _, _)? = line else { return nil }
        return values.first
    }

    func testBuildLinesProducesCreditsCountAndPlanBadge() {
        let (plan, lines) = HiggsfieldUsageMapper.buildLines(
            HiggsfieldBalance(credits: 850, planSlug: "plus")
        )
        XCTAssertEqual(plan, "Plus")

        let credits = countValue(lines.first { $0.label == "Credits" })
        XCTAssertEqual(credits?.number, 850)
        XCTAssertEqual(credits?.kind, .count)
        XCTAssertEqual(credits?.label, "credits")

        guard case .badge(_, let text, _, _)? = lines.first(where: { $0.label == "Plan" }) else {
            return XCTFail("expected a Plan badge")
        }
        XCTAssertEqual(text, "Plus")
    }

    func testNoPlanSlugOmitsBadgeButKeepsCredits() {
        let (plan, lines) = HiggsfieldUsageMapper.buildLines(
            HiggsfieldBalance(credits: 12, planSlug: nil)
        )
        XCTAssertNil(plan)
        XCTAssertNotNil(lines.first { $0.label == "Credits" })
        XCTAssertNil(lines.first { $0.label == "Plan" })
    }

    func testTitleCasedPlanHandlesEmptyAndNil() {
        XCTAssertNil(HiggsfieldUsageMapper.titleCasedPlan(nil))
        XCTAssertNil(HiggsfieldUsageMapper.titleCasedPlan("   "))
        XCTAssertEqual(HiggsfieldUsageMapper.titleCasedPlan("PLUS"), "Plus")
        XCTAssertEqual(HiggsfieldUsageMapper.titleCasedPlan("enterprise"), "Enterprise")
    }

    func testNegativeCreditsClampToZero() {
        let (_, lines) = HiggsfieldUsageMapper.buildLines(HiggsfieldBalance(credits: -5, planSlug: "plus"))
        XCTAssertEqual(countValue(lines.first { $0.label == "Credits" })?.number, 0)
    }
}

// MARK: - HiggsfieldUsageClient

final class HiggsfieldUsageClientTests: XCTestCase {
    /// The exact live response contract, verified against `fnf.higgsfield.ai/agents/balance`.
    private let balanceJSON = #"{"email":"ty@catalystdigital.app","credits":850.0,"subscription_plan_type":"plus"}"#

    func testFetchBalanceParsesExactLiveFixture() async throws {
        let json = balanceJSON
        let client = HiggsfieldUsageClient(
            http: RoutingHTTPClient { request in
                XCTAssertEqual(request.headers["Authorization"], "Bearer token-value")
                XCTAssertEqual(request.url, HiggsfieldUsageClient.balanceURL)
                return HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8))
            }
        )
        let balance = try await client.fetchBalance(accessToken: "token-value")
        XCTAssertEqual(balance.credits, 850)
        XCTAssertEqual(balance.planSlug, "plus")
    }

    private func expectFetchError(
        status: Int,
        body: Data = Data(),
        expected: HiggsfieldUsageError,
        line: UInt = #line
    ) async {
        let client = HiggsfieldUsageClient(
            http: RoutingHTTPClient { _ in HTTPResponse(statusCode: status, headers: [:], body: body) }
        )
        do {
            _ = try await client.fetchBalance(accessToken: "t")
            XCTFail("expected \(expected)", line: line)
        } catch {
            XCTAssertEqual(error as? HiggsfieldUsageError, expected, line: line)
        }
    }

    func testFetchBalanceOn401ThrowsLoginExpired() async {
        await expectFetchError(status: 401, expected: .loginExpired)
    }

    func testFetchBalanceOnServerErrorThrowsRequestFailed() async {
        await expectFetchError(status: 503, expected: .requestFailed(503))
    }

    func testFetchBalanceOnUnparseableBodyThrowsInvalidResponse() async {
        await expectFetchError(status: 200, body: Data("not json".utf8), expected: .invalidResponse)
    }
}

// MARK: - HiggsfieldAuthStore

final class HiggsfieldAuthStoreTests: XCTestCase {
    private let credentialsPath = "~/.config/higgsfield/credentials.json"

    private func store(files: [String: String]) -> HiggsfieldAuthStore {
        HiggsfieldAuthStore(environment: FakeEnvironment(), files: FakeFiles(files))
    }

    func testMissingFileYieldsNilCredentials() throws {
        XCTAssertNil(try store(files: [:]).loadCredentials())
    }

    func testValidFileLoadsAccessToken() throws {
        let json = #"{"access_token":"abc123","refresh_token":"refresh456"}"#
        let credentials = try store(files: [credentialsPath: json]).loadCredentials()
        XCTAssertEqual(credentials?.accessToken, "abc123")
        XCTAssertEqual(credentials?.refreshToken, "refresh456")
        XCTAssertEqual(credentials?.hasUsableAccessToken, true)
    }

    func testEmptyAccessTokenYieldsNil() throws {
        let json = #"{"access_token":"","refresh_token":"refresh456"}"#
        XCTAssertNil(try store(files: [credentialsPath: json]).loadCredentials())
    }

    func testConfigDirOverrideIsHonored() throws {
        let json = #"{"access_token":"xyz"}"#
        let s = HiggsfieldAuthStore(
            environment: FakeEnvironment(["HIGGSFIELD_CONFIG_DIR": "/tmp/hf"]),
            files: FakeFiles(["/tmp/hf/credentials.json": json])
        )
        XCTAssertEqual(try s.loadCredentials()?.accessToken, "xyz")
    }
}

// MARK: - HiggsfieldProvider

@MainActor
final class HiggsfieldProviderTests: XCTestCase {
    private let credentialsPath = "~/.config/higgsfield/credentials.json"
    private let validCreds = #"{"access_token":"token-value","refresh_token":"r"}"#
    private let balanceJSON = #"{"email":"ty@catalystdigital.app","credits":850.0,"subscription_plan_type":"plus"}"#

    private func provider(files: [String: String], http: @escaping @Sendable (HTTPRequest) async throws -> HTTPResponse) -> HiggsfieldProvider {
        HiggsfieldProvider(
            authStore: HiggsfieldAuthStore(environment: FakeEnvironment(), files: FakeFiles(files)),
            usageClient: HiggsfieldUsageClient(http: RoutingHTTPClient(handler: http))
        )
    }

    func testRefreshWithNoCredentialsReportsNotSignedIn() async {
        let provider = provider(files: [:]) { _ in
            XCTFail("should not hit the network without a credential")
            return HTTPResponse(statusCode: 200, headers: [:], body: Data())
        }
        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .notLoggedIn)
    }

    func testHasLocalCredentialsReflectsFile() async {
        let signedOut = provider(files: [:]) { _ in HTTPResponse(statusCode: 200, headers: [:], body: Data()) }
        let signedIn = provider(files: [credentialsPath: validCreds]) { _ in HTTPResponse(statusCode: 200, headers: [:], body: Data()) }
        let outResult = await signedOut.hasLocalCredentials()
        let inResult = await signedIn.hasLocalCredentials()
        XCTAssertFalse(outResult)
        XCTAssertTrue(inResult)
    }

    func testRefreshWithTokenReportsCreditsAndPlan() async {
        let json = balanceJSON
        let provider = provider(files: [credentialsPath: validCreds]) { request in
            XCTAssertEqual(request.headers["Authorization"], "Bearer token-value")
            return HTTPResponse(statusCode: 200, headers: [:], body: Data(json.utf8))
        }
        let snapshot = await provider.refresh()
        XCTAssertNil(snapshot.errorCategory)
        XCTAssertEqual(snapshot.plan, "Plus")
        XCTAssertNotNil(snapshot.line(label: "Credits"))
        XCTAssertNotNil(snapshot.line(label: "Plan"))
    }

    func testRefreshTreats401AsLoginExpired() async {
        let provider = provider(files: [credentialsPath: validCreds]) { _ in
            HTTPResponse(statusCode: 401, headers: [:], body: Data())
        }
        let snapshot = await provider.refresh()
        XCTAssertEqual(snapshot.errorCategory, .authExpired)
    }
}
