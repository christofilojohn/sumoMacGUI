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
}
