import AppKit
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

    func testPlaybackSpeedFactorUsesSimulationDeltaOverWallDelta() {
        let viewModel = SimulationViewModel()

        viewModel.recordPlaybackStep(simTime: 10, wallTime: 100)
        XCTAssertEqual(viewModel.playbackSpeedFactor, 0)

        viewModel.recordPlaybackStep(simTime: 12, wallTime: 100.5)
        XCTAssertEqual(viewModel.playbackSpeedFactor, 4, accuracy: 0.001)

        viewModel.resetPlaybackSpeed()
        XCTAssertEqual(viewModel.playbackSpeedFactor, 0)
    }

    func testPlaybackDelayIsClampedToMinimumFrameDelay() {
        let viewModel = SimulationViewModel()

        viewModel.stepDelay = 0
        XCTAssertEqual(viewModel.playbackDelayNanoseconds(), 20_000_000)

        viewModel.stepDelay = 0.25
        XCTAssertEqual(viewModel.playbackDelayNanoseconds(), 250_000_000)
        XCTAssertEqual(viewModel.playbackLoopDelayNanoseconds(), 250_000_000)
    }

    func testDefaultVisualizationModesMatchCurrentRendererBehavior() {
        let viewModel = SimulationViewModel()

        XCTAssertEqual(viewModel.laneColorMode, .speedLimit)
        XCTAssertEqual(viewModel.vehicleColorMode, .speed)
        XCTAssertEqual(viewModel.junctionColorMode, .type)
        XCTAssertTrue(viewModel.showLaneDirectionArrows)
        XCTAssertEqual(LaneColorMode.allCases.map(\.title), ["By Allowed Speed", "By Lane Number", "By Occupancy", "By Edge Type", "Uniform"])
        XCTAssertEqual(VehicleColorMode.allCases.map(\.title), ["By Speed", "By Acceleration", "By Route", "By Type", "By CO2", "By Color Attribute", "Uniform"])
        XCTAssertEqual(JunctionColorMode.allCases.map(\.title), ["By Type", "By Load", "Uniform"])
    }

    func testVisualizationSettingsXMLRoundTrip() throws {
        var snapshot = VisualizationSettingsSnapshot()
        snapshot.laneColorMode = .occupancy
        snapshot.vehicleColorMode = .co2
        snapshot.junctionColorMode = .load
        snapshot.showLaneDirectionArrows = false
        snapshot.showPolygons = false
        snapshot.backgroundPath = "/tmp/decal.png"
        snapshot.backgroundWorldRect = SIMD4(1, 2, 3, 4)
        snapshot.palette.vehicleUniform = VisualizationColor(red: 0.1, green: 0.2, blue: 0.3)

        let parsed = try VisualizationSettingsSnapshot.parse(data: snapshot.xmlData())

        XCTAssertEqual(parsed.laneColorMode, .occupancy)
        XCTAssertEqual(parsed.vehicleColorMode, .co2)
        XCTAssertEqual(parsed.junctionColorMode, .load)
        XCTAssertFalse(parsed.showLaneDirectionArrows)
        XCTAssertFalse(parsed.showPolygons)
        XCTAssertEqual(parsed.backgroundPath, "/tmp/decal.png")
        XCTAssertEqual(parsed.backgroundWorldRect, SIMD4<Float>(1, 2, 3, 4))
        XCTAssertEqual(parsed.palette.vehicleUniform.red, 0.1, accuracy: 0.01)
        XCTAssertEqual(parsed.palette.vehicleUniform.green, 0.2, accuracy: 0.01)
        XCTAssertEqual(parsed.palette.vehicleUniform.blue, 0.3, accuracy: 0.01)
    }

    func testNetEditLaunchPlanUsesNativeInputFlags() {
        let config = URL(fileURLWithPath: "/tmp/example.sumocfg")
        let network = URL(fileURLWithPath: "/tmp/example.net.xml")

        XCTAssertEqual(NetEditLaunchPlan(url: config).arguments, ["--sumocfg-file", "/tmp/example.sumocfg"])
        XCTAssertEqual(NetEditLaunchPlan(url: network).arguments, ["-s", "/tmp/example.net.xml"])
    }

    func testNativeNetworkEditorCreatesJunctionsEdgesAndPreviewGraph() async {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(0, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(80, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.setNativeEditTool(.edge)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(0, 0),
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(80, 0),
            junctionID: "J1",
            edgeID: nil
        ))

        XCTAssertTrue(viewModel.nativeNetworkEditingEnabled)
        XCTAssertEqual(viewModel.nativeEditor.junctions.map(\.id), ["J0", "J1"])
        XCTAssertEqual(viewModel.nativeEditor.edges.map(\.id), ["E0"])
        XCTAssertEqual(viewModel.graph?.junctions.count, 2)
        XCTAssertEqual(viewModel.graph?.edges.count, 1)
        XCTAssertEqual(viewModel.graph?.lanes.count, 1)
        XCTAssertEqual(viewModel.selectedEdgeID, "E0")
    }

    func testNativeNetworkSUMOExportsUsePublicNodeAndEdgeFormats() {
        var state = NativeNetworkEditorState(isEnabled: true)
        _ = state.addJunction(at: SIMD2<Float>(0, 0))
        _ = state.addJunction(at: SIMD2<Float>(10.5, -2))
        _ = state.addEdge(from: "J0", to: "J1")

        let nodeXML = NativeNetworkSUMOWriter.nodeXML(for: state)
        let edgeXML = NativeNetworkSUMOWriter.edgeXML(for: state)
        let plan = NativeNetworkExportPlan(outputNetURL: URL(fileURLWithPath: "/tmp/example.net.xml"))

        XCTAssertTrue(nodeXML.contains(#"<node id="J0" x="0.000" y="0.000" type="priority"/>"#))
        XCTAssertTrue(nodeXML.contains(#"<node id="J1" x="10.500" y="-2.000" type="priority"/>"#))
        XCTAssertTrue(edgeXML.contains(#"<edge id="E0" from="J0" to="J1" priority="1" numLanes="1" speed="13.890" width="3.200" spreadType="right"/>"#))
        XCTAssertEqual(plan.nodeURL.path, "/tmp/example.nod.xml")
        XCTAssertEqual(plan.edgeURL.path, "/tmp/example.edg.xml")
        XCTAssertEqual(plan.configURL.path, "/tmp/example.sumocfg")
    }

    func testNativeNetworkEditorEditsAndExportsJunctionShapes() async throws {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.selectNativeJunction("J0")
        XCTAssertTrue(viewModel.nativeJunctionShapeHandles.isEmpty)

        viewModel.customizeSelectedNativeJunctionShape()
        XCTAssertEqual(viewModel.selectedNativeJunction?.shapePoints.count, 4)
        XCTAssertEqual(viewModel.nativeJunctionShapeHandles.map(\.id), [
            "J0:shape:0",
            "J0:shape:1",
            "J0:shape:2",
            "J0:shape:3",
        ])

        viewModel.addShapePointToSelectedNativeJunction()
        XCTAssertEqual(viewModel.selectedNativeJunction?.shapePoints.count, 5)

        viewModel.moveNativeJunctionShapePoint(junctionID: "J0", pointIndex: 0, to: SIMD2<Float>(-12, -8))
        viewModel.finishNativeJunctionShapePointMoveGesture()
        XCTAssertEqual(viewModel.selectedNativeJunction?.shapePoints.first, SIMD2<Float>(-12, -8))

        let junction = try XCTUnwrap(viewModel.graph?.junctions.first { $0.id == "J0" })
        let graphShape = Array(try XCTUnwrap(viewModel.graph).junctionShape(junction))
        XCTAssertEqual(graphShape.first, SIMD2<Float>(-12, -8))

        let shapedNodeXML = NativeNetworkSUMOWriter.nodeXML(for: viewModel.nativeEditor)
        XCTAssertTrue(shapedNodeXML.contains(#"shape="-12.000,-8.000 0.000,-4.000 4.000,-4.000 4.000,4.000 -4.000,4.000""#))

        viewModel.moveNativeJunction(id: "J0", to: SIMD2<Float>(10, 5))
        viewModel.finishNativeJunctionMoveGesture()
        XCTAssertEqual(viewModel.selectedNativeJunction?.position, SIMD2<Float>(10, 5))
        XCTAssertEqual(viewModel.selectedNativeJunction?.shapePoints.first, SIMD2<Float>(-2, -3))

        viewModel.resetSelectedNativeJunctionShape()
        XCTAssertEqual(viewModel.selectedNativeJunction?.shapePoints, [])
        XCTAssertFalse(NativeNetworkSUMOWriter.nodeXML(for: viewModel.nativeEditor).contains("shape="))
    }

    func testNativeNetworkEditorMovesUpdatesAndDeletesDraftObjects() async {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(0, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.setNativeEditTool(.edge)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))

        viewModel.selectNativeJunction("J0")
        viewModel.moveNativeJunction(id: "J0", to: SIMD2<Float>(5, 7))
        viewModel.finishNativeJunctionMoveGesture()
        viewModel.setSelectedNativeJunctionType("traffic_light")
        viewModel.setSelectedNativeJunctionID("north_in")
        XCTAssertEqual(viewModel.selectedNativeJunction?.position, SIMD2<Float>(5, 7))
        XCTAssertEqual(viewModel.selectedNativeJunction?.type, "traffic_light")
        XCTAssertEqual(viewModel.selectedNativeJunction?.id, "north_in")
        XCTAssertEqual(viewModel.graph?.junctions.first(where: { $0.id == "north_in" })?.position, SIMD2<Float>(5, 7))

        viewModel.selectNativeEdge("E0")
        viewModel.setSelectedNativeEdgeID("north_to_south")
        viewModel.setSelectedNativeEdgePriority(4)
        viewModel.setSelectedNativeEdgeLaneCount(3)
        viewModel.setSelectedNativeEdgeSpeed(22.2)
        viewModel.setSelectedNativeEdgeLaneWidth(4.0)
        viewModel.setSelectedNativeEdgeSpreadType("center")
        viewModel.setSelectedNativeEdgeAllow("passenger bus")
        XCTAssertEqual(viewModel.selectedNativeEdge?.priority, 4)
        XCTAssertEqual(viewModel.selectedNativeEdge?.laneCount, 3)
        XCTAssertEqual(viewModel.selectedNativeEdge?.speed ?? 0, 22.2, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedNativeEdge?.laneWidth ?? 0, 4.0, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedNativeEdge?.spreadType, "center")
        XCTAssertEqual(viewModel.selectedNativeEdge?.allow, "passenger bus")
        XCTAssertEqual(viewModel.selectedNativeEdge?.id, "north_to_south")
        XCTAssertEqual(viewModel.selectedNativeEdge?.fromJunctionID, "north_in")
        XCTAssertEqual(viewModel.graph?.lanes.count, 3)
        XCTAssertEqual(viewModel.graph?.lanes.first?.width ?? 0, 4.0, accuracy: 0.001)

        let edgeXML = NativeNetworkSUMOWriter.edgeXML(for: viewModel.nativeEditor)
        XCTAssertTrue(edgeXML.contains(#"id="north_to_south" from="north_in" to="J1" priority="4" numLanes="3" speed="22.200" width="4.000" spreadType="center" allow="passenger bus""#))

        viewModel.deleteSelectedNativeObject()
        XCTAssertTrue(viewModel.nativeEditor.edges.isEmpty)

        viewModel.selectNativeJunction("north_in")
        viewModel.deleteSelectedNativeObject()
        XCTAssertEqual(viewModel.nativeEditor.junctions.map(\.id), ["J1"])
    }

    func testNativeNetworkEditorUndoRedoRestoresSnapshots() async {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(0, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(50, 0),
            junctionID: nil,
            edgeID: nil
        ))
        XCTAssertEqual(viewModel.nativeEditor.junctions.count, 2)
        XCTAssertTrue(viewModel.nativeEditorCanUndo)

        viewModel.undoNativeEditorChange()
        XCTAssertEqual(viewModel.nativeEditor.junctions.map(\.id), ["J0"])
        XCTAssertTrue(viewModel.nativeEditorCanRedo)

        viewModel.redoNativeEditorChange()
        XCTAssertEqual(viewModel.nativeEditor.junctions.map(\.id), ["J0", "J1"])
        XCTAssertFalse(viewModel.nativeEditorCanRedo)

        viewModel.selectNativeJunction("J0")
        viewModel.moveNativeJunction(id: "J0", to: SIMD2<Float>(7, 9))
        viewModel.moveNativeJunction(id: "J0", to: SIMD2<Float>(8, 10))
        viewModel.finishNativeJunctionMoveGesture()
        XCTAssertEqual(viewModel.selectedNativeJunction?.position, SIMD2<Float>(8, 10))

        viewModel.undoNativeEditorChange()
        XCTAssertEqual(viewModel.selectedNativeJunction?.position, SIMD2<Float>(0, 0))
    }

    func testNativeNetworkEditorGridSnapAppliesToCanvasAddsAndDragMoves() async {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        viewModel.setNativeGridSize(10)
        viewModel.setNativeSnapToGrid(true)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(6.2, 14.4),
            junctionID: nil,
            edgeID: nil
        ))

        XCTAssertEqual(viewModel.selectedNativeJunction?.position, SIMD2<Float>(10, 10))
        XCTAssertEqual(viewModel.nativeEditStatus, "1 junctions, 0 edges, snap 10.0m")

        viewModel.moveNativeJunction(id: "J0", to: SIMD2<Float>(24.2, 26.1))
        viewModel.finishNativeJunctionMoveGesture()

        XCTAssertEqual(viewModel.selectedNativeJunction?.position, SIMD2<Float>(20, 30))

        viewModel.undoNativeEditorChange()
        XCTAssertEqual(viewModel.selectedNativeJunction?.position, SIMD2<Float>(10, 10))

        viewModel.setNativeSnapToGrid(false)
        viewModel.moveNativeJunction(id: "J0", to: SIMD2<Float>(24.2, 26.1))
        viewModel.finishNativeJunctionMoveGesture()

        XCTAssertEqual(viewModel.selectedNativeJunction?.position.x ?? 0, 24.2, accuracy: 0.001)
        XCTAssertEqual(viewModel.selectedNativeJunction?.position.y ?? 0, 26.1, accuracy: 0.001)
    }

    func testNativeNetworkEditorAddsMovesAndExportsEdgeGeometryPoints() async throws {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(0, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.setNativeEditTool(.edge)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))

        viewModel.addGeometryPointToSelectedNativeEdge()
        XCTAssertEqual(viewModel.selectedNativeEdge?.geometryPoints, [SIMD2<Float>(50, 0)])
        XCTAssertEqual(viewModel.nativeEdgeGeometryHandles.map(\.id), ["E0:0"])

        viewModel.setNativeSnapToGrid(true)
        viewModel.setNativeGridSize(10)
        viewModel.moveNativeEdgeGeometryPoint(edgeID: "E0", pointIndex: 0, to: SIMD2<Float>(43, 18))
        viewModel.finishNativeEdgeGeometryPointMoveGesture()
        XCTAssertEqual(viewModel.selectedNativeEdge?.geometryPoints, [SIMD2<Float>(40, 20)])

        let lane = try XCTUnwrap(viewModel.graph?.lanes.first)
        let laneShape = Array(try XCTUnwrap(viewModel.graph).laneShape(lane))
        XCTAssertEqual(laneShape[1], SIMD2<Float>(40, 20))

        let edgeXML = NativeNetworkSUMOWriter.edgeXML(for: viewModel.nativeEditor)
        XCTAssertTrue(edgeXML.contains(#"shape="0.000,0.000 40.000,20.000 100.000,0.000""#))

        viewModel.undoNativeEditorChange()
        XCTAssertEqual(viewModel.selectedNativeEdge?.geometryPoints, [SIMD2<Float>(50, 0)])

        viewModel.removeLastGeometryPointFromSelectedNativeEdge()
        XCTAssertEqual(viewModel.selectedNativeEdge?.geometryPoints, [])
    }

    func testNativeNetworkEditorDuplicatesAndReversesEdges() async {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(0, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: nil,
            edgeID: nil
        ))
        viewModel.setNativeEditTool(.edge)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))
        viewModel.addGeometryPointToSelectedNativeEdge()
        viewModel.moveNativeEdgeGeometryPoint(edgeID: "E0", pointIndex: 0, to: SIMD2<Float>(40, 20))
        viewModel.finishNativeEdgeGeometryPointMoveGesture()

        viewModel.duplicateSelectedNativeEdge()
        XCTAssertEqual(viewModel.selectedNativeEdge?.id, "E1")
        XCTAssertEqual(viewModel.selectedNativeEdge?.fromJunctionID, "J0")
        XCTAssertEqual(viewModel.selectedNativeEdge?.toJunctionID, "J1")
        XCTAssertEqual(viewModel.selectedNativeEdge?.geometryPoints, [SIMD2<Float>(40, 20)])

        viewModel.reverseSelectedNativeEdge()
        XCTAssertEqual(viewModel.selectedNativeEdge?.id, "E2")
        XCTAssertEqual(viewModel.selectedNativeEdge?.fromJunctionID, "J1")
        XCTAssertEqual(viewModel.selectedNativeEdge?.toJunctionID, "J0")
        XCTAssertEqual(viewModel.selectedNativeEdge?.geometryPoints, [SIMD2<Float>(40, 20)])
        XCTAssertEqual(viewModel.nativeEditor.edges.map(\.id), ["E0", "E1", "E2"])
        XCTAssertEqual(viewModel.graph?.lanes.count, 3)

        let edgeXML = NativeNetworkSUMOWriter.edgeXML(for: viewModel.nativeEditor)
        XCTAssertTrue(edgeXML.contains(#"id="E1" from="J0" to="J1""#))
        XCTAssertTrue(edgeXML.contains(#"id="E2" from="J1" to="J0""#))
        XCTAssertTrue(edgeXML.contains(#"shape="100.000,0.000 40.000,20.000 0.000,0.000""#))

        viewModel.reverseSelectedNativeEdge()
        XCTAssertEqual(viewModel.nativeEditor.edges.map(\.id), ["E0", "E1", "E2"])

        viewModel.undoNativeEditorChange()
        XCTAssertEqual(viewModel.nativeEditor.edges.map(\.id), ["E0", "E1"])
    }

    func testNativeNetworkEditorEditsJunctionRadiusAndEdgeEndpoints() async throws {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        for position in [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(100, 0),
            SIMD2<Float>(40, 50),
        ] {
            viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
                worldPosition: position,
                junctionID: nil,
                edgeID: nil
            ))
        }
        viewModel.setNativeEditTool(.edge)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))

        viewModel.selectNativeJunction("J0")
        viewModel.setSelectedNativeJunctionRadius(12.5)
        XCTAssertEqual(viewModel.selectedNativeJunction?.radius ?? 0, 12.5, accuracy: 0.001)

        let junction = try XCTUnwrap(viewModel.graph?.junctions.first { $0.id == "J0" })
        let shape = Array(try XCTUnwrap(viewModel.graph).junctionShape(junction))
        XCTAssertEqual(shape[0], SIMD2<Float>(-12.5, -12.5))
        XCTAssertEqual(shape[2], SIMD2<Float>(12.5, 12.5))

        viewModel.selectNativeEdge("E0")
        viewModel.setSelectedNativeEdgeFromJunction("J2")
        XCTAssertEqual(viewModel.selectedNativeEdge?.fromJunctionID, "J2")
        XCTAssertEqual(viewModel.selectedNativeEdge?.toJunctionID, "J1")
        XCTAssertEqual(viewModel.graph?.edges.first?.fromJunction, "J2")

        viewModel.setSelectedNativeEdgeToJunction("J2")
        XCTAssertEqual(viewModel.selectedNativeEdge?.toJunctionID, "J1")
        XCTAssertEqual(viewModel.runtimeMessage, "Edge endpoints must be different.")

        viewModel.setSelectedNativeEdgeToJunction("J0")
        XCTAssertEqual(viewModel.selectedNativeEdge?.fromJunctionID, "J2")
        XCTAssertEqual(viewModel.selectedNativeEdge?.toJunctionID, "J0")

        let nodeXML = NativeNetworkSUMOWriter.nodeXML(for: viewModel.nativeEditor)
        let edgeXML = NativeNetworkSUMOWriter.edgeXML(for: viewModel.nativeEditor)
        XCTAssertTrue(nodeXML.contains(#"<node id="J0" x="0.000" y="0.000" type="priority" radius="12.500"/>"#))
        XCTAssertTrue(edgeXML.contains(#"<edge id="E0" from="J2" to="J0""#))

        viewModel.undoNativeEditorChange()
        XCTAssertEqual(viewModel.selectedNativeEdge?.fromJunctionID, "J2")
        XCTAssertEqual(viewModel.selectedNativeEdge?.toJunctionID, "J1")
    }

    func testNativeNetworkEditorShiftSelectsAndDeletesMultipleObjects() async {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        for position in [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(100, 0),
            SIMD2<Float>(200, 0),
        ] {
            viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
                worldPosition: position,
                junctionID: nil,
                edgeID: nil
            ))
        }
        viewModel.setNativeEditTool(.edge)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(200, 0),
            junctionID: "J2",
            edgeID: nil
        ))

        viewModel.setNativeEditTool(.select)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(200, 0),
            junctionID: "J2",
            edgeID: nil,
            extendsSelection: true
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: nil,
            edgeID: "E1",
            extendsSelection: true
        ))

        XCTAssertEqual(viewModel.nativeEditor.selectedJunctionIDs, ["J0", "J2"])
        XCTAssertEqual(viewModel.nativeEditor.selectedEdgeIDs, ["E1"])
        XCTAssertEqual(viewModel.nativeEditor.selectedObjectCount, 3)
        XCTAssertEqual(viewModel.selectedEdgeIDs, ["E1"])
        XCTAssertEqual(viewModel.selectedNativeEdge?.id, "E1")

        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(200, 0),
            junctionID: "J2",
            edgeID: nil,
            extendsSelection: true
        ))
        XCTAssertEqual(viewModel.nativeEditor.selectedJunctionIDs, ["J0"])
        XCTAssertEqual(viewModel.nativeEditor.selectedEdgeIDs, ["E1"])

        viewModel.deleteSelectedNativeObject()
        XCTAssertEqual(viewModel.nativeEditor.junctions.map(\.id), ["J1", "J2"])
        XCTAssertEqual(viewModel.nativeEditor.edges.map(\.id), [])
        XCTAssertEqual(viewModel.nativeEditor.selectedObjectCount, 0)
        XCTAssertEqual(viewModel.selectedEdgeIDs, [])
        XCTAssertEqual(viewModel.runtimeMessage, "Deleted 1 junction and 2 edges.")

        viewModel.undoNativeEditorChange()
        XCTAssertEqual(viewModel.nativeEditor.junctions.map(\.id), ["J0", "J1", "J2"])
        XCTAssertEqual(viewModel.nativeEditor.edges.map(\.id), ["E0", "E1"])
        XCTAssertEqual(viewModel.nativeEditor.selectedJunctionIDs, ["J0"])
        XCTAssertEqual(viewModel.nativeEditor.selectedEdgeIDs, ["E1"])
    }

    func testNativeNetworkEditorRubberBandSelectsObjectsInWorldBounds() async {
        let viewModel = SimulationViewModel()

        await viewModel.beginNativeNetworkEditing()
        for position in [
            SIMD2<Float>(0, 0),
            SIMD2<Float>(100, 0),
            SIMD2<Float>(200, 0),
        ] {
            viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
                worldPosition: position,
                junctionID: nil,
                edgeID: nil
            ))
        }
        viewModel.setNativeEditTool(.edge)
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: .zero,
            junctionID: "J0",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(100, 0),
            junctionID: "J1",
            edgeID: nil
        ))
        viewModel.handleNativeNetworkCanvasClick(NativeNetworkCanvasClick(
            worldPosition: SIMD2<Float>(200, 0),
            junctionID: "J2",
            edgeID: nil
        ))

        viewModel.selectNativeObjects(NativeNetworkRubberBandSelection(
            worldBounds: SIMD4<Float>(40, -10, 60, 10),
            extendsSelection: false
        ))
        XCTAssertEqual(viewModel.nativeEditor.selectedJunctionIDs, [])
        XCTAssertEqual(viewModel.nativeEditor.selectedEdgeIDs, ["E0"])
        XCTAssertEqual(viewModel.selectedEdgeIDs, ["E0"])
        XCTAssertEqual(viewModel.runtimeMessage, "Selected 0 junctions and 1 edge.")

        viewModel.selectNativeObjects(NativeNetworkRubberBandSelection(
            worldBounds: SIMD4<Float>(190, -10, 210, 10),
            extendsSelection: true
        ))
        XCTAssertEqual(viewModel.nativeEditor.selectedJunctionIDs, ["J2"])
        XCTAssertEqual(viewModel.nativeEditor.selectedEdgeIDs, ["E0", "E1"])
        XCTAssertEqual(viewModel.nativeEditor.selectedObjectCount, 3)

        viewModel.selectNativeObjects(NativeNetworkRubberBandSelection(
            worldBounds: SIMD4<Float>(300, -10, 320, 10),
            extendsSelection: false
        ))
        XCTAssertEqual(viewModel.nativeEditor.selectedObjectCount, 0)
        XCTAssertEqual(viewModel.selectedEdgeIDs, [])
    }

    func testScreenshotExportRequestLifecycleReportsSuccess() throws {
        let viewModel = SimulationViewModel()
        let url = URL(fileURLWithPath: "/tmp/sumogui-screenshot.png")

        viewModel.requestScreenshotExport(to: url)

        let request = viewModel.screenshotExportRequest
        XCTAssertEqual(request?.url, url)
        XCTAssertEqual(viewModel.runtimeMessage, "Exporting screenshot...")

        let id = try XCTUnwrap(request?.id)
        viewModel.completeScreenshotExport(id: id, result: .success(url))

        XCTAssertNil(viewModel.screenshotExportRequest)
        XCTAssertEqual(viewModel.runtimeMessage, "Exported screenshot to sumogui-screenshot.png")
    }

    func testScreenshotExportIgnoresStaleCompletion() {
        let viewModel = SimulationViewModel()
        let url = URL(fileURLWithPath: "/tmp/sumogui-screenshot.png")

        viewModel.requestScreenshotExport(to: url)
        viewModel.completeScreenshotExport(id: UUID(), result: .success(url))

        XCTAssertNotNil(viewModel.screenshotExportRequest)
        XCTAssertEqual(viewModel.runtimeMessage, "Exporting screenshot...")
    }

    func testFollowSelectedVehicleRequiresSelectionAndClearsWithEdgeSelection() {
        let viewModel = SimulationViewModel()

        viewModel.toggleFollowSelectedVehicle()
        XCTAssertFalse(viewModel.isFollowingSelectedVehicle)

        viewModel.selectVehicle("veh0")
        XCTAssertTrue(viewModel.canFollowSelectedVehicle)

        viewModel.toggleFollowSelectedVehicle()
        XCTAssertTrue(viewModel.isFollowingSelectedVehicle)

        viewModel.setSelectedEdge("edge0")
        XCTAssertNil(viewModel.selectedVehicleID)
        XCTAssertFalse(viewModel.isFollowingSelectedVehicle)
    }

    func testObjectActionsCopyFollowAndClearSelection() {
        let viewModel = SimulationViewModel()

        viewModel.setSelectedEdge("edge0")
        XCTAssertEqual(viewModel.selectedEdgeID, "edge0")

        viewModel.copyObjectID("edge0", label: "edge")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "edge0")
        XCTAssertEqual(viewModel.runtimeMessage, "Copied edge ID edge0")

        viewModel.followVehicle("veh0")
        XCTAssertEqual(viewModel.selectedVehicleID, "veh0")
        XCTAssertNil(viewModel.selectedEdgeID)
        XCTAssertTrue(viewModel.isFollowingSelectedVehicle)

        viewModel.clearSelection()
        XCTAssertNil(viewModel.selectedEdgeID)
        XCTAssertNil(viewModel.selectedVehicleID)
        XCTAssertFalse(viewModel.isFollowingSelectedVehicle)
    }

    func testSelectionSetsPersistAcrossFocusedObjectChanges() {
        let viewModel = SimulationViewModel()

        viewModel.setSelectedEdge("edge0")
        XCTAssertEqual(viewModel.selectedEdgeIDs, ["edge0"])

        viewModel.selectVehicle("veh0")
        XCTAssertNil(viewModel.selectedEdgeID)
        XCTAssertEqual(viewModel.selectedEdgeIDs, ["edge0"])
        XCTAssertEqual(viewModel.selectedVehicleID, "veh0")
        XCTAssertEqual(viewModel.selectedVehicleIDs, ["veh0"])

        viewModel.toggleEdgeSelection("edge1")
        XCTAssertEqual(viewModel.selectedEdgeIDs, ["edge0", "edge1"])

        viewModel.removeVehicleFromSelection("veh0")
        XCTAssertNil(viewModel.selectedVehicleID)
        XCTAssertTrue(viewModel.selectedVehicleIDs.isEmpty)
        XCTAssertEqual(viewModel.selectedEdgeIDs, ["edge0", "edge1"])

        viewModel.clearSelection()
        XCTAssertFalse(viewModel.hasSelection)
        XCTAssertTrue(viewModel.selectedEdgeIDs.isEmpty)
        XCTAssertTrue(viewModel.selectedVehicleIDs.isEmpty)
    }

    func testRouteSelectionHighlightsEdgesAndCanBeCleared() {
        let viewModel = SimulationViewModel()

        viewModel.selectRouteEdges(["edge0", "edge1", "edge1"], vehicleID: "veh0")

        XCTAssertEqual(viewModel.selectedRouteEdgeIDs, ["edge0", "edge1"])
        XCTAssertEqual(viewModel.selectedVehicleRouteEdgeIDs, ["edge0", "edge1"])
        XCTAssertEqual(viewModel.selectedEdgeIDs, ["edge0", "edge1"])
        XCTAssertEqual(viewModel.runtimeMessage, "Selected route for vehicle veh0 (2 edges)")

        viewModel.clearSelection()

        XCTAssertTrue(viewModel.selectedRouteEdgeIDs.isEmpty)
        XCTAssertTrue(viewModel.selectedVehicleRouteEdgeIDs.isEmpty)
    }

    func testBreakpointsAreSortedDeduplicatedAndClearable() {
        let viewModel = SimulationViewModel()

        XCTAssertTrue(viewModel.addBreakpoint(at: 10))
        XCTAssertTrue(viewModel.addBreakpoint(at: 3.5))
        XCTAssertFalse(viewModel.addBreakpoint(at: 10.0004))
        XCTAssertFalse(viewModel.addBreakpoint(at: -1))

        XCTAssertEqual(viewModel.breakpoints.map(\.time), [3.5, 10])

        let firstID = viewModel.breakpoints[0].id
        viewModel.removeBreakpoint(id: firstID)
        XCTAssertEqual(viewModel.breakpoints.map(\.time), [10])

        viewModel.clearBreakpoints()
        XCTAssertTrue(viewModel.breakpoints.isEmpty)
    }

    func testReachedBreakpointDetectsFirstForwardCrossing() {
        let viewModel = SimulationViewModel()
        viewModel.addBreakpoint(at: 5)
        viewModel.addBreakpoint(at: 8)

        XCTAssertNil(viewModel.reachedBreakpoint(from: 0, to: 4.99))
        XCTAssertEqual(viewModel.reachedBreakpoint(from: 4.99, to: 5.0)?.time, 5)
        XCTAssertEqual(viewModel.reachedBreakpoint(from: 5.0, to: 9.0)?.time, 8)
        XCTAssertNil(viewModel.reachedBreakpoint(from: 8.0, to: 9.0))
    }

    func testJumpToBreakpointRequiresRunnableSession() {
        let viewModel = SimulationViewModel()
        viewModel.addBreakpoint(at: 12)

        viewModel.jumpToBreakpoint(viewModel.breakpoints[0])

        XCTAssertEqual(viewModel.runtimeMessage, "Open a runnable SUMO configuration before jumping to a breakpoint.")
        XCTAssertFalse(viewModel.isPlaying)
    }

    func testTrackerSamplesReplaceDuplicateTimesAndKeepRecentWindow() {
        let viewModel = SimulationViewModel()

        viewModel.recordTrackerSample(simTime: 1, vehicleCount: 2, speedFactor: 0)
        viewModel.recordTrackerSample(simTime: 1.00001, vehicleCount: 3, speedFactor: 1.5)

        XCTAssertEqual(viewModel.trackerSamples.count, 1)
        XCTAssertEqual(viewModel.trackerSamples[0].vehicleCount, 3)
        XCTAssertEqual(viewModel.trackerSamples[0].speedFactor, 1.5)

        for index in 2...250 {
            viewModel.recordTrackerSample(simTime: Double(index), vehicleCount: index, speedFactor: Double(index) / 10)
        }

        XCTAssertEqual(viewModel.trackerSamples.count, 240)
        XCTAssertEqual(viewModel.trackerSamples.first?.simTime, 11)
        XCTAssertEqual(viewModel.trackerSamples.last?.simTime, 250)
    }

    func testTrackerValueSamplesReplaceDuplicatesAndFilterByVariable() {
        let viewModel = SimulationViewModel()

        viewModel.recordTrackerSample(simTime: 1, vehicleCount: 2, speedFactor: 1.25)
        XCTAssertEqual(viewModel.selectedTrackerSamples.map(\.value), [2])

        viewModel.trackerVariable = .playbackSpeed
        XCTAssertEqual(viewModel.selectedTrackerSamples.map(\.value), [1.25])

        viewModel.recordTrackerValueSample(
            simTime: 2,
            variable: .selectedVehicleSpeed,
            objectID: "veh0",
            value: 8
        )
        viewModel.recordTrackerValueSample(
            simTime: 2.00001,
            variable: .selectedVehicleSpeed,
            objectID: "veh0",
            value: 9
        )

        viewModel.trackerVariable = .selectedVehicleSpeed
        XCTAssertEqual(viewModel.selectedTrackerSamples.count, 1)
        XCTAssertEqual(viewModel.selectedTrackerSamples[0].seriesName, "Vehicle Speed veh0")
        XCTAssertEqual(viewModel.selectedTrackerSamples[0].value, 9)
    }

    func testSelectedVehicleTrackerSamplesUseSelectionSet() {
        let viewModel = SimulationViewModel()
        viewModel.selectVehicle("veh0")
        let state = SimulationState(
            simTime: 3,
            vehicles: [
                VehicleSnapshot(
                    id: "veh0",
                    position: SIMD2(10, 20),
                    angle: 90,
                    speed: 12,
                    typeID: 1,
                    acceleration: 1.5,
                    co2Emission: 42
                ),
            ]
        )

        viewModel.recordSelectedObjectTrackerSamples(simTime: 3, state: state)

        viewModel.trackerVariable = .selectedVehicleSpeed
        XCTAssertEqual(viewModel.selectedTrackerSamples.map(\.value), [12])

        viewModel.trackerVariable = .selectedVehicleAcceleration
        XCTAssertEqual(viewModel.selectedTrackerSamples.map(\.value), [1.5])

        viewModel.trackerVariable = .selectedVehicleCO2
        XCTAssertEqual(viewModel.selectedTrackerSamples.map(\.value), [42])
    }

    func testHoverVehicleTracksAndClearsPreviewStateWithoutSession() {
        let viewModel = SimulationViewModel()

        viewModel.hoverVehicle("veh0")
        XCTAssertEqual(viewModel.hoveredVehicleID, "veh0")
        XCTAssertTrue(viewModel.hoveredVehicleRouteEdgeIDs.isEmpty)
        XCTAssertTrue(viewModel.previewRouteEdgeIDs.isEmpty)

        viewModel.hoverVehicle(nil)
        XCTAssertNil(viewModel.hoveredVehicleID)
        XCTAssertTrue(viewModel.hoveredVehicleRouteEdgeIDs.isEmpty)
    }

    func testRecentDocumentsPersistAndMoveMostRecentToFront() async throws {
        let defaults = try makeIsolatedDefaults()
        let first = try makeTinyNetworkFile(name: "first")
        let second = try makeTinyNetworkFile(name: "second")

        let viewModel = SimulationViewModel(userDefaults: defaults)
        await viewModel.load(url: first)
        await viewModel.load(url: second)
        await viewModel.load(url: first)

        XCTAssertEqual(viewModel.recentDocuments.map(\.url), [first.standardizedFileURL, second.standardizedFileURL])

        let reloaded = SimulationViewModel(userDefaults: defaults)
        XCTAssertEqual(reloaded.recentDocuments.map(\.url), [first.standardizedFileURL, second.standardizedFileURL])
    }

    func testClearRecentDocumentsRemovesPersistedEntries() async throws {
        let defaults = try makeIsolatedDefaults()
        let net = try makeTinyNetworkFile(name: "clear")

        let viewModel = SimulationViewModel(userDefaults: defaults)
        await viewModel.load(url: net)
        XCTAssertFalse(viewModel.recentDocuments.isEmpty)

        viewModel.clearRecentDocuments()

        XCTAssertTrue(viewModel.recentDocuments.isEmpty)
        XCTAssertTrue(SimulationViewModel(userDefaults: defaults).recentDocuments.isEmpty)
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

    func testKilledSUMOSessionDisconnectsCleanly() async throws {
        guard SumoLauncher.locateBinary() != nil else {
            throw XCTSkip("SUMO not installed")
        }

        let config = try makeTinyScenario()
        let viewModel = SimulationViewModel()

        await viewModel.load(url: config)
        XCTAssertTrue(viewModel.canRunSimulation)

        await viewModel.stepOnceNow()
        XCTAssertGreaterThanOrEqual(viewModel.liveState.simTime, 0)

        await viewModel.terminateRunningSessionForTesting()
        await viewModel.stepOnceNow()

        XCTAssertFalse(viewModel.canRunSimulation)
        XCTAssertFalse(viewModel.isPlaying)
        XCTAssertTrue(viewModel.liveState.vehicles.isEmpty)
        XCTAssertTrue(viewModel.runtimeMessage?.contains("Simulation disconnected") == true)
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

    private func makeTinyNetworkFile(name: String) throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sumoguiapp-recent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let url = tmp.appendingPathComponent("\(name).net.xml")
        let net = """
        <?xml version="1.0" encoding="UTF-8"?>
        <net version="1.20">
            <location netOffset="0.00,0.00" convBoundary="0.00,0.00,100.00,0.00" origBoundary="0.00,0.00,100.00,0.00" projParameter="!"/>
            <edge id="e1" from="j0" to="j1" priority="1">
                <lane id="e1_0" index="0" speed="13.89" length="100.00" shape="0.00,0.00 100.00,0.00"/>
            </edge>
            <junction id="j0" type="dead_end" x="0.00" y="0.00" incLanes="" intLanes="" shape="0.00,0.00"/>
            <junction id="j1" type="dead_end" x="100.00" y="0.00" incLanes="e1_0" intLanes="" shape="100.00,0.00"/>
        </net>
        """
        try net.write(to: url, atomically: true, encoding: .utf8)
        return url.standardizedFileURL
    }

    private func makeIsolatedDefaults() throws -> UserDefaults {
        let suiteName = "SumoGUIMacTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
