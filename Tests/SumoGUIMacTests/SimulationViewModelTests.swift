import XCTest
@testable import SumoGUIMac
@testable import SumoKit

@MainActor
final class SimulationViewModelTests: XCTestCase {
    func testViewportSubscriptionPlannerChoosesVisibleJunctionAndBoundedRange() {
        let graph = NetGraph()
        graph.location.convBoundary = SIMD4(0, 0, 1_000, 1_000)
        graph.junctions.append(Junction(
            id: "far",
            type: "priority",
            position: SIMD2(900, 900),
            shapeOffset: 0,
            shapeCount: 0,
            bounds: SIMD4(900, 900, 900, 900),
            incomingLanes: [],
            internalLanes: []
        ))
        graph.junctions.append(Junction(
            id: "near",
            type: "priority",
            position: SIMD2(110, 110),
            shapeOffset: 0,
            shapeCount: 0,
            bounds: SIMD4(110, 110, 110, 110),
            incomingLanes: [],
            internalLanes: []
        ))

        let request = ViewportSubscriptionPlanner.request(
            graph: graph,
            indexes: graph.makeSpatialIndexes(),
            visibleBounds: SIMD4(0, 0, 200, 200)
        )

        XCTAssertEqual(request?.anchorJunctionID, "near")
        XCTAssertGreaterThanOrEqual(request?.range ?? 0, 50)
        XCTAssertLessThan(request?.range ?? .infinity, 180)
    }

    func testStopHaltsButKeepsSessionAlive() async throws {
        guard SumoLauncher.locateBinary() != nil else {
            throw XCTSkip("SUMO not installed")
        }

        let config = try makeTinyScenario()
        let viewModel = SimulationViewModel()

        await viewModel.load(url: config)
        XCTAssertTrue(viewModel.canRunSimulation)

        await viewModel.stepOnceNow()
        let runningTime = viewModel.liveState.simTime

        await viewModel.stop()
        XCTAssertTrue(viewModel.canRunSimulation, "stop should halt the simulation without tearing down the session")
        XCTAssertFalse(viewModel.isPlaying)

        await viewModel.stepOnceNow()
        XCTAssertGreaterThan(viewModel.liveState.simTime, runningTime, "step should continue the same simulation after stop")
    }

    private func makeTinyScenario() throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sumoguiapp-vm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let net = """
        <?xml version="1.0" encoding="UTF-8"?>
        <net version="1.20">
            <location netOffset="0.00,0.00" convBoundary="0.00,0.00,200.00,0.00" origBoundary="0.00,0.00,200.00,0.00" projParameter="!"/>
            <edge id=":j1_0" function="internal">
                <lane id=":j1_0_0" index="0" speed="13.89" length="0.10" shape="100.00,-1.60 100.00,-1.60"/>
            </edge>
            <edge id="e1" from="j0" to="j1" priority="1">
                <lane id="e1_0" index="0" speed="13.89" length="100.00" shape="0.00,-1.60 100.00,-1.60"/>
            </edge>
            <edge id="e2" from="j1" to="j2" priority="1">
                <lane id="e2_0" index="0" speed="13.89" length="100.00" shape="100.00,-1.60 200.00,-1.60"/>
            </edge>
            <junction id="j0" type="dead_end" x="0.00" y="0.00" incLanes="" intLanes="" shape="-0.00,0.00 -0.00,-3.20"/>
            <junction id="j1" type="priority" x="100.00" y="0.00" incLanes="e1_0" intLanes=":j1_0_0" shape="100.00,0.00 100.00,-3.20 100.00,0.00">
                <request index="0" response="0" foes="0" cont="0"/>
            </junction>
            <junction id="j2" type="dead_end" x="200.00" y="0.00" incLanes="e2_0" intLanes="" shape="200.00,-3.20 200.00,0.00"/>
            <connection from="e1" to="e2" fromLane="0" toLane="0" via=":j1_0_0" dir="s" state="M"/>
            <connection from=":j1_0" to="e2" fromLane="0" toLane="0" dir="s" state="M"/>
        </net>
        """

        let routes = """
        <routes>
            <vType id="car" accel="2.6" decel="4.5" length="5" maxSpeed="13.89"/>
            <route id="r" edges="e1 e2"/>
            <vehicle id="v0" type="car" route="r" depart="0"/>
            <vehicle id="v1" type="car" route="r" depart="1"/>
        </routes>
        """

        let config = """
        <configuration>
            <input>
                <net-file value="tiny.net.xml"/>
                <route-files value="tiny.rou.xml"/>
            </input>
            <time><begin value="0"/><end value="30"/></time>
        </configuration>
        """

        try net.write(to: tmp.appendingPathComponent("tiny.net.xml"), atomically: true, encoding: .utf8)
        try routes.write(to: tmp.appendingPathComponent("tiny.rou.xml"), atomically: true, encoding: .utf8)
        try config.write(to: tmp.appendingPathComponent("cfg.sumocfg"), atomically: true, encoding: .utf8)
        return tmp.appendingPathComponent("cfg.sumocfg")
    }
}
