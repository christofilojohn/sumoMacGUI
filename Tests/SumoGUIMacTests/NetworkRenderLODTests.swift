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

    func testLaneDisplayWidthKeepsScalingAtCloseZoomUntilLargeCap() {
        let closeDisplayWidth = RenderLOD.laneDisplayWorldWidth(worldWidth: 3.2, scale: 10)
        XCTAssertEqual((closeDisplayWidth ?? 0) * 10, 31, accuracy: 0.001)

        let cappedDisplayWidth = RenderLOD.laneDisplayWorldWidth(worldWidth: 3.2, scale: 40)
        XCTAssertEqual((cappedDisplayWidth ?? 0) * 40, 95, accuracy: 0.001)
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

    func testVehicleStrokeContrastsWhenFillMatchesBackground() {
        let background = SIMD3<Float>(0.12, 0.13, 0.14)
        let stroke = VehicleIconContrast.strokeColor(fill: background, background: background)
        let strokeRGB = SIMD3<Float>(stroke.x, stroke.y, stroke.z)

        XCTAssertGreaterThanOrEqual(VehicleIconContrast.contrastRatio(strokeRGB, background), 4.5)
    }

    func testVehicleStrokePreservesEdgeContrastForLightVehiclesOnDarkMap() {
        let fill = SIMD3<Float>(0.96, 0.97, 0.94)
        let background = SIMD3<Float>(0.06, 0.06, 0.07)
        let stroke = VehicleIconContrast.strokeColor(fill: fill, background: background)
        let strokeRGB = SIMD3<Float>(stroke.x, stroke.y, stroke.z)

        XCTAssertGreaterThanOrEqual(VehicleIconContrast.contrastRatio(strokeRGB, fill), 4.5)
    }

    func testVehicleDetailContrastsWithBodyFill() {
        let fill = SIMD3<Float>(0.36, 0.70, 0.88)
        let detail = VehicleIconContrast.detailColor(fill: fill)
        let detailRGB = SIMD3<Float>(detail.x, detail.y, detail.z)

        XCTAssertGreaterThanOrEqual(VehicleIconContrast.contrastRatio(detailRGB, fill), 3.0)
    }

    func testRenderBufferInvalidationIgnoresTinyScaleChanges() {
        XCTAssertFalse(RenderBufferInvalidation.scaleChanged(10, 10.1, relativeTolerance: 0.03))
        XCTAssertTrue(RenderBufferInvalidation.scaleChanged(10, 10.31, relativeTolerance: 0.03))
    }

    func testVehicleBufferInvalidatesWhenLODThresholdIsCrossed() {
        XCTAssertTrue(RenderBufferInvalidation.vehicleScaleChanged(0.399, 0.4, relativeTolerance: 0.03))
    }

    func testVehicleRenderPolicySkipsAnimationWhenVehiclesAreTooDense() {
        XCTAssertTrue(VehicleRenderPolicy.shouldAnimate(vehicleCount: 500, scale: 1))
        XCTAssertFalse(
            VehicleRenderPolicy.shouldAnimate(
                vehicleCount: VehicleRenderPolicy.maximumAnimatedVehicleCount + 1,
                scale: 1
            )
        )
    }

    func testVehicleRenderPolicySkipsAnimationWhenVehiclesAreNotVisible() {
        XCTAssertFalse(VehicleRenderPolicy.shouldAnimate(vehicleCount: 500, scale: 0.1))
    }

    func testVehicleRenderPolicyDropsAnimationFrameRateForLargeVisibleFleets() {
        XCTAssertEqual(VehicleRenderPolicy.animationInterval(vehicleCount: 500), 1.0 / 60.0, accuracy: 0.0001)
        XCTAssertEqual(
            VehicleRenderPolicy.animationInterval(vehicleCount: VehicleRenderPolicy.reducedAnimationVehicleCount + 1),
            1.0 / 30.0,
            accuracy: 0.0001
        )
    }

    func testWorldBoundsCoverageAddsPanHeadroom() {
        let visible = SIMD4<Float>(0, 0, 100, 50)
        let expanded = WorldBoundsCoverage.expanded(visible, scale: 2, screenPadding: 40)

        XCTAssertTrue(WorldBoundsCoverage.contains(expanded, visible))
        XCTAssertTrue(WorldBoundsCoverage.contains(expanded, SIMD2<Float>(-20, 75)))
        XCTAssertFalse(WorldBoundsCoverage.contains(expanded, SIMD2<Float>(-40, 25)))
    }

    func testMaximumProportionalScaleStopsBeforeLaneWidthCap() {
        let scale = RenderLOD.maximumProportionalScale(forLaneWidths: [3.2, 3.2, 3.5, 4.0])

        XCTAssertEqual(scale, 24, accuracy: 0.001)
        XCTAssertLessThan(3.5 * scale, RenderLOD.maximumLaneScreenWidth)
    }

    func testLaneDirectionArrowLODRequiresReadableLaneAndSegmentSize() {
        XCTAssertFalse(LaneDirectionArrows.shouldRender(laneScreenWidth: 2.4, segmentScreenLength: 80, scale: 1))
        XCTAssertFalse(LaneDirectionArrows.shouldRender(laneScreenWidth: 4, segmentScreenLength: 33.9, scale: 1))
        XCTAssertTrue(LaneDirectionArrows.shouldRender(laneScreenWidth: 4, segmentScreenLength: 80, scale: 1))
    }

    func testLaneDirectionArrowPlacementKeepsArrowsAwayFromJunctionEnds() {
        XCTAssertEqual(LaneDirectionArrows.placementFractions(segmentScreenLength: 20), [])

        let single = LaneDirectionArrows.placementFractions(segmentScreenLength: 80)
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0], 0.5, accuracy: 0.001)

        let repeated = LaneDirectionArrows.placementFractions(segmentScreenLength: 260)
        XCTAssertEqual(repeated.count, 2)
        XCTAssertGreaterThan(repeated[0], 0.25)
        XCTAssertLessThan(repeated[1], 0.75)
    }

    func testLaneDirectionArrowSizeGrowsButStaysBounded() {
        let narrow = LaneDirectionArrows.arrowScreenMetrics(laneScreenWidth: 8)
        XCTAssertEqual(narrow.x, 10, accuracy: 0.001)
        XCTAssertEqual(narrow.y, 6, accuracy: 0.001)

        let wide = LaneDirectionArrows.arrowScreenMetrics(laneScreenWidth: 80)
        XCTAssertEqual(wide.x, 32, accuracy: 0.001)
        XCTAssertEqual(wide.y, 20, accuracy: 0.001)
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
