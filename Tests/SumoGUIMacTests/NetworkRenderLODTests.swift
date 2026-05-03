import XCTest
@testable import SumoGUIMac

final class NetworkRenderLODTests: XCTestCase {
    func testLaneLODUsesHalfPixelThreshold() {
        XCTAssertFalse(RenderLOD.shouldRenderLane(worldWidth: 3.2, scale: 0.15624))
        XCTAssertTrue(RenderLOD.shouldRenderLane(worldWidth: 3.2, scale: 0.15625))
        XCTAssertFalse(RenderLOD.shouldRenderLane(worldWidth: 0, scale: 1))
        XCTAssertFalse(RenderLOD.shouldRenderLane(worldWidth: 3.2, scale: 0))
    }

    func testVehicleLODUsesTwoPixelShapeThreshold() {
        XCTAssertNil(RenderLOD.vehicleScreenSize(scale: 0.399))

        let thresholdSize = RenderLOD.vehicleScreenSize(scale: 0.4)
        XCTAssertEqual(thresholdSize?.x ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(thresholdSize?.y ?? 0, 0.8, accuracy: 0.001)

        let zoomedSize = RenderLOD.vehicleScreenSize(scale: 2)
        XCTAssertEqual(zoomedSize?.x ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(zoomedSize?.y ?? 0, 4, accuracy: 0.001)
    }

    func testSUMOHeadingConvertsToScreenCoordinates() {
        XCTAssertEqual(VehicleHeading.screenRadians(sumoDegrees: 0, viewportRotationRadians: 0), -.pi / 2, accuracy: 0.001)
        XCTAssertEqual(VehicleHeading.screenRadians(sumoDegrees: 90, viewportRotationRadians: 0), 0, accuracy: 0.001)
        XCTAssertEqual(VehicleHeading.screenRadians(sumoDegrees: 180, viewportRotationRadians: 0), .pi / 2, accuracy: 0.001)
        XCTAssertEqual(
            VehicleHeading.screenRadians(sumoDegrees: 90, viewportRotationRadians: .pi / 2),
            -.pi / 2,
            accuracy: 0.001
        )
    }

    func testMovementHeadingUsesSUMOAngleConvention() {
        XCTAssertEqual(
            VehicleHeading.sumoDegrees(from: SIMD2<Float>(0, 0), to: SIMD2<Float>(0, 10)) ?? -1,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VehicleHeading.sumoDegrees(from: SIMD2<Float>(0, 0), to: SIMD2<Float>(10, 0)) ?? -1,
            90,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VehicleHeading.sumoDegrees(from: SIMD2<Float>(0, 0), to: SIMD2<Float>(0, -10)) ?? -1,
            180,
            accuracy: 0.001
        )
        XCTAssertEqual(
            VehicleHeading.sumoDegrees(from: SIMD2<Float>(0, 0), to: SIMD2<Float>(-10, 0)) ?? -1,
            270,
            accuracy: 0.001
        )
    }

    func testHeadingInterpolationUsesShortestTurnAndMovementBias() {
        XCTAssertEqual(VehicleHeading.mixDegrees(350, 10, progress: 0.5), 0, accuracy: 0.001)

        let biased = VehicleHeading.interpolatedSUMODegrees(
            from: 0,
            to: 90,
            sourcePosition: SIMD2<Float>(0, 0),
            targetPosition: SIMD2<Float>(10, 0),
            progress: 0.5
        )
        XCTAssertGreaterThan(biased, 45)
        XCTAssertLessThan(biased, 90)
    }
}
