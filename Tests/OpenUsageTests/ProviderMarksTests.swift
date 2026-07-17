import XCTest
@testable import OpenUsage

@MainActor
final class ProviderMarksTests: XCTestCase {
    func testGrokResolvesToVectorMarkNotBoltFallback() {
        let mark = ProviderMarks.mark(for: "grok")
        XCTAssertNotNil(mark, "Grok must load a real vector mark instead of the bolt.fill fallback")
        XCTAssertFalse(mark?.path.isEmpty ?? true, "Grok mark must carry SVG path data")
    }

    func testDevinResolvesToVectorMark() {
        let mark = ProviderMarks.mark(for: "devin")
        XCTAssertNotNil(mark)
        XCTAssertFalse(mark?.path.isEmpty ?? true, "Devin mark must carry SVG path data")
    }

    func testStandardProviderMarksLoad() {
        for id in ["claude", "codex", "cursor"] {
            let mark = ProviderMarks.mark(for: id)
            XCTAssertNotNil(mark, "\(id) should load")
            XCTAssertFalse(mark?.path.isEmpty ?? true, "\(id) mark must carry SVG path data")
        }
    }

    func testOllamaResolvesToVectorMark() {
        let mark = ProviderMarks.mark(for: "ollama")
        XCTAssertNotNil(mark, "Ollama must load a real vector mark instead of the cloud fallback")
        XCTAssertFalse(mark?.path.isEmpty ?? true, "Ollama mark must carry SVG path data")
    }

    /// The Ollama mark is arc-heavy (`A`/`a` commands). Before arc support the parser broke at the
    /// first arc and produced an empty path, so the icon rendered invisible. Guard the real bounds.
    func testOllamaArcPathParsesToNonEmptyBounds() {
        let mark = ProviderMarks.mark(for: "ollama")
        let bounds = SVGPath.parse(mark?.path ?? "").cgPath.boundingBoxOfPath
        XCTAssertGreaterThan(bounds.width, 0, "Ollama arc path must parse into a non-empty shape")
        XCTAssertGreaterThan(bounds.height, 0, "Ollama arc path must parse into a non-empty shape")
    }

    /// Pins the actual arc geometry, not just non-emptiness: a semicircle from (0,0) to (100,0)
    /// with rx=ry=50 and sweep=1 (`largeArc=0`) must bow through the bottom of the circle — a
    /// mirrored sweep, a swapped/garbled radius, or a wrong-direction rotation would still parse
    /// to a non-empty box (the regression `testOllamaArcPathParsesToNonEmptyBounds` guards) but
    /// would land on the wrong side or at the wrong scale, which only a bounds check like this one
    /// catches. Center of the arc sits at the (0,0)-(100,0) midpoint, (50, 0); sweep=1 traces the
    /// half below it (per SVG's endpoint-to-center parameterization, F.6.5), so the box is
    /// (minX: 0, minY: -50, width: 100, height: 50). Accuracy is loosened slightly past the
    /// nominal 1e-3 to absorb the cubic-Bézier arc approximation's known ~0.03%-of-radius error.
    func testArcSweepProducesExpectedSemicircleBounds() {
        let path = SVGPath.parse("M 0 0 A 50 50 0 0 1 100 0")
        let bounds = path.cgPath.boundingBoxOfPath

        XCTAssertEqual(bounds.minX, 0, accuracy: 0.01, "semicircle should start at x=0")
        XCTAssertEqual(bounds.minY, -50, accuracy: 0.01, "sweep=1 should bow through the bottom of the circle")
        XCTAssertEqual(bounds.width, 100, accuracy: 0.01, "chord length must match the endpoint span")
        XCTAssertEqual(bounds.height, 50, accuracy: 0.01, "radius must not be mirrored or rescaled")
    }
}
