import XCTest
@testable import SumoGUIMac

final class NetworkRenderLODTests: XCTestCase {
    func testRendererCoordinateSpaceFlipsUnflippedAppKitLocations() {
        let viewLocation = CGPoint(x: 120, y: 80)

        let rendererLocation = RendererCoordinateSpace.rendererLocation(
            forViewLocation: viewLocation,
            boundsHeight: 500,
            isFlipped: false
        )

        XCTAssertEqual(rendererLocation.x, 120, accuracy: 0.001)
        XCTAssertEqual(rendererLocation.y, 420, accuracy: 0.001)
        XCTAssertEqual(
            RendererCoordinateSpace.rendererLocation(forViewLocation: viewLocation, boundsHeight: 500, isFlipped: true),
            viewLocation
        )
    }

    func testViewTransformRoundTripsRendererCoordinates() {
        let transform = ViewTransform(
            netBounds: SIMD4<Float>(-100, -50, 300, 150),
            viewSize: CGSize(width: 800, height: 600),
            inset: 28,
            center: SIMD2<Float>(100, 50),
            pointsPerWorldUnit: 1.5,
            rotationRadians: .pi / 7
        )
        let world = SIMD2<Float>(42, 84)
        let screen = transform.point(world)
        let roundTripped = transform.worldPoint(forScreenPoint: screen)

        XCTAssertEqual(roundTripped.x, world.x, accuracy: 0.001)
        XCTAssertEqual(roundTripped.y, world.y, accuracy: 0.001)
    }

    func testLaneLODUsesHalfPixelThreshold() {
        XCTAssertFalse(RenderLOD.shouldRenderLane(worldWidth: 3.2, scale: 0.15624))
        XCTAssertTrue(RenderLOD.shouldRenderLane(worldWidth: 3.2, scale: 0.15625))
        XCTAssertFalse(RenderLOD.shouldRenderLane(worldWidth: 0, scale: 1))
        XCTAssertFalse(RenderLOD.shouldRenderLane(worldWidth: 3.2, scale: 0))
    }

    func testLaneDisplayWidthLeavesSeparatorSpaceAtLowZoom() {
        let displayWidth = RenderLOD.laneDisplayWorldWidth(worldWidth: 3.2, scale: 0.3)
        XCTAssertEqual((displayWidth ?? 0) * 0.3, 0.6912, accuracy: 0.001)

        let emphasizedWidth = RenderLOD.laneDisplayWorldWidth(worldWidth: 3.2, scale: 0.3, emphasized: true)
        XCTAssertEqual(emphasizedWidth ?? 0, 3.2, accuracy: 0.001)

        XCTAssertNil(RenderLOD.laneDisplayWorldWidth(worldWidth: 3.2, scale: 0.15624))
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
