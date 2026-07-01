import XCTest
@testable import OpenUsage

final class ClaudeSecondaryEnvironmentReaderTests: XCTestCase {
    func testOverridesConfigDirRegardlessOfRealEnvironment() {
        let base = FakeEnvironment(["CLAUDE_CONFIG_DIR": "/should/be/ignored"])
        let reader = ClaudeSecondaryEnvironmentReader(base: base)
        XCTAssertEqual(reader.value(for: "CLAUDE_CONFIG_DIR"), expandHome("~/.claude-2nd"))
    }

    func testDelegatesEveryOtherKeyToBase() {
        let base = FakeEnvironment(["USER_TYPE": "ant", "USE_STAGING_OAUTH": "1"])
        let reader = ClaudeSecondaryEnvironmentReader(base: base)
        XCTAssertEqual(reader.value(for: "USER_TYPE"), "ant")
        XCTAssertEqual(reader.value(for: "USE_STAGING_OAUTH"), "1")
        XCTAssertNil(reader.value(for: "SOME_UNRELATED_VAR"))
    }

    /// The override must be the expanded absolute path, never the literal tilde form — see the doc
    /// comment on `ClaudeSecondaryEnvironmentReader` for why: `ClaudeAuthStore.keychainServiceCandidates()`
    /// hashes this value to find the Keychain service Claude Code itself wrote the second login under,
    /// and Claude Code's own `CLAUDE_CONFIG_DIR` is always the shell-expanded absolute path.
    func testConfigDirOverrideIsExpandedNotLiteral() {
        let reader = ClaudeSecondaryEnvironmentReader(base: FakeEnvironment())
        let value = reader.value(for: "CLAUDE_CONFIG_DIR")
        XCTAssertNotEqual(value, "~/.claude-2nd")
        XCTAssertEqual(value?.hasPrefix("~"), false)
        XCTAssertEqual(value?.hasSuffix("/.claude-2nd"), true)
    }
}

@MainActor
final class ClaudeSecondaryProviderTests: XCTestCase {
    func testDistinctIdentity() {
        let secondary = ClaudeSecondaryProvider.make()
        XCTAssertEqual(secondary.provider.id, "claude-2")
        XCTAssertEqual(secondary.provider.displayName, "Claude (Account 2)")
    }

    /// Every widget id must be namespaced by the provider id so the two Claude instances never collide
    /// in `WidgetRegistry`/`LayoutStore` — this is what makes running two `ClaudeProvider` instances safe.
    func testWidgetIDsNeverCollideWithPrimaryAccount() {
        let primary = ClaudeProvider()
        let secondary = ClaudeSecondaryProvider.make()

        let primaryIDs = Set(primary.widgetDescriptors.map(\.id))
        let secondaryIDs = Set(secondary.widgetDescriptors.map(\.id))

        XCTAssertTrue(secondaryIDs.allSatisfy { $0.hasPrefix("claude-2.") })
        XCTAssertTrue(primaryIDs.isDisjoint(with: secondaryIDs))
        XCTAssertEqual(primaryIDs.count, secondaryIDs.count)
    }
}
