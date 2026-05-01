import XCTest
@testable import SumoGUIMac

@MainActor
final class ViewportStateTests: XCTestCase {
    private func makeFitted() -> ViewportState {
        let viewport = ViewportState()
        viewport.configureToFit(
            netBounds: SIMD4(0, 0, 1_000, 1_000),
            viewSize: CGSize(width: 1_000, height: 1_000),
            inset: 0
        )
        return viewport
    }

    func testConfigureToFitCentersAndScales() {
        let viewport = makeFitted()
        XCTAssertTrue(viewport.isConfigured)
        XCTAssertEqual(viewport.center.x, 500, accuracy: 0.001)
        XCTAssertEqual(viewport.center.y, 500, accuracy: 0.001)
        XCTAssertEqual(viewport.pointsPerWorldUnit, 1, accuracy: 0.001)
    }

    func testZoomInIncreasesScale() {
        let viewport = makeFitted()
        let before = viewport.pointsPerWorldUnit
        viewport.zoom(by: 2, anchorWorld: SIMD2(500, 500))
        XCTAssertGreaterThan(viewport.pointsPerWorldUnit, before)
    }

    func testZoomOutDecreasesScale() {
        let viewport = makeFitted()
        let before = viewport.pointsPerWorldUnit
        viewport.zoom(by: 0.5, anchorWorld: SIMD2(500, 500))
        XCTAssertLessThan(viewport.pointsPerWorldUnit, before)
    }

    func testZoomAroundCenterPreservesCenter() {
        let viewport = makeFitted()
        viewport.zoom(by: 1.5, anchorWorld: viewport.center)
        XCTAssertEqual(viewport.center.x, 500, accuracy: 0.001)
        XCTAssertEqual(viewport.center.y, 500, accuracy: 0.001)
    }

    func testZoomAroundOffCenterAnchorKeepsAnchorStable() {
        let viewport = makeFitted()
        let anchor = SIMD2<Float>(750, 250)
        viewport.zoom(by: 2, anchorWorld: anchor)
        let scale = viewport.pointsPerWorldUnit
        let projected = SIMD2(
            (anchor.x - viewport.center.x) * scale,
            (anchor.y - viewport.center.y) * scale
        )
        let expected = SIMD2<Float>(250 * scale * 0.5, -250 * scale * 0.5)
        XCTAssertEqual(projected.x, expected.x, accuracy: 0.5)
        XCTAssertEqual(projected.y, expected.y, accuracy: 0.5)
    }

    func testZoomNoOpBeforeConfigured() {
        let viewport = ViewportState()
        viewport.zoom(by: 2, anchorWorld: SIMD2(0, 0))
        XCTAssertFalse(viewport.isConfigured)
        XCTAssertEqual(viewport.pointsPerWorldUnit, 1)
    }

    func testPanShiftsCenter() {
        let viewport = makeFitted()
        viewport.pan(worldDelta: SIMD2(50, -25))
        XCTAssertEqual(viewport.center.x, 550, accuracy: 0.001)
        XCTAssertEqual(viewport.center.y, 475, accuracy: 0.001)
    }

    func testZoomFactorClampedToReasonableRange() {
        let viewport = makeFitted()
        let before = viewport.pointsPerWorldUnit
        viewport.zoom(by: 1_000, anchorWorld: viewport.center)
        XCTAssertLessThanOrEqual(viewport.pointsPerWorldUnit / before, 4 + 0.001)
        viewport.zoom(by: 0.0001, anchorWorld: viewport.center)
        XCTAssertGreaterThan(viewport.pointsPerWorldUnit, 0)
    }

    func testRequestFitClearsConfiguredFlag() {
        let viewport = makeFitted()
        var changeCount = 0
        viewport.onChange = { changeCount += 1 }
        viewport.requestFit()
        XCTAssertFalse(viewport.isConfigured)
        XCTAssertEqual(changeCount, 1)
    }

    func testZoomNotifiesOnChange() {
        let viewport = makeFitted()
        var changeCount = 0
        viewport.onChange = { changeCount += 1 }
        viewport.zoom(by: 1.2, anchorWorld: viewport.center)
        XCTAssertEqual(changeCount, 1)
    }

    func testUpdatePinchScalesIncrementally() {
        let viewport = makeFitted()
        let before = viewport.pointsPerWorldUnit
        viewport.updatePinch(magnification: 1.1)
        let mid = viewport.pointsPerWorldUnit
        XCTAssertGreaterThan(mid, before)
        viewport.updatePinch(magnification: 1.5)
        XCTAssertGreaterThan(viewport.pointsPerWorldUnit, mid)
    }

    func testUpdatePinchAfterEndStartsFromUnity() {
        let viewport = makeFitted()
        viewport.updatePinch(magnification: 1.5)
        let afterFirst = viewport.pointsPerWorldUnit
        viewport.endPinch()
        // New gesture starts at 1.0 baseline; tiny first delta should not jump scale.
        viewport.updatePinch(magnification: 1.01)
        XCTAssertEqual(viewport.pointsPerWorldUnit, afterFirst * 1.01, accuracy: afterFirst * 0.05)
    }
}
