import AppKit
import Foundation
import SumoKit
import UniformTypeIdentifiers

@MainActor
final class SimulationViewModel: ObservableObject {
    enum LoadState: Equatable {
        case empty
        case loading(String)
        case ready
        case failed(String)
    }

    struct SelectedEdgeDetails: Equatable {
        let id: String
        let function: String
        let fromJunction: String?
        let toJunction: String?
        let priority: Int16
        let laneCount: Int
        let connectionCount: Int
        let speed: Float?
        let length: Float?
        let bounds: SIMD4<Float>?
    }

    struct ScreenshotExportRequest: Equatable, Identifiable {
        let id: UUID
        let url: URL
    }

    struct RecentDocument: Equatable, Identifiable {
        let url: URL

        var id: String {
            url.standardizedFileURL.path
        }

        var title: String {
            url.lastPathComponent
        }

        var location: String {
            url.deletingLastPathComponent().path
        }
    }

    struct SimulationBreakpoint: Equatable, Identifiable {
        let id: UUID
        let time: Double

        init(id: UUID = UUID(), time: Double) {
            self.id = id
            self.time = time
        }
    }

    struct TrackerSample: Equatable, Identifiable {
        let simTime: Double
        let vehicleCount: Int
        let speedFactor: Double

        var id: Double { simTime }
    }

    enum TrackerVariable: String, CaseIterable, Identifiable {
        case vehicleCount
        case playbackSpeed
        case selectedVehicleSpeed
        case selectedVehicleAcceleration
        case selectedVehicleCO2
        case selectedEdgeOccupancy

        var id: Self { self }

        var title: String {
            switch self {
            case .vehicleCount:
                return "Vehicle Count"
            case .playbackSpeed:
                return "Playback Speed"
            case .selectedVehicleSpeed:
                return "Vehicle Speed"
            case .selectedVehicleAcceleration:
                return "Vehicle Acceleration"
            case .selectedVehicleCO2:
                return "Vehicle CO2"
            case .selectedEdgeOccupancy:
                return "Lane Occupancy"
            }
        }

        var axisTitle: String {
            switch self {
            case .vehicleCount:
                return "Vehicles"
            case .playbackSpeed:
                return "Speed factor"
            case .selectedVehicleSpeed:
                return "m/s"
            case .selectedVehicleAcceleration:
                return "m/s2"
            case .selectedVehicleCO2:
                return "mg/s"
            case .selectedEdgeOccupancy:
                return "%"
            }
        }
    }

    struct TrackerValueSample: Equatable, Identifiable {
        let simTime: Double
        let variable: TrackerVariable
        let objectID: String?
        let value: Double

        var id: String {
            "\(variable.rawValue):\(objectID ?? "global"):\(String(format: "%.4f", simTime))"
        }

        var seriesName: String {
            objectID.map { "\(variable.title) \($0)" } ?? variable.title
        }
    }

    struct FollowedVehiclePose: Equatable {
        let position: SIMD2<Float>
        let angle: Float
    }

    @Published private(set) var graph: NetGraph?
    @Published private(set) var sourceURL: URL?
    @Published private(set) var loadState: LoadState = .empty
    @Published private(set) var liveState = SimulationState()
    @Published private(set) var runtimeMessage: String?
    @Published private(set) var playbackSpeedFactor: Double = 0
    @Published private(set) var screenshotExportRequest: ScreenshotExportRequest?
    @Published private(set) var recentDocuments: [RecentDocument] = []
    @Published private(set) var breakpoints: [SimulationBreakpoint] = []
    @Published private(set) var trackerSamples: [TrackerSample] = []
    @Published private(set) var trackerValueSamples: [TrackerValueSample] = []
    @Published private(set) var selectedVehicleID: String?
    @Published private(set) var selectedEdgeIDs: Set<String> = []
    @Published private(set) var selectedVehicleIDs: Set<String> = []
    @Published private(set) var selectedRouteEdgeIDs: Set<String> = []
    @Published private(set) var hoveredVehicleID: String?
    @Published private(set) var hoveredVehicleRouteEdgeIDs: Set<String> = []
    @Published private(set) var laneOccupancyByID: [String: Float] = [:]
    @Published var selectedEdgeID: String?
    @Published var trackerVariable: TrackerVariable = .vehicleCount
    @Published var isPlaying = false
    @Published var isFollowingSelectedVehicle = false
    @Published var isRotatingWithSelectedVehicle = false
    @Published var stepDelay: Double = 0.1
    @Published var vehicleUpdateMode: VehicleUpdateMode = .subscriptions {
        didSet {
            guard vehicleUpdateMode != oldValue else { return }
            applyVehicleUpdateModeChange()
        }
    }
    @Published var laneColorMode: LaneColorMode = .speedLimit
    @Published var vehicleColorMode: VehicleColorMode = .speed
    @Published var junctionColorMode: JunctionColorMode = .type
    @Published var showLaneDirectionArrows = true
    @Published var showPolygons = true
    @Published var showPOIs = true
    @Published var showBackground = true
    @Published var showLegend = true
    @Published var backgroundImageURL: URL?
    @Published var backgroundWorldRect = SIMD4<Float>(0, 0, 1, 1)
    @Published var backgroundOpacity: Float = 0.65
    @Published var visualizationPalette = VisualizationPalette()
    @Published var isVisualizationSettingsPresented = false
    @Published private(set) var nativeEditor = NativeNetworkEditorState()
    @Published private(set) var nativeEditorUndoCount = 0
    @Published private(set) var nativeEditorRedoCount = 0
    @Published private(set) var nativeSnapToGrid = false
    @Published private(set) var nativeGridSize: Float = 10
    @Published var nativeEditTool: NativeNetworkEditTool = .select {
        didSet {
            guard nativeEditTool != oldValue else { return }
            if nativeEditTool != .edge {
                nativeEditor.pendingEdgeStartJunctionID = nil
            }
            if nativeEditor.isEnabled {
                runtimeMessage = nativeEditTool.helpText
            }
        }
    }

    private let initialOpenURL: URL?
    private let userDefaults: UserDefaults
    private var didAttemptInitialLoad = false
    private var session: RunningSUMOSession?
    private var playTask: Task<Void, Never>?
    private var viewportSubscriptionTask: Task<Void, Never>?
    private var vehicleUpdateModeTask: Task<Void, Never>?
    private var hoverRouteTask: Task<Void, Never>?
    private var externalToolProcesses: [Process] = []
    private var nativeEditorUndoStack: [NativeNetworkEditorState] = []
    private var nativeEditorRedoStack: [NativeNetworkEditorState] = []
    private var nativeMoveUndoJunctionID: String?
    private var nativeMoveUndoGeometryPoint: NativeEdgeGeometryHandle?
    private var nativeMoveUndoJunctionShapePoint: NativeJunctionShapeHandle?
    private var latestViewportBounds: SIMD4<Float>?
    private var spatialIndexes: SpatialIndexes?
    private var lastPlaybackWallTime: TimeInterval?
    private var lastPlaybackSimTime: Double?
    private var vehicleRouteCache: [String: Set<String>] = [:]
    private var vehicleRouteOrderCache: [String: [String]] = [:]
    private static let externalPlaybackDelayNanoseconds: UInt64 = 100_000_000

    private static let recentDocumentsKey = "SumoGUIMac.recentDocuments"
    private static let maxRecentDocumentCount = 8
    private static let maxTrackerSampleCount = 240
    private static let maxTrackerValueSampleCount = 2_000
    private static let maxNativeEditorHistoryCount = 120

    init(initialOpenURL: URL? = nil, userDefaults: UserDefaults = .standard) {
        self.initialOpenURL = initialOpenURL
        self.userDefaults = userDefaults
        recentDocuments = Self.loadRecentDocuments(from: userDefaults)
    }

    deinit {
        playTask?.cancel()
        viewportSubscriptionTask?.cancel()
        vehicleUpdateModeTask?.cancel()
        session?.terminateImmediately()
    }

    var title: String {
        sourceURL?.lastPathComponent ?? "No Network Open"
    }

    var subtitle: String {
        guard let graph else { return "Open a .sumocfg or .net.xml file" }
        if let runtimeMessage {
            return runtimeMessage
        }
        return "\(graph.edges.count) edges, \(graph.lanes.count) lanes, \(graph.junctions.count) junctions"
    }

    var normalEdges: Int {
        graph?.edges.filter { $0.function == .normal }.count ?? 0
    }

    var canRunSimulation: Bool {
        session != nil
    }

    var canFollowSelectedVehicle: Bool {
        selectedVehicleID != nil
    }

    var nativeNetworkEditingEnabled: Bool {
        nativeEditor.isEnabled
    }

    var nativeNetworkCanExport: Bool {
        nativeEditor.isEnabled && nativeEditor.junctions.isEmpty == false
    }

    var nativeEditorCanUndo: Bool {
        nativeEditor.isEnabled && nativeEditorUndoCount > 0
    }

    var nativeEditorCanRedo: Bool {
        nativeEditor.isEnabled && nativeEditorRedoCount > 0
    }

    var nativeSnapSummary: String {
        nativeSnapToGrid ? "Snap \(formattedNativeGridSize)m" : "Free placement"
    }

    var nativeEditStatus: String {
        let suffix = nativeSnapToGrid ? ", snap \(formattedNativeGridSize)m" : ""
        if let pending = nativeEditor.pendingEdgeStartJunctionID {
            return "\(nativeEditor.junctions.count) junctions, \(nativeEditor.edges.count) edges, edge from \(pending)\(suffix)"
        }
        return "\(nativeEditor.junctions.count) junctions, \(nativeEditor.edges.count) edges\(suffix)"
    }

    private var formattedNativeGridSize: String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), nativeGridSize)
    }

    var selectedNativeJunction: NativeNetworkJunction? {
        guard let id = nativeEditor.selectedJunctionID else { return nil }
        return nativeEditor.junction(id: id)
    }

    var selectedNativeEdge: NativeNetworkEdge? {
        guard let id = nativeEditor.selectedEdgeID else { return nil }
        return nativeEditor.edge(id: id)
    }

    var nativeEdgeGeometryHandles: [NativeEdgeGeometryHandle] {
        guard nativeEditor.isEnabled else { return [] }
        return nativeEditor.edgeGeometryHandles()
    }

    var nativeJunctionShapeHandles: [NativeJunctionShapeHandle] {
        guard nativeEditor.isEnabled else { return [] }
        let focusedIDs = nativeEditor.selectedJunctionIDs.isEmpty
            ? Set(nativeEditor.selectedJunctionID.map { [$0] } ?? [])
            : nativeEditor.selectedJunctionIDs
        return nativeEditor.junctionShapeHandles(for: focusedIDs)
    }

    var hasSelection: Bool {
        selectedEdgeID != nil ||
            selectedVehicleID != nil ||
            selectedEdgeIDs.isEmpty == false ||
            selectedVehicleIDs.isEmpty == false ||
            selectedRouteEdgeIDs.isEmpty == false
    }

    var followedVehiclePosition: SIMD2<Float>? {
        followedVehiclePose?.position
    }

    var followedVehiclePose: FollowedVehiclePose? {
        guard isFollowingSelectedVehicle, let selectedVehicleID else { return nil }
        if let vehicle = liveState.vehicles.first(where: { $0.id == selectedVehicleID }) {
            return FollowedVehiclePose(position: vehicle.position, angle: vehicle.angle)
        }
        guard let details = liveState.selectedVehicle, details.id == selectedVehicleID else {
            return nil
        }
        guard let position = details.position else { return nil }
        return FollowedVehiclePose(
            position: position,
            angle: details.angle ?? 0
        )
    }

    var selectedVehicleRouteEdgeIDs: Set<String> {
        var routeEdges = selectedRouteEdgeIDs
        if let selectedVehicleID, let cached = vehicleRouteCache[selectedVehicleID] {
            routeEdges.formUnion(cached)
        }
        guard
            let selectedVehicleID,
            liveState.selectedVehicle?.id == selectedVehicleID
        else {
            return routeEdges
        }
        routeEdges.formUnion(liveState.selectedVehicle?.routeEdgeIDs ?? [])
        return routeEdges
    }

    var previewRouteEdgeIDs: Set<String> {
        hoveredVehicleRouteEdgeIDs.subtracting(selectedVehicleRouteEdgeIDs)
    }

    var selectedTrackerSamples: [TrackerValueSample] {
        trackerValueSamples.filter { $0.variable == trackerVariable }
    }

    var activeBackgroundDecal: BackgroundDecal? {
        guard showBackground, let backgroundImageURL else { return nil }
        return BackgroundDecal(url: backgroundImageURL, worldRect: backgroundWorldRect, opacity: backgroundOpacity)
    }

    var junctionLoadByID: [String: Int] {
        guard junctionColorMode == .load, let graph, liveState.vehicles.isEmpty == false else { return [:] }
        var loads: [String: Int] = [:]
        for vehicle in liveState.vehicles {
            guard let nearest = nearestJunction(to: vehicle.position, in: graph), nearest.distanceSquared < 625 else {
                continue
            }
            loads[nearest.id, default: 0] += 1
        }
        return loads
    }

    var isExternalTraCIAttached: Bool {
        session?.isAttachedToExternalSUMO == true
    }

    var visibleWorldBoundsSummary: String {
        guard let latestViewportBounds else { return "Waiting for viewport" }
        return String(
            format: "%.0f, %.0f - %.0f, %.0f",
            latestViewportBounds.x,
            latestViewportBounds.y,
            latestViewportBounds.z,
            latestViewportBounds.w
        )
    }

    var viewportSubscriptionSummary: String {
        guard canRunSimulation else { return "No active SUMO session" }
        guard vehicleUpdateMode == .subscriptions else { return "Polling all active vehicles" }
        guard latestViewportBounds != nil else { return "Waiting for visible bounds" }
        return "Viewport vehicle context active"
    }

    var internalEdges: Int {
        graph?.edges.filter { $0.function == .internalEdge }.count ?? 0
    }

    var selectedEdge: Edge? {
        guard
            let graph,
            let selectedEdgeID,
            let index = graph.edgeIndex[selectedEdgeID]
        else {
            return nil
        }
        return graph.edges[Int(index)]
    }

    var selectedEdgeLanes: [Lane] {
        guard let edge = selectedEdge else { return [] }
        return lanes(for: edge)
    }

    func lanes(forEdgeID edgeID: String) -> [Lane] {
        guard
            let graph,
            let index = graph.edgeIndex[edgeID]
        else {
            return []
        }
        return lanes(for: graph.edges[Int(index)])
    }

    private func lanes(for edge: Edge) -> [Lane] {
        guard let graph else { return [] }
        return edge.laneRange.compactMap { laneIndex in
            let index = Int(laneIndex)
            guard graph.lanes.indices.contains(index) else { return nil }
            return graph.lanes[index]
        }
    }

    var selectedEdgeConnectionCount: Int {
        guard let selectedEdgeID else { return 0 }
        return graph?.connections.filter {
            $0.fromEdge == selectedEdgeID || $0.toEdge == selectedEdgeID
        }.count ?? 0
    }

    var selectedEdgeDetails: SelectedEdgeDetails? {
        guard let edge = selectedEdge else { return nil }
        let lanes = selectedEdgeLanes
        return SelectedEdgeDetails(
            id: edge.id,
            function: edgeFunctionText(edge.function),
            fromJunction: edge.fromJunction.isEmpty ? nil : edge.fromJunction,
            toJunction: edge.toJunction.isEmpty ? nil : edge.toJunction,
            priority: edge.priority,
            laneCount: lanes.count,
            connectionCount: selectedEdgeConnectionCount,
            speed: lanes.map(\.speed).filter(\.isFinite).max(),
            length: lanes.map(\.length).filter { $0.isFinite && $0 > 0 }.max(),
            bounds: boundsAreValid(edge.bounds) ? edge.bounds : nil
        )
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sumocfg"),
            UTType(filenameExtension: "xml"),
        ].compactMap { $0 }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.load(url: url)
            }
        }
    }

    func openRecentDocument(_ document: RecentDocument) {
        Task { @MainActor in
            await load(url: document.url)
        }
    }

    func clearRecentDocuments() {
        recentDocuments = []
        persistRecentDocuments()
    }

    func presentAttachPanel() {
        let panel = NSOpenPanel()
        panel.message = "Choose the .sumocfg or .net.xml that matches the external SUMO run."
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sumocfg"),
            UTType(filenameExtension: "xml"),
        ].compactMap { $0 }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.presentAttachSettings(for: url)
            }
        }
    }

    func presentNetEditOpenPanel() {
        let panel = NSOpenPanel()
        panel.message = "Choose the .sumocfg or .net.xml to edit in SUMO NetEdit."
        panel.prompt = "Edit"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "sumocfg"),
            UTType(filenameExtension: "xml"),
        ].compactMap { $0 }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.openInNetEdit(url)
            }
        }
    }

    func openCurrentDocumentInNetEdit() {
        guard let sourceURL else {
            presentNetEditOpenPanel()
            return
        }
        openInNetEdit(sourceURL)
    }

    func createNewNetworkInNetEdit() {
        launchNetEdit(arguments: ["--new-network"], workingDirectory: nil, successMessage: "Opened a new network in SUMO NetEdit.")
    }

    func beginNativeNetworkEditing() async {
        await shutdownSession()
        resetEditingDocumentState()
        nativeEditor = NativeNetworkEditorState(isEnabled: true)
        resetNativeEditorHistory()
        nativeEditTool = .junction
        rebuildNativeNetworkGraph()
        sourceURL = nil
        loadState = .ready
        runtimeMessage = nativeEditTool.helpText
    }

    func beginNativeNetworkEditingFromCurrentOrNew() async {
        guard let graph else {
            await beginNativeNetworkEditing()
            return
        }
        await shutdownSession()
        resetEditingDocumentState()
        nativeEditor = NativeNetworkEditorState(importing: graph)
        resetNativeEditorHistory()
        nativeEditTool = nativeEditor.junctions.isEmpty ? .junction : .select
        rebuildNativeNetworkGraph()
        loadState = .ready
        runtimeMessage = "Converted visible network to a simplified native editing draft."
    }

    func finishNativeNetworkEditing() {
        guard nativeEditor.isEnabled else { return }
        nativeEditor.isEnabled = false
        nativeEditor.pendingEdgeStartJunctionID = nil
        runtimeMessage = "Native editing paused."
    }

    func setNativeEditTool(_ tool: NativeNetworkEditTool) {
        nativeEditTool = tool
    }

    func handleNativeNetworkCanvasClick(_ click: NativeNetworkCanvasClick) {
        guard nativeEditor.isEnabled else { return }
        switch nativeEditTool {
        case .select:
            if let junctionID = click.junctionID {
                selectNativeJunction(junctionID, extending: click.extendsSelection)
            } else if let edgeID = click.edgeID {
                selectNativeEdge(edgeID, extending: click.extendsSelection)
            } else {
                guard click.extendsSelection == false else {
                    runtimeMessage = "Selection unchanged."
                    return
                }
                clearNativeEditorSelection()
                runtimeMessage = "Selection cleared."
            }
        case .junction:
            var addedID: String?
            if commitNativeEditorMutation({
                let junction = $0.addJunction(at: snappedNativePosition(click.worldPosition))
                addedID = junction.id
                return true
            }) {
                runtimeMessage = "Added junction \(addedID ?? "junction")."
            }
        case .edge:
            let junctionID = click.junctionID ?? nativeEditor.previewNextJunctionID
            if let startID = nativeEditor.pendingEdgeStartJunctionID {
                guard startID != junctionID else {
                    nativeEditor.selectedJunctionID = junctionID
                    runtimeMessage = "Choose another junction to finish the edge."
                    return
                }
                guard nativeEditor.hasEdge(from: startID, to: junctionID) == false else {
                    runtimeMessage = "That edge already exists in the native draft."
                    return
                }
                var addedEdgeID: String?
                let committed = commitNativeEditorMutation({
                    let destinationID: String
                    if let existingID = click.junctionID {
                        destinationID = existingID
                    } else {
                        destinationID = $0.addJunction(at: snappedNativePosition(click.worldPosition)).id
                    }
                    guard let edge = $0.addEdge(from: startID, to: destinationID) else {
                        return false
                    }
                    $0.pendingEdgeStartJunctionID = nil
                    addedEdgeID = edge.id
                    return true
                })
                if committed {
                    runtimeMessage = "Added edge \(addedEdgeID ?? "edge")."
                }
            } else {
                if click.junctionID == nil {
                    var addedJunctionID: String?
                    if commitNativeEditorMutation({
                        let junction = $0.addJunction(at: snappedNativePosition(click.worldPosition))
                        $0.pendingEdgeStartJunctionID = junction.id
                        addedJunctionID = junction.id
                        return true
                    }) {
                        runtimeMessage = "Started edge from \(addedJunctionID ?? "junction")."
                    }
                } else if let junctionID = click.junctionID {
                    nativeEditor.selectJunction(junctionID)
                    nativeEditor.pendingEdgeStartJunctionID = junctionID
                    selectedEdgeID = nil
                    syncNativeSelectionToViewerSelection()
                    rebuildNativeNetworkGraph()
                    runtimeMessage = "Started edge from \(junctionID)."
                }
            }
        }
    }

    func selectNativeJunction(_ id: String, extending: Bool = false) {
        guard nativeEditor.isEnabled, nativeEditor.junction(id: id) != nil else { return }
        nativeEditor.selectJunction(id, extending: extending)
        syncNativeSelectionToViewerSelection()
        runtimeMessage = nativeSelectionMessage(focusedLabel: "junction \(id)")
    }

    func selectNativeEdge(_ id: String, extending: Bool = false) {
        guard nativeEditor.isEnabled, nativeEditor.edge(id: id) != nil else { return }
        nativeEditor.selectEdge(id, extending: extending)
        syncNativeSelectionToViewerSelection()
        runtimeMessage = nativeSelectionMessage(focusedLabel: "edge \(id)")
    }

    func selectNativeObjects(_ selection: NativeNetworkRubberBandSelection) {
        guard nativeEditor.isEnabled else { return }
        let summary = nativeEditor.selectObjects(in: selection.worldBounds, extending: selection.extendsSelection)
        syncNativeSelectionToViewerSelection()
        runtimeMessage = "Selected \(summary.junctionCount) junction\(summary.junctionCount == 1 ? "" : "s") and \(summary.edgeCount) edge\(summary.edgeCount == 1 ? "" : "s")."
    }

    func moveNativeJunction(id: String, to position: SIMD2<Float>) {
        guard nativeEditor.isEnabled else { return }
        guard let junction = nativeEditor.junction(id: id) else { return }
        let targetPosition = snappedNativePosition(position)
        guard junction.position != targetPosition else { return }
        if nativeMoveUndoJunctionID != id {
            recordNativeEditorUndoSnapshot(nativeEditor)
            nativeMoveUndoJunctionID = id
        }
        guard nativeEditor.moveJunction(id, to: targetPosition) else { return }
        nativeEditor.focusJunction(id, preservingSelection: true)
        syncNativeSelectionToViewerSelection()
        rebuildNativeNetworkGraph()
        runtimeMessage = "Moved junction \(id)."
    }

    func finishNativeJunctionMoveGesture() {
        nativeMoveUndoJunctionID = nil
    }

    func moveNativeEdgeGeometryPoint(edgeID: String, pointIndex: Int, to position: SIMD2<Float>) {
        guard nativeEditor.isEnabled else { return }
        guard nativeEditor.edge(id: edgeID)?.geometryPoints.indices.contains(pointIndex) == true else { return }
        let targetPosition = snappedNativePosition(position)
        let handle = NativeEdgeGeometryHandle(edgeID: edgeID, pointIndex: pointIndex, position: targetPosition)
        if nativeMoveUndoGeometryPoint?.edgeID != edgeID || nativeMoveUndoGeometryPoint?.pointIndex != pointIndex {
            recordNativeEditorUndoSnapshot(nativeEditor)
            nativeMoveUndoGeometryPoint = handle
        }
        guard nativeEditor.moveEdgeGeometryPoint(edgeID: edgeID, pointIndex: pointIndex, to: targetPosition) else { return }
        nativeEditor.focusEdge(edgeID, preservingSelection: true)
        syncNativeSelectionToViewerSelection()
        rebuildNativeNetworkGraph()
        runtimeMessage = "Moved edge \(edgeID) geometry point."
    }

    func finishNativeEdgeGeometryPointMoveGesture() {
        nativeMoveUndoGeometryPoint = nil
    }

    func moveNativeJunctionShapePoint(junctionID: String, pointIndex: Int, to position: SIMD2<Float>) {
        guard nativeEditor.isEnabled else { return }
        guard nativeEditor.junction(id: junctionID)?.shapePoints.indices.contains(pointIndex) == true else { return }
        let targetPosition = snappedNativePosition(position)
        let handle = NativeJunctionShapeHandle(junctionID: junctionID, pointIndex: pointIndex, position: targetPosition)
        if nativeMoveUndoJunctionShapePoint?.junctionID != junctionID ||
            nativeMoveUndoJunctionShapePoint?.pointIndex != pointIndex
        {
            recordNativeEditorUndoSnapshot(nativeEditor)
            nativeMoveUndoJunctionShapePoint = handle
        }
        guard nativeEditor.moveJunctionShapePoint(junctionID: junctionID, pointIndex: pointIndex, to: targetPosition) else { return }
        nativeEditor.focusJunction(junctionID, preservingSelection: true)
        syncNativeSelectionToViewerSelection()
        rebuildNativeNetworkGraph()
        runtimeMessage = "Moved junction \(junctionID) shape point."
    }

    func finishNativeJunctionShapePointMoveGesture() {
        nativeMoveUndoJunctionShapePoint = nil
    }

    func setSelectedNativeJunctionType(_ type: String) {
        guard let id = nativeEditor.selectedJunctionID else { return }
        let cleanType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanType.isEmpty == false else { return }
        guard commitNativeEditorMutation({ $0.updateJunction(id, type: cleanType) }) else { return }
        runtimeMessage = "Updated junction \(id)."
    }

    func setSelectedNativeJunctionID(_ newID: String) {
        guard let id = nativeEditor.selectedJunctionID else { return }
        switch validatedNativeObjectID(newID, currentID: id) {
        case .success(let cleanID):
            guard cleanID != id else { return }
            guard commitNativeEditorMutation({ $0.renameJunction(id, to: cleanID) }) else {
                runtimeMessage = "Junction ID \(cleanID) is already in use."
                return
            }
            runtimeMessage = "Renamed junction \(id) to \(cleanID)."
        case .failure(let message):
            runtimeMessage = message
        }
    }

    func setSelectedNativeJunctionPosition(axis: Int, value: Float) {
        guard let junction = selectedNativeJunction, value.isFinite else { return }
        var position = junction.position
        if axis == 0 {
            position.x = value
        } else {
            position.y = value
        }
        guard commitNativeEditorMutation({ state in
            state.moveJunction(junction.id, to: position)
        }) else { return }
        runtimeMessage = "Moved junction \(junction.id)."
    }

    func setSelectedNativeJunctionRadius(_ radius: Float) {
        guard let id = nativeEditor.selectedJunctionID, radius.isFinite, radius > 0 else { return }
        guard commitNativeEditorMutation({ $0.updateJunction(id, radius: max(0.5, min(radius, 1_000))) }) else { return }
        runtimeMessage = "Updated junction \(id)."
    }

    func customizeSelectedNativeJunctionShape() {
        guard let id = nativeEditor.selectedJunctionID else {
            runtimeMessage = "Select a native junction first."
            return
        }
        guard commitNativeEditorMutation({ $0.customizeJunctionShape(id) }) else {
            runtimeMessage = "Junction \(id) already has a custom shape."
            return
        }
        runtimeMessage = "Enabled custom shape editing for junction \(id)."
    }

    func addShapePointToSelectedNativeJunction() {
        guard let id = nativeEditor.selectedJunctionID else {
            runtimeMessage = "Select a native junction first."
            return
        }
        var pointIndex: Int?
        guard commitNativeEditorMutation({ state in
            pointIndex = state.addShapePoint(toJunction: id)
            return pointIndex != nil
        }) else {
            runtimeMessage = "Could not add a shape point to junction \(id)."
            return
        }
        runtimeMessage = "Added shape point \(pointIndex.map { $0 + 1 } ?? 1) to junction \(id)."
    }

    func removeLastShapePointFromSelectedNativeJunction() {
        guard let id = nativeEditor.selectedJunctionID else {
            runtimeMessage = "Select a native junction first."
            return
        }
        guard commitNativeEditorMutation({ $0.removeLastShapePoint(fromJunction: id) }) else {
            runtimeMessage = "Junction \(id) needs at least three shape points."
            return
        }
        runtimeMessage = "Removed the last shape point from junction \(id)."
    }

    func resetSelectedNativeJunctionShape() {
        guard let id = nativeEditor.selectedJunctionID else {
            runtimeMessage = "Select a native junction first."
            return
        }
        guard commitNativeEditorMutation({ $0.resetJunctionShape(id) }) else {
            runtimeMessage = "Junction \(id) is already using radius shape."
            return
        }
        runtimeMessage = "Reset junction \(id) to radius shape."
    }

    func setSelectedNativeEdgePriority(_ priority: Int16) {
        guard let id = nativeEditor.selectedEdgeID else { return }
        guard commitNativeEditorMutation({ $0.updateEdge(id, priority: priority) }) else { return }
        runtimeMessage = "Updated edge \(id)."
    }

    func setSelectedNativeEdgeLaneCount(_ laneCount: Int) {
        guard let id = nativeEditor.selectedEdgeID else { return }
        guard commitNativeEditorMutation({ $0.updateEdge(id, laneCount: max(1, min(laneCount, 12))) }) else { return }
        runtimeMessage = "Updated edge \(id)."
    }

    func setSelectedNativeEdgeSpeed(_ speed: Float) {
        guard let id = nativeEditor.selectedEdgeID, speed.isFinite, speed > 0 else { return }
        guard commitNativeEditorMutation({ $0.updateEdge(id, speed: speed) }) else { return }
        runtimeMessage = "Updated edge \(id)."
    }

    func setSelectedNativeEdgeID(_ newID: String) {
        guard let id = nativeEditor.selectedEdgeID else { return }
        switch validatedNativeObjectID(newID, currentID: id) {
        case .success(let cleanID):
            guard cleanID != id else { return }
            guard commitNativeEditorMutation({ $0.renameEdge(id, to: cleanID) }) else {
                runtimeMessage = "Edge ID \(cleanID) is already in use."
                return
            }
            runtimeMessage = "Renamed edge \(id) to \(cleanID)."
        case .failure(let message):
            runtimeMessage = message
        }
    }

    func setSelectedNativeEdgeLaneWidth(_ width: Float) {
        guard let id = nativeEditor.selectedEdgeID, width.isFinite, width > 0 else { return }
        guard commitNativeEditorMutation({ $0.updateEdge(id, laneWidth: max(0.5, min(width, 12))) }) else { return }
        runtimeMessage = "Updated edge \(id)."
    }

    func setSelectedNativeEdgeFromJunction(_ junctionID: String) {
        guard let edge = selectedNativeEdge else { return }
        let cleanID = junctionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanID != edge.toJunctionID else {
            runtimeMessage = "Edge endpoints must be different."
            return
        }
        guard commitNativeEditorMutation({ $0.updateEdge(edge.id, fromJunctionID: cleanID) }) else {
            runtimeMessage = "Junction \(cleanID) is not in the native draft."
            return
        }
        runtimeMessage = "Updated edge \(edge.id) start junction."
    }

    func setSelectedNativeEdgeToJunction(_ junctionID: String) {
        guard let edge = selectedNativeEdge else { return }
        let cleanID = junctionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanID != edge.fromJunctionID else {
            runtimeMessage = "Edge endpoints must be different."
            return
        }
        guard commitNativeEditorMutation({ $0.updateEdge(edge.id, toJunctionID: cleanID) }) else {
            runtimeMessage = "Junction \(cleanID) is not in the native draft."
            return
        }
        runtimeMessage = "Updated edge \(edge.id) end junction."
    }

    func setSelectedNativeEdgeSpreadType(_ spreadType: String) {
        guard let id = nativeEditor.selectedEdgeID else { return }
        let cleanSpreadType = spreadType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanSpreadType.isEmpty == false else { return }
        guard commitNativeEditorMutation({ $0.updateEdge(id, spreadType: cleanSpreadType) }) else { return }
        runtimeMessage = "Updated edge \(id)."
    }

    func setSelectedNativeEdgeAllow(_ allow: String) {
        guard let id = nativeEditor.selectedEdgeID else { return }
        guard commitNativeEditorMutation({ $0.updateEdge(id, allow: allow.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { return }
        runtimeMessage = "Updated edge \(id)."
    }

    func setSelectedNativeEdgeDisallow(_ disallow: String) {
        guard let id = nativeEditor.selectedEdgeID else { return }
        guard commitNativeEditorMutation({ $0.updateEdge(id, disallow: disallow.trimmingCharacters(in: .whitespacesAndNewlines)) }) else { return }
        runtimeMessage = "Updated edge \(id)."
    }

    func addGeometryPointToSelectedNativeEdge() {
        guard let id = nativeEditor.selectedEdgeID else {
            runtimeMessage = "Select a native edge first."
            return
        }
        var pointIndex: Int?
        guard commitNativeEditorMutation({ state in
            pointIndex = state.addGeometryPoint(toEdge: id)
            return pointIndex != nil
        }) else {
            runtimeMessage = "Could not add a geometry point to edge \(id)."
            return
        }
        runtimeMessage = "Added geometry point \(pointIndex.map { $0 + 1 } ?? 1) to edge \(id)."
    }

    func removeLastGeometryPointFromSelectedNativeEdge() {
        guard let id = nativeEditor.selectedEdgeID else {
            runtimeMessage = "Select a native edge first."
            return
        }
        guard commitNativeEditorMutation({ $0.removeLastGeometryPoint(fromEdge: id) }) else {
            runtimeMessage = "Edge \(id) has no geometry points to remove."
            return
        }
        runtimeMessage = "Removed the last geometry point from edge \(id)."
    }

    func duplicateSelectedNativeEdge() {
        guard let id = nativeEditor.selectedEdgeID else {
            runtimeMessage = "Select a native edge first."
            return
        }
        var duplicateID: String?
        guard commitNativeEditorMutation({ state in
            guard let edge = state.duplicateEdge(id) else { return false }
            duplicateID = edge.id
            return true
        }) else {
            runtimeMessage = "Could not duplicate edge \(id)."
            return
        }
        runtimeMessage = "Duplicated edge \(id) as \(duplicateID ?? "new edge")."
    }

    func reverseSelectedNativeEdge() {
        guard let id = nativeEditor.selectedEdgeID else {
            runtimeMessage = "Select a native edge first."
            return
        }
        var reverseID: String?
        guard commitNativeEditorMutation({ state in
            guard let edge = state.reverseEdge(id) else { return false }
            reverseID = edge.id
            return true
        }) else {
            runtimeMessage = "Could not create a reverse edge for \(id)."
            return
        }
        runtimeMessage = "Created reverse edge \(reverseID ?? "edge") from \(id)."
    }

    func deleteSelectedNativeObject() {
        guard nativeEditor.isEnabled else { return }
        var removed: NativeNetworkSelectionRemoval?
        guard commitNativeEditorMutation({ state in
            removed = state.removeSelectedObjects()
            return removed != nil
        }) else {
            runtimeMessage = "Select a native junction or edge first."
            return
        }
        let junctionCount = removed?.junctionCount ?? 0
        let edgeCount = removed?.edgeCount ?? 0
        runtimeMessage = "Deleted \(junctionCount) junction\(junctionCount == 1 ? "" : "s") and \(edgeCount) edge\(edgeCount == 1 ? "" : "s")."
    }

    func clearNativePendingEdge() {
        nativeEditor.pendingEdgeStartJunctionID = nil
        runtimeMessage = "Cancelled native edge creation."
    }

    func setNativeSnapToGrid(_ enabled: Bool) {
        nativeSnapToGrid = enabled
        nativeMoveUndoJunctionID = nil
        nativeMoveUndoGeometryPoint = nil
        nativeMoveUndoJunctionShapePoint = nil
        runtimeMessage = enabled ? "Grid snapping enabled at \(formattedNativeGridSize)m." : "Grid snapping disabled."
    }

    func setNativeGridSize(_ size: Float) {
        guard size.isFinite, size > 0 else { return }
        nativeGridSize = max(0.25, min(size, 1_000))
        runtimeMessage = "Native editor grid set to \(formattedNativeGridSize)m."
    }

    func undoNativeEditorChange() {
        guard nativeEditorCanUndo, let previous = nativeEditorUndoStack.popLast() else { return }
        nativeEditorRedoStack.append(nativeEditor)
        nativeEditor = previous
        nativeMoveUndoJunctionID = nil
        nativeMoveUndoGeometryPoint = nil
        nativeMoveUndoJunctionShapePoint = nil
        syncNativeSelectionToViewerSelection()
        updateNativeEditorHistoryCounts()
        rebuildNativeNetworkGraph()
        runtimeMessage = "Undid native editor change."
    }

    func redoNativeEditorChange() {
        guard nativeEditorCanRedo, let next = nativeEditorRedoStack.popLast() else { return }
        nativeEditorUndoStack.append(nativeEditor)
        nativeEditor = next
        nativeMoveUndoJunctionID = nil
        nativeMoveUndoGeometryPoint = nil
        nativeMoveUndoJunctionShapePoint = nil
        syncNativeSelectionToViewerSelection()
        updateNativeEditorHistoryCounts()
        rebuildNativeNetworkGraph()
        runtimeMessage = "Redid native editor change."
    }

    func presentNativeNetworkExportPanel() {
        guard nativeNetworkCanExport else {
            runtimeMessage = "Add at least one junction before exporting."
            return
        }
        let panel = NSSavePanel()
        panel.title = "Export Native Network"
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType.xml]
        panel.nameFieldStringValue = "native-network.net.xml"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.exportNativeNetwork(to: url)
            }
        }
    }

    func exportNativeNetwork(to outputNetURL: URL) {
        guard nativeNetworkCanExport else {
            runtimeMessage = "Add at least one junction before exporting."
            return
        }
        let plan = NativeNetworkExportPlan(outputNetURL: outputNetURL)
        do {
            try NativeNetworkSUMOWriter.writeSourceFiles(for: nativeEditor, plan: plan)
            if let netconvert = SumoLauncher.locateTool(named: "netconvert") {
                try runNetconvert(netconvert, plan: plan)
                sourceURL = plan.netURL
                rememberRecentDocument(plan.netURL)
                runtimeMessage = "Exported native network to \(plan.netURL.lastPathComponent)."
            } else {
                runtimeMessage = "Wrote \(plan.nodeURL.lastPathComponent) and \(plan.edgeURL.lastPathComponent). Install netconvert to compile the .net.xml."
            }
        } catch {
            runtimeMessage = "Native network export failed: \(error.localizedDescription)"
        }
    }

    func presentScreenshotPanel() {
        guard graph != nil else {
            runtimeMessage = "Open a network before exporting a screenshot."
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Screenshot"
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType.png]
        panel.nameFieldStringValue = defaultScreenshotFilename()
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.requestScreenshotExport(to: url)
            }
        }
    }

    func presentVisualizationSettings() {
        isVisualizationSettingsPresented = true
    }

    func presentBackgroundImagePanel() {
        let panel = NSOpenPanel()
        panel.title = "Choose Background Decal"
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType.png,
            UTType.jpeg,
            UTType.tiff,
            UTType(filenameExtension: "tif"),
            UTType(filenameExtension: "geotiff"),
        ].compactMap { $0 }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.setBackgroundImage(url)
            }
        }
    }

    func setBackgroundImage(_ url: URL) {
        backgroundImageURL = url.standardizedFileURL
        backgroundWorldRect = inferredBackgroundWorldRect(for: url)
        showBackground = true
        runtimeMessage = "Loaded background decal \(url.lastPathComponent)"
    }

    func clearBackgroundImage() {
        backgroundImageURL = nil
        runtimeMessage = "Cleared background decal"
    }

    func setBackgroundWorldRectComponent(_ index: Int, value: Float) {
        guard value.isFinite else { return }
        switch index {
        case 0:
            backgroundWorldRect.x = value
        case 1:
            backgroundWorldRect.y = value
        case 2:
            backgroundWorldRect.z = value
        case 3:
            backgroundWorldRect.w = value
        default:
            break
        }
    }

    func presentImportVisualizationSettingsPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Visualization Settings"
        panel.prompt = "Import"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.xml]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.importVisualizationSettings(from: url)
            }
        }
    }

    func presentExportVisualizationSettingsPanel() {
        let panel = NSSavePanel()
        panel.title = "Export Visualization Settings"
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType.xml]
        panel.nameFieldStringValue = "sumogui-viewsettings.xml"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.exportVisualizationSettings(to: url)
            }
        }
    }

    func importVisualizationSettings(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            var snapshot = try VisualizationSettingsSnapshot.parse(data: data)
            if let path = snapshot.backgroundPath, URL(fileURLWithPath: path).isFileURL {
                let backgroundURL = URL(fileURLWithPath: path, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
                snapshot.backgroundPath = backgroundURL.path
            }
            applyVisualizationSettings(snapshot)
            runtimeMessage = "Imported visualization settings from \(url.lastPathComponent)"
        } catch {
            runtimeMessage = "Visualization settings import failed: \(error.localizedDescription)"
        }
    }

    func exportVisualizationSettings(to url: URL) {
        do {
            try currentVisualizationSettings().xmlData().write(to: url, options: .atomic)
            runtimeMessage = "Exported visualization settings to \(url.lastPathComponent)"
        } catch {
            runtimeMessage = "Visualization settings export failed: \(error.localizedDescription)"
        }
    }

    func currentVisualizationSettings() -> VisualizationSettingsSnapshot {
        VisualizationSettingsSnapshot(
            laneColorMode: laneColorMode,
            vehicleColorMode: vehicleColorMode,
            junctionColorMode: junctionColorMode,
            showLaneDirectionArrows: showLaneDirectionArrows,
            showPolygons: showPolygons,
            showPOIs: showPOIs,
            showBackground: showBackground,
            showLegend: showLegend,
            backgroundPath: backgroundImageURL?.path,
            backgroundWorldRect: backgroundWorldRect,
            backgroundOpacity: backgroundOpacity,
            palette: visualizationPalette
        )
    }

    func applyVisualizationSettings(_ snapshot: VisualizationSettingsSnapshot) {
        laneColorMode = snapshot.laneColorMode
        vehicleColorMode = snapshot.vehicleColorMode
        junctionColorMode = snapshot.junctionColorMode
        showLaneDirectionArrows = snapshot.showLaneDirectionArrows
        showPolygons = snapshot.showPolygons
        showPOIs = snapshot.showPOIs
        showBackground = snapshot.showBackground
        showLegend = snapshot.showLegend
        backgroundImageURL = snapshot.backgroundPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        backgroundWorldRect = snapshot.backgroundWorldRect
        backgroundOpacity = snapshot.backgroundOpacity
        visualizationPalette = snapshot.palette
    }

    func requestScreenshotExport(to url: URL) {
        screenshotExportRequest = ScreenshotExportRequest(id: UUID(), url: url)
        runtimeMessage = "Exporting screenshot..."
    }

    func completeScreenshotExport(id: UUID, result: Result<URL, Error>) {
        guard screenshotExportRequest?.id == id else { return }
        screenshotExportRequest = nil
        switch result {
        case .success(let url):
            runtimeMessage = "Exported screenshot to \(url.lastPathComponent)"
        case .failure(let error):
            runtimeMessage = "Screenshot export failed: \(error.localizedDescription)"
        }
    }

    func performInitialLoadIfNeeded() {
        guard !didAttemptInitialLoad else { return }
        didAttemptInitialLoad = true
        guard let initialOpenURL else { return }
        Task { @MainActor in
            await load(url: initialOpenURL)
        }
    }

    func load(url: URL) async {
        await shutdownSession()
        loadState = .loading(url.lastPathComponent)
        liveState = SimulationState()
        runtimeMessage = nil
        breakpoints = []
        trackerSamples = []
        trackerValueSamples = []
        resetPlaybackSpeed()
        selectedVehicleID = nil
        selectedEdgeIDs = []
        selectedVehicleIDs = []
        selectedRouteEdgeIDs = []
        clearHoverRoutePreview()
        vehicleRouteCache = [:]
        vehicleRouteOrderCache = [:]
        laneOccupancyByID = [:]
        selectedEdgeID = nil
        isFollowingSelectedVehicle = false
        isRotatingWithSelectedVehicle = false
        nativeEditor = NativeNetworkEditorState()
        resetNativeEditorHistory()
        nativeEditTool = .select
        latestViewportBounds = nil
        spatialIndexes = nil
        do {
            let resolved = try resolveInputURL(url)
            let parsed = try await Task.detached(priority: .userInitiated) {
                let graph = try NetXMLParser.parse(url: resolved.netURL)
                for additionalURL in resolved.additionalURLs {
                    try NetXMLParser.parseAdditional(url: additionalURL, into: graph)
                }
                return graph
            }.value
            graph = parsed
            spatialIndexes = parsed.makeSpatialIndexes()
            sourceURL = url
            loadState = .ready
            rememberRecentDocument(url)
            if let configURL = resolved.configURL {
                do {
                    let running = try await RunningSUMOSession.start(
                        config: configURL,
                        subscriptionAnchorID: parsed.junctions.first?.id,
                        vehicleUpdateMode: vehicleUpdateMode
                    )
                    session = running
                    if let latestViewportBounds {
                        updateVisibleWorldBounds(latestViewportBounds)
                    }
                    runtimeMessage = connectionMessage(prefix: "Connected", session: running)
                } catch {
                    runtimeMessage = "Network loaded. SUMO launch failed: \(error.localizedDescription)"
                }
            }
        } catch {
            graph = nil
            sourceURL = url
            loadState = .failed(error.localizedDescription)
        }
    }

    func attach(url: URL, host: String, port: Int, clientOrder: Int32) async {
        await shutdownSession()
        loadState = .loading("Attaching to \(host):\(port)")
        liveState = SimulationState()
        runtimeMessage = nil
        breakpoints = []
        trackerSamples = []
        trackerValueSamples = []
        resetPlaybackSpeed()
        selectedVehicleID = nil
        selectedEdgeIDs = []
        selectedVehicleIDs = []
        selectedRouteEdgeIDs = []
        clearHoverRoutePreview()
        vehicleRouteCache = [:]
        vehicleRouteOrderCache = [:]
        laneOccupancyByID = [:]
        selectedEdgeID = nil
        isFollowingSelectedVehicle = false
        isRotatingWithSelectedVehicle = false
        nativeEditor = NativeNetworkEditorState()
        resetNativeEditorHistory()
        nativeEditTool = .select
        latestViewportBounds = nil
        spatialIndexes = nil
        do {
            let resolved = try resolveInputURL(url)
            let parsed = try await Task.detached(priority: .userInitiated) {
                let graph = try NetXMLParser.parse(url: resolved.netURL)
                for additionalURL in resolved.additionalURLs {
                    try NetXMLParser.parseAdditional(url: additionalURL, into: graph)
                }
                return graph
            }.value
            graph = parsed
            spatialIndexes = parsed.makeSpatialIndexes()
            sourceURL = url
            loadState = .ready
            rememberRecentDocument(url)

            do {
                let running = try await RunningSUMOSession.attach(
                    host: host,
                    port: port,
                    clientOrder: clientOrder,
                    subscriptionAnchorID: parsed.junctions.first?.id,
                    vehicleUpdateMode: vehicleUpdateMode
                )
                session = running
                if let latestViewportBounds {
                    updateVisibleWorldBounds(latestViewportBounds)
                }
                runtimeMessage = connectionMessage(prefix: "Attached", session: running, suffix: " at \(host):\(port)")
                isPlaying = true
                resetPlaybackSpeed()
                startPlayback()
            } catch {
                runtimeMessage = "Network loaded. TraCI attach failed: \(error.localizedDescription)"
            }
        } catch {
            graph = nil
            sourceURL = url
            loadState = .failed(error.localizedDescription)
        }
    }

    func togglePlayPause() {
        guard session != nil else { return }
        isPlaying.toggle()
        if isPlaying {
            resetPlaybackSpeed()
            startPlayback()
        } else {
            playTask?.cancel()
            playTask = nil
            resetPlaybackSpeed()
        }
    }

    func stepOnce() {
        Task { @MainActor in
            await stepOnceNow()
        }
    }

    func stepOnceNow() async {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
        await stepSimulation(updatePlaybackSpeed: false)
        resetPlaybackSpeed()
    }

    func terminateRunningSessionForTesting() async {
        await session?.disconnectAfterFailure()
    }

    func stop() async {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
        resetPlaybackSpeed()
        if canRunSimulation {
            if isExternalTraCIAttached {
                runtimeMessage = String(format: "Viewer sync paused at t = %.2fs", liveState.simTime)
            } else {
                runtimeMessage = String(format: "Stopped at t = %.2fs", liveState.simTime)
            }
        }
    }

    func recordPlaybackStep(simTime: Double, wallTime: TimeInterval) {
        defer {
            lastPlaybackSimTime = simTime
            lastPlaybackWallTime = wallTime
        }

        guard
            let lastPlaybackWallTime,
            let lastPlaybackSimTime
        else {
            playbackSpeedFactor = 0
            return
        }

        let wallDelta = wallTime - lastPlaybackWallTime
        let simDelta = simTime - lastPlaybackSimTime
        guard wallDelta > 0, simDelta >= 0 else {
            playbackSpeedFactor = 0
            return
        }

        playbackSpeedFactor = simDelta / wallDelta
    }

    func playbackDelayNanoseconds() -> UInt64 {
        UInt64(max(stepDelay, 0.02) * 1_000_000_000)
    }

    func playbackLoopDelayNanoseconds() -> UInt64 {
        isExternalTraCIAttached ? Self.externalPlaybackDelayNanoseconds : playbackDelayNanoseconds()
    }

    func resetPlaybackSpeed() {
        playbackSpeedFactor = 0
        lastPlaybackWallTime = nil
        lastPlaybackSimTime = nil
    }

    @discardableResult
    func addBreakpoint(at time: Double) -> Bool {
        guard time.isFinite, time >= 0 else {
            runtimeMessage = "Breakpoint time must be a non-negative number."
            return false
        }
        guard breakpoints.contains(where: { abs($0.time - time) < 0.001 }) == false else {
            runtimeMessage = String(format: "Breakpoint at %.2fs already exists.", time)
            return false
        }

        breakpoints.append(SimulationBreakpoint(time: time))
        breakpoints.sort { $0.time < $1.time }
        runtimeMessage = String(format: "Added breakpoint at %.2fs.", time)
        return true
    }

    func removeBreakpoint(id: SimulationBreakpoint.ID) {
        breakpoints.removeAll { $0.id == id }
    }

    func clearBreakpoints() {
        breakpoints = []
    }

    func reachedBreakpoint(from previousTime: Double, to currentTime: Double) -> SimulationBreakpoint? {
        guard currentTime >= previousTime else { return nil }
        let epsilon = 0.000_1
        return breakpoints.first { breakpoint in
            breakpoint.time > previousTime + epsilon && breakpoint.time <= currentTime + epsilon
        }
    }

    func jumpToBreakpoint(_ breakpoint: SimulationBreakpoint) {
        jumpToBreakpoint(at: breakpoint.time)
    }

    func jumpToBreakpoint(at time: Double) {
        guard time.isFinite, time >= 0 else {
            runtimeMessage = "Breakpoint time must be a non-negative number."
            return
        }
        guard canRunSimulation else {
            runtimeMessage = "Open a runnable SUMO configuration before jumping to a breakpoint."
            return
        }
        guard liveState.simTime <= time + 0.000_1 else {
            runtimeMessage = String(
                format: "Cannot jump back from t = %.2fs to %.2fs.",
                liveState.simTime,
                time
            )
            return
        }
        if breakpoints.contains(where: { abs($0.time - time) < 0.001 }) == false {
            _ = addBreakpoint(at: time)
        }
        isPlaying = true
        resetPlaybackSpeed()
        startPlayback()
        runtimeMessage = String(format: "Running to breakpoint %.2fs.", time)
    }

    func recordTrackerSample(simTime: Double, vehicleCount: Int, speedFactor: Double) {
        guard simTime.isFinite, speedFactor.isFinite else { return }
        if let last = trackerSamples.last, abs(last.simTime - simTime) < 0.000_1 {
            trackerSamples[trackerSamples.count - 1] = TrackerSample(
                simTime: simTime,
                vehicleCount: vehicleCount,
                speedFactor: speedFactor
            )
        } else {
            trackerSamples.append(TrackerSample(
                simTime: simTime,
                vehicleCount: vehicleCount,
                speedFactor: speedFactor
            ))
        }
        if trackerSamples.count > Self.maxTrackerSampleCount {
            trackerSamples.removeFirst(trackerSamples.count - Self.maxTrackerSampleCount)
        }
        recordTrackerValueSample(
            simTime: simTime,
            variable: .vehicleCount,
            objectID: nil,
            value: Double(vehicleCount)
        )
        recordTrackerValueSample(
            simTime: simTime,
            variable: .playbackSpeed,
            objectID: nil,
            value: speedFactor
        )
    }

    func recordTrackerValueSample(
        simTime: Double,
        variable: TrackerVariable,
        objectID: String?,
        value: Double
    ) {
        guard simTime.isFinite, value.isFinite else { return }
        if let lastIndex = trackerValueSamples.lastIndex(where: {
            $0.variable == variable &&
                $0.objectID == objectID &&
                abs($0.simTime - simTime) < 0.000_1
        }) {
            trackerValueSamples[lastIndex] = TrackerValueSample(
                simTime: simTime,
                variable: variable,
                objectID: objectID,
                value: value
            )
        } else {
            trackerValueSamples.append(TrackerValueSample(
                simTime: simTime,
                variable: variable,
                objectID: objectID,
                value: value
            ))
        }
        if trackerValueSamples.count > Self.maxTrackerValueSampleCount {
            trackerValueSamples.removeFirst(trackerValueSamples.count - Self.maxTrackerValueSampleCount)
        }
    }

    func recordSelectedObjectTrackerSamples(simTime: Double, state: SimulationState) {
        let vehicleIDs = selectedVehicleIDs.union(selectedVehicleID.map { [$0] } ?? [])
        for vehicleID in vehicleIDs.sorted() {
            let snapshot = state.vehicles.first { $0.id == vehicleID }
            let details = state.selectedVehicle?.id == vehicleID ? state.selectedVehicle : nil
            if let speed = snapshot?.speed ?? details?.speed {
                recordTrackerValueSample(
                    simTime: simTime,
                    variable: .selectedVehicleSpeed,
                    objectID: vehicleID,
                    value: Double(speed)
                )
            }
            if let acceleration = snapshot?.acceleration ?? details?.acceleration {
                recordTrackerValueSample(
                    simTime: simTime,
                    variable: .selectedVehicleAcceleration,
                    objectID: vehicleID,
                    value: Double(acceleration)
                )
            }
            if let co2Emission = snapshot?.co2Emission {
                recordTrackerValueSample(
                    simTime: simTime,
                    variable: .selectedVehicleCO2,
                    objectID: vehicleID,
                    value: Double(co2Emission)
                )
            }
        }

        for edgeID in selectedEdgeIDs.sorted() {
            let occupancies = lanes(forEdgeID: edgeID).compactMap { laneOccupancyByID[$0.id] }
            guard occupancies.isEmpty == false else { continue }
            let average = occupancies.reduce(Float(0), +) / Float(occupancies.count)
            recordTrackerValueSample(
                simTime: simTime,
                variable: .selectedEdgeOccupancy,
                objectID: edgeID,
                value: Double(average)
            )
        }
    }

    func hoverVehicle(_ id: String?) {
        guard hoveredVehicleID != id else { return }

        hoverRouteTask?.cancel()
        hoverRouteTask = nil
        hoveredVehicleID = id

        guard let id else {
            hoveredVehicleRouteEdgeIDs = []
            return
        }

        if id == selectedVehicleID {
            hoveredVehicleRouteEdgeIDs = selectedVehicleRouteEdgeIDs
            return
        }

        if let cached = vehicleRouteCache[id] {
            hoveredVehicleRouteEdgeIDs = cached
            return
        }

        hoveredVehicleRouteEdgeIDs = []
        hoverRouteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard
                !Task.isCancelled,
                let self,
                self.hoveredVehicleID == id,
                let session = self.session
            else {
                return
            }

            let route = (try? await session.routeEdges(forVehicle: id)) ?? []
            guard !Task.isCancelled, self.hoveredVehicleID == id else { return }
            let routeSet = Set(route)
            self.vehicleRouteCache[id] = routeSet
            self.vehicleRouteOrderCache[id] = route
            self.hoveredVehicleRouteEdgeIDs = routeSet
        }
    }

    private func stepSimulation(updatePlaybackSpeed: Bool = true) async {
        guard let session else { return }
        do {
            let previousTime = liveState.simTime
            let nextState = try await session.step()
            liveState = nextState
            await updateLaneOccupanciesIfNeeded(session: session)
            if updatePlaybackSpeed {
                recordPlaybackStep(
                    simTime: nextState.simTime,
                    wallTime: Date.timeIntervalSinceReferenceDate
                )
            }
            recordTrackerSample(
                simTime: nextState.simTime,
                vehicleCount: nextState.vehicles.count,
                speedFactor: playbackSpeedFactor
            )
            recordSelectedObjectTrackerSamples(simTime: nextState.simTime, state: nextState)
            if playbackSpeedFactor > 0 {
                runtimeMessage = String(
                    format: "t = %.2fs, %d vehicles, %.1fx",
                    liveState.simTime,
                    liveState.vehicles.count,
                    playbackSpeedFactor
                )
            } else {
                runtimeMessage = String(format: "t = %.2fs, %d vehicles", liveState.simTime, liveState.vehicles.count)
            }
            if let breakpoint = reachedBreakpoint(from: previousTime, to: nextState.simTime) {
                runtimeMessage = String(
                    format: "Paused at breakpoint %.2fs (t = %.2fs).",
                    breakpoint.time,
                    nextState.simTime
                )
                if isPlaying {
                    isPlaying = false
                    playTask?.cancel()
                    playTask = nil
                    resetPlaybackSpeed()
                }
            }
        } catch {
            runtimeMessage = "Simulation disconnected: \(error.localizedDescription)"
            isPlaying = false
            playTask?.cancel()
            playTask = nil
            viewportSubscriptionTask?.cancel()
            viewportSubscriptionTask = nil
            vehicleUpdateModeTask?.cancel()
            vehicleUpdateModeTask = nil
            self.session = nil
            liveState = SimulationState(simTime: liveState.simTime)
            selectedVehicleID = nil
            selectedVehicleIDs = []
            selectedRouteEdgeIDs = []
            vehicleRouteCache = [:]
            vehicleRouteOrderCache = [:]
            laneOccupancyByID = [:]
            clearHoverRoutePreview()
            resetPlaybackSpeed()
            await session.disconnectAfterFailure()
        }
    }

    private func updateLaneOccupanciesIfNeeded(session: RunningSUMOSession) async {
        guard laneColorMode == .occupancy else { return }
        guard let graph else { return }
        let laneIDs = visibleLaneIDs(graph: graph, limit: 600)
        guard laneIDs.isEmpty == false else { return }
        do {
            let occupancies = try await session.laneOccupancies(ids: laneIDs)
            laneOccupancyByID.merge(occupancies) { _, new in new }
        } catch {
            runtimeMessage = "Lane occupancy update failed: \(error.localizedDescription)"
        }
    }

    func updateVisibleWorldBounds(_ bounds: SIMD4<Float>) {
        latestViewportBounds = bounds
        guard vehicleUpdateMode == .subscriptions else {
            viewportSubscriptionTask?.cancel()
            return
        }
        guard
            let graph,
            let request = ViewportSubscriptionPlanner.request(
                graph: graph,
                indexes: spatialIndexes,
                visibleBounds: bounds
            )
        else {
            return
        }
        viewportSubscriptionTask?.cancel()
        viewportSubscriptionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, let self, let session = self.session else { return }
            do {
                try await session.updateVehicleViewport(anchorID: request.anchorJunctionID, range: request.range)
            } catch {
                self.runtimeMessage = "Viewport subscription failed: \(error.localizedDescription)"
            }
        }
    }

    private func applyVehicleUpdateModeChange() {
        viewportSubscriptionTask?.cancel()
        vehicleUpdateModeTask?.cancel()
        guard let session else {
            runtimeMessage = "Vehicle updates: \(vehicleUpdateMode.title)"
            return
        }
        let requestedMode = vehicleUpdateMode
        let request = currentVehicleViewportRequest()
        let fallbackAnchorID = graph?.junctions.first?.id
        vehicleUpdateModeTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                try await session.setVehicleUpdateMode(
                    requestedMode,
                    anchorID: request?.anchorJunctionID ?? fallbackAnchorID,
                    range: request?.range ?? 1e6
                )
                self.runtimeMessage = "Vehicle updates: \(requestedMode.title)"
            } catch {
                self.runtimeMessage = "Vehicle update mode failed: \(error.localizedDescription)"
            }
        }
    }

    private func currentVehicleViewportRequest() -> VehicleViewportSubscriptionRequest? {
        guard
            let graph,
            let latestViewportBounds,
            let spatialIndexes
        else {
            return nil
        }
        return ViewportSubscriptionPlanner.request(
            graph: graph,
            indexes: spatialIndexes,
            visibleBounds: latestViewportBounds
        )
    }

    func selectEdge(_ id: String?) {
        guard let id else {
            selectedEdgeID = nil
            return
        }
        if selectedEdgeID == id {
            removeEdgeFromSelection(id)
        } else {
            setSelectedEdge(id)
        }
    }

    func setSelectedEdge(_ id: String?) {
        selectedEdgeID = id
        if let id {
            selectedEdgeIDs.insert(id)
            selectVehicle(nil)
            isFollowingSelectedVehicle = false
            isRotatingWithSelectedVehicle = false
        }
    }

    func toggleEdgeSelection(_ id: String) {
        if selectedEdgeIDs.contains(id) {
            removeEdgeFromSelection(id)
        } else {
            selectedEdgeIDs.insert(id)
            selectedEdgeID = id
            runtimeMessage = "Added edge \(id) to selection"
        }
    }

    func removeEdgeFromSelection(_ id: String) {
        selectedEdgeIDs.remove(id)
        selectedRouteEdgeIDs.remove(id)
        if selectedEdgeID == id {
            selectedEdgeID = nil
        }
        runtimeMessage = "Removed edge \(id) from selection"
    }

    func selectVehicle(_ id: String?) {
        guard selectedVehicleID != id else { return }
        selectedVehicleID = id
        if let id {
            selectedVehicleIDs.insert(id)
            selectedEdgeID = nil
        }
        if id == nil {
            liveState.selectedVehicle = nil
            isFollowingSelectedVehicle = false
            isRotatingWithSelectedVehicle = false
        }
        Task { @MainActor [weak self] in
            guard let self, let session = self.session else { return }
            do {
                try await session.selectVehicle(id)
            } catch {
                self.runtimeMessage = "Vehicle selection failed: \(error.localizedDescription)"
            }
        }
    }

    func toggleVehicleSelection(_ id: String) {
        if selectedVehicleIDs.contains(id) {
            removeVehicleFromSelection(id)
        } else {
            selectedVehicleIDs.insert(id)
            selectVehicle(id)
            runtimeMessage = "Added vehicle \(id) to selection"
        }
    }

    func removeVehicleFromSelection(_ id: String) {
        selectedVehicleIDs.remove(id)
        if selectedVehicleID == id {
            selectVehicle(nil)
        }
        if selectedVehicleIDs.isEmpty {
            isFollowingSelectedVehicle = false
            isRotatingWithSelectedVehicle = false
        }
        runtimeMessage = "Removed vehicle \(id) from selection"
    }

    func followVehicle(_ id: String) {
        selectVehicle(id)
        isFollowingSelectedVehicle = true
    }

    func toggleFollowSelectedVehicle() {
        guard canFollowSelectedVehicle else {
            isFollowingSelectedVehicle = false
            isRotatingWithSelectedVehicle = false
            return
        }
        isFollowingSelectedVehicle.toggle()
        if !isFollowingSelectedVehicle {
            isRotatingWithSelectedVehicle = false
        }
    }

    func toggleRotateWithSelectedVehicle() {
        guard isFollowingSelectedVehicle, canFollowSelectedVehicle else {
            isRotatingWithSelectedVehicle = false
            return
        }
        isRotatingWithSelectedVehicle.toggle()
    }

    func selectRouteEdges(_ edgeIDs: [String], vehicleID: String? = nil) {
        let routeEdges = Set(edgeIDs.filter { !$0.isEmpty })
        guard routeEdges.isEmpty == false else {
            runtimeMessage = vehicleID.map { "No route edges available for vehicle \($0)." } ?? "No route edges available."
            return
        }
        selectedRouteEdgeIDs = routeEdges
        selectedEdgeIDs.formUnion(routeEdges)
        if selectedEdgeID == nil {
            selectedEdgeID = edgeIDs.first { !$0.isEmpty }
        }
        if let vehicleID {
            runtimeMessage = "Selected route for vehicle \(vehicleID) (\(routeEdges.count) edges)"
        } else {
            runtimeMessage = "Selected route (\(routeEdges.count) edges)"
        }
    }

    func selectRouteForVehicle(_ id: String) {
        selectVehicle(id)
        if let routeEdges = cachedRouteEdges(forVehicle: id), routeEdges.isEmpty == false {
            selectRouteEdges(routeEdges, vehicleID: id)
            return
        }
        guard let session else {
            runtimeMessage = "Route edges for \(id) are unavailable until a SUMO session is active."
            return
        }

        Task { @MainActor [weak self] in
            do {
                let routeEdges = try await session.routeEdges(forVehicle: id)
                guard let self else { return }
                self.vehicleRouteCache[id] = Set(routeEdges)
                self.vehicleRouteOrderCache[id] = routeEdges
                self.selectRouteEdges(routeEdges, vehicleID: id)
            } catch {
                self?.runtimeMessage = "Route lookup failed for \(id): \(error.localizedDescription)"
            }
        }
    }

    func copyRouteForVehicle(_ id: String) {
        if let routeEdges = cachedRouteEdges(forVehicle: id), routeEdges.isEmpty == false {
            copyRouteEdges(routeEdges, vehicleID: id)
            return
        }
        guard let session else {
            runtimeMessage = "Route edges for \(id) are unavailable until a SUMO session is active."
            return
        }

        Task { @MainActor [weak self] in
            do {
                let routeEdges = try await session.routeEdges(forVehicle: id)
                guard let self else { return }
                self.vehicleRouteCache[id] = Set(routeEdges)
                self.vehicleRouteOrderCache[id] = routeEdges
                self.copyRouteEdges(routeEdges, vehicleID: id)
            } catch {
                self?.runtimeMessage = "Route copy failed for \(id): \(error.localizedDescription)"
            }
        }
    }

    func clearSelection() {
        selectedEdgeID = nil
        selectedEdgeIDs = []
        selectedVehicleIDs = []
        selectedRouteEdgeIDs = []
        isFollowingSelectedVehicle = false
        isRotatingWithSelectedVehicle = false
        selectVehicle(nil)
    }

    func copyObjectID(_ id: String, label: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
        runtimeMessage = "Copied \(label) ID \(id)"
    }

    private func cachedRouteEdges(forVehicle id: String) -> [String]? {
        if let cached = vehicleRouteOrderCache[id] {
            return cached
        }
        if let cached = vehicleRouteCache[id] {
            return Array(cached).sorted()
        }
        guard liveState.selectedVehicle?.id == id else { return nil }
        return liveState.selectedVehicle?.routeEdgeIDs
    }

    private func copyRouteEdges(_ routeEdges: [String], vehicleID: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(routeEdges.joined(separator: " "), forType: .string)
        runtimeMessage = "Copied route for vehicle \(vehicleID) (\(routeEdges.count) edges)"
    }

    private func clearHoverRoutePreview() {
        hoverRouteTask?.cancel()
        hoverRouteTask = nil
        hoveredVehicleID = nil
        hoveredVehicleRouteEdgeIDs = []
    }

    private func startPlayback() {
        playTask?.cancel()
        playTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { return }
                await self.stepSimulation()
                try? await Task.sleep(nanoseconds: self.playbackLoopDelayNanoseconds())
            }
        }
    }

    private func shutdownSession() async {
        playTask?.cancel()
        playTask = nil
        viewportSubscriptionTask?.cancel()
        viewportSubscriptionTask = nil
        vehicleUpdateModeTask?.cancel()
        vehicleUpdateModeTask = nil
        clearHoverRoutePreview()
        isPlaying = false
        resetPlaybackSpeed()
        if let session {
            await session.close()
        }
        session = nil
    }

    private func resolveInputURL(_ url: URL) throws -> (netURL: URL, configURL: URL?, additionalURLs: [URL]) {
        if url.lastPathComponent.hasSuffix(".net.xml") {
            return (url, nil, [])
        }
        if url.pathExtension == "sumocfg" {
            let parsed = try SUMOConfigNetFileParser.parse(configURL: url)
            return (parsed.netURL, url, parsed.additionalURLs)
        }
        return (url, nil, [])
    }

    private func visibleLaneIDs(graph: NetGraph, limit: Int) -> [String] {
        let laneIndexes: [Int]
        if let latestViewportBounds, let spatialIndexes {
            let queried = spatialIndexes.lanes.query(in: latestViewportBounds)
            laneIndexes = queried[..<min(limit, queried.count)].map(Int.init)
        } else {
            let allIndexes = Array(graph.lanes.indices)
            laneIndexes = Array(allIndexes[..<min(limit, allIndexes.count)])
        }
        return laneIndexes.compactMap { index in
            guard graph.lanes.indices.contains(index) else { return nil }
            return graph.lanes[index].id
        }
    }

    private func nearestJunction(to position: SIMD2<Float>, in graph: NetGraph) -> (id: String, distanceSquared: Float)? {
        graph.junctions
            .map { junction -> (id: String, distanceSquared: Float) in
                let dx = position.x - junction.position.x
                let dy = position.y - junction.position.y
                return (junction.id, dx * dx + dy * dy)
            }
            .min { $0.distanceSquared < $1.distanceSquared }
    }

    private func inferredBackgroundWorldRect(for url: URL) -> SIMD4<Float> {
        if let worldRect = worldFileRect(for: url) {
            return worldRect
        }
        if let graph {
            return graph.bounds()
        }
        return backgroundWorldRect
    }

    private func worldFileRect(for imageURL: URL) -> SIMD4<Float>? {
        guard
            let image = NSImage(contentsOf: imageURL),
            image.size.width > 0,
            image.size.height > 0
        else {
            return nil
        }
        let candidates = worldFileCandidates(for: imageURL)
        guard
            let worldURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
            let content = try? String(contentsOf: worldURL, encoding: .utf8)
        else {
            return nil
        }
        let values = content
            .split(whereSeparator: \.isNewline)
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count >= 6 else { return nil }

        let a = values[0]
        let d = values[1]
        let b = values[2]
        let e = values[3]
        let c = values[4]
        let f = values[5]
        let width = Double(image.size.width)
        let height = Double(image.size.height)
        let corners = [
            worldFilePoint(column: 0, row: 0, a: a, b: b, c: c, d: d, e: e, f: f),
            worldFilePoint(column: width, row: 0, a: a, b: b, c: c, d: d, e: e, f: f),
            worldFilePoint(column: 0, row: height, a: a, b: b, c: c, d: d, e: e, f: f),
            worldFilePoint(column: width, row: height, a: a, b: b, c: c, d: d, e: e, f: f),
        ]
        let xs = corners.map(\.x)
        let ys = corners.map(\.y)
        guard
            let minX = xs.min(),
            let minY = ys.min(),
            let maxX = xs.max(),
            let maxY = ys.max()
        else {
            return nil
        }
        return SIMD4(Float(minX), Float(minY), Float(maxX), Float(maxY))
    }

    private func worldFilePoint(
        column: Double,
        row: Double,
        a: Double,
        b: Double,
        c: Double,
        d: Double,
        e: Double,
        f: Double
    ) -> SIMD2<Double> {
        SIMD2(a * column + b * row + c, d * column + e * row + f)
    }

    private func worldFileCandidates(for url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        let basename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        var names = ["\(basename).wld"]
        switch ext {
        case "png":
            names.append("\(basename).pgw")
        case "jpg", "jpeg":
            names.append("\(basename).jgw")
        case "tif", "tiff", "geotiff":
            names.append("\(basename).tfw")
        default:
            break
        }
        return names.map { directory.appendingPathComponent($0) }
    }

    private func presentAttachSettings(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "Attach to TraCI"
        alert.informativeText = "Start the external SUMO run with a remote port and enough clients for both the controller and this viewer. Use a client order that does not collide with the controller."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Attach")
        alert.addButton(withTitle: "Cancel")

        let hostField = NSTextField(string: "127.0.0.1")
        let portField = NSTextField(string: "8813")
        let orderField = NSTextField(string: "2")
        [hostField, portField, orderField].forEach {
            $0.frame.size.width = 180
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Host"), hostField],
            [NSTextField(labelWithString: "Port"), portField],
            [NSTextField(labelWithString: "Client order"), orderField],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .fill
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        alert.accessoryView = grid

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let host = trimmed(hostField.stringValue)
        let portText = trimmed(portField.stringValue)
        let orderText = trimmed(orderField.stringValue)
        guard
            host.isEmpty == false,
            let port = Int(portText),
            (1...65_535).contains(port),
            let orderValue = Int32(orderText)
        else {
            runtimeMessage = "Invalid TraCI attach settings."
            return
        }

        Task { @MainActor in
            await attach(url: url, host: host, port: port, clientOrder: orderValue)
        }
    }

    private func resetEditingDocumentState() {
        liveState = SimulationState()
        runtimeMessage = nil
        breakpoints = []
        trackerSamples = []
        trackerValueSamples = []
        resetPlaybackSpeed()
        selectedVehicleID = nil
        selectedEdgeIDs = []
        selectedVehicleIDs = []
        selectedRouteEdgeIDs = []
        clearHoverRoutePreview()
        vehicleRouteCache = [:]
        vehicleRouteOrderCache = [:]
        laneOccupancyByID = [:]
        selectedEdgeID = nil
        isFollowingSelectedVehicle = false
        isRotatingWithSelectedVehicle = false
        latestViewportBounds = nil
        spatialIndexes = nil
    }

    @discardableResult
    private func commitNativeEditorMutation(_ mutate: (inout NativeNetworkEditorState) -> Bool) -> Bool {
        guard nativeEditor.isEnabled else { return false }
        let previous = nativeEditor
        var next = nativeEditor
        guard mutate(&next), next != previous else { return false }
        recordNativeEditorUndoSnapshot(previous)
        nativeEditor = next
        nativeMoveUndoJunctionID = nil
        nativeMoveUndoGeometryPoint = nil
        nativeMoveUndoJunctionShapePoint = nil
        syncNativeSelectionToViewerSelection()
        rebuildNativeNetworkGraph()
        return true
    }

    private func recordNativeEditorUndoSnapshot(_ snapshot: NativeNetworkEditorState) {
        guard snapshot.isEnabled else { return }
        if nativeEditorUndoStack.last == snapshot {
            return
        }
        nativeEditorUndoStack.append(snapshot)
        if nativeEditorUndoStack.count > Self.maxNativeEditorHistoryCount {
            nativeEditorUndoStack.removeFirst(nativeEditorUndoStack.count - Self.maxNativeEditorHistoryCount)
        }
        nativeEditorRedoStack.removeAll()
        updateNativeEditorHistoryCounts()
    }

    private func resetNativeEditorHistory() {
        nativeEditorUndoStack = []
        nativeEditorRedoStack = []
        nativeMoveUndoJunctionID = nil
        nativeMoveUndoGeometryPoint = nil
        nativeMoveUndoJunctionShapePoint = nil
        updateNativeEditorHistoryCounts()
    }

    private func updateNativeEditorHistoryCounts() {
        nativeEditorUndoCount = nativeEditorUndoStack.count
        nativeEditorRedoCount = nativeEditorRedoStack.count
    }

    private func validatedNativeObjectID(_ value: String, currentID: String) -> NativeEditorIDValidationResult {
        let cleanID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanID.isEmpty == false else {
            return .failure("IDs cannot be empty.")
        }
        guard cleanID.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) == false }) else {
            return .failure("IDs cannot contain whitespace.")
        }
        guard cleanID != currentID else {
            return .success(cleanID)
        }
        return .success(cleanID)
    }

    private func snappedNativePosition(_ position: SIMD2<Float>) -> SIMD2<Float> {
        guard nativeSnapToGrid, nativeGridSize.isFinite, nativeGridSize > 0 else {
            return position
        }
        return SIMD2(
            (position.x / nativeGridSize).rounded() * nativeGridSize,
            (position.y / nativeGridSize).rounded() * nativeGridSize
        )
    }

    private func rebuildNativeNetworkGraph() {
        guard nativeEditor.isEnabled else { return }
        let editedGraph = NativeNetworkGraphBuilder.makeGraph(from: nativeEditor)
        graph = editedGraph
        spatialIndexes = editedGraph.makeSpatialIndexes()
    }

    private func clearNativeEditorSelection() {
        nativeEditor.clearSelection()
        syncNativeSelectionToViewerSelection()
    }

    private func syncNativeSelectionToViewerSelection() {
        guard nativeEditor.isEnabled else { return }
        selectedEdgeID = nativeEditor.selectedEdgeID
        selectedEdgeIDs = nativeEditor.selectedEdgeIDs
        selectedVehicleID = nil
        selectedVehicleIDs = []
        selectedRouteEdgeIDs = []
        isFollowingSelectedVehicle = false
        isRotatingWithSelectedVehicle = false
    }

    private func nativeSelectionMessage(focusedLabel: String) -> String {
        let count = nativeEditor.selectedObjectCount
        if count > 1 {
            return "Selected \(focusedLabel) (\(count) objects selected)."
        }
        if count == 0 {
            return "Selection cleared."
        }
        return "Selected \(focusedLabel)."
    }

    private func runNetconvert(_ executableURL: URL, plan: NativeNetworkExportPlan) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--node-files", plan.nodeURL.path,
            "--edge-files", plan.edgeURL.path,
            "--output-file", plan.netURL.path,
        ]
        process.currentDirectoryURL = plan.netURL.deletingLastPathComponent()
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw RuntimeError(message?.isEmpty == false ? message! : "netconvert exited with status \(process.terminationStatus).")
        }
        try NativeNetworkSUMOWriter.writeConfigFile(plan: plan)
    }

    private func openInNetEdit(_ url: URL) {
        let plan = NetEditLaunchPlan(url: url)
        launchNetEdit(
            arguments: plan.arguments,
            workingDirectory: url.deletingLastPathComponent(),
            successMessage: "Opened \(url.lastPathComponent) in SUMO NetEdit."
        )
    }

    private func launchNetEdit(arguments: [String], workingDirectory: URL?, successMessage: String) {
        guard let netedit = SumoLauncher.locateTool(named: "netedit") else {
            runtimeMessage = "SUMO NetEdit not found. Install SUMO or add netedit to PATH."
            return
        }

        let process = Process()
        process.executableURL = netedit
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        let processID = ObjectIdentifier(process)
        process.terminationHandler = { [weak self, processID] _ in
            Task { @MainActor [weak self, processID] in
                self?.externalToolProcesses.removeAll { ObjectIdentifier($0) == processID }
            }
        }

        do {
            externalToolProcesses.append(process)
            try process.run()
            runtimeMessage = successMessage
        } catch {
            externalToolProcesses.removeAll { $0 === process }
            runtimeMessage = "SUMO NetEdit launch failed: \(error.localizedDescription)"
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func connectionMessage(prefix: String, session: RunningSUMOSession, suffix: String = "") -> String {
        let base = "\(prefix) to \(session.versionIdentifier)\(suffix) using \(session.vehicleUpdateMode.title.lowercased())"
        guard let warning = session.versionWarning else { return base }
        return "\(base). \(warning)"
    }

    private func rememberRecentDocument(_ url: URL) {
        let standardized = url.standardizedFileURL
        recentDocuments.removeAll { $0.id == standardized.path }
        recentDocuments.insert(RecentDocument(url: standardized), at: 0)
        if recentDocuments.count > Self.maxRecentDocumentCount {
            recentDocuments.removeSubrange(Self.maxRecentDocumentCount..<recentDocuments.count)
        }
        persistRecentDocuments()
    }

    private func persistRecentDocuments() {
        userDefaults.set(recentDocuments.map(\.url.path), forKey: Self.recentDocumentsKey)
    }

    private static func loadRecentDocuments(from userDefaults: UserDefaults) -> [RecentDocument] {
        let paths = userDefaults.stringArray(forKey: recentDocumentsKey) ?? []
        var seen = Set<String>()
        var documents: [RecentDocument] = []
        documents.reserveCapacity(min(paths.count, maxRecentDocumentCount))
        for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }
            documents.append(RecentDocument(url: url))
            if documents.count == maxRecentDocumentCount {
                break
            }
        }
        return documents
    }

    private func defaultScreenshotFilename() -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "SumoGUIMac"
        let safeBase = base
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return "\(safeBase.isEmpty ? "SumoGUIMac" : safeBase)-screenshot.png"
    }

    private func edgeFunctionText(_ function: EdgeFunction) -> String {
        switch function {
        case .normal:
            return "Normal"
        case .internalEdge:
            return "Internal"
        case .connector:
            return "Connector"
        case .crossing:
            return "Crossing"
        case .walkingArea:
            return "Walking area"
        }
    }

    private func boundsAreValid(_ bounds: SIMD4<Float>) -> Bool {
        bounds.x.isFinite && bounds.y.isFinite && bounds.z.isFinite && bounds.w.isFinite
    }
}

enum NativeNetworkEditTool: String, CaseIterable, Identifiable {
    case select
    case junction
    case edge

    var id: Self { self }

    var title: String {
        switch self {
        case .select:
            return "Select"
        case .junction:
            return "Junction"
        case .edge:
            return "Edge"
        }
    }

    var systemImage: String {
        switch self {
        case .select:
            return "cursorarrow"
        case .junction:
            return "smallcircle.filled.circle"
        case .edge:
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var helpText: String {
        switch self {
        case .select:
            return "Native editor select mode."
        case .junction:
            return "Click the canvas to add a junction."
        case .edge:
            return "Click two junctions to add an edge."
        }
    }
}

struct NativeNetworkCanvasClick: Equatable {
    let worldPosition: SIMD2<Float>
    let junctionID: String?
    let edgeID: String?
    let extendsSelection: Bool

    init(
        worldPosition: SIMD2<Float>,
        junctionID: String?,
        edgeID: String?,
        extendsSelection: Bool = false
    ) {
        self.worldPosition = worldPosition
        self.junctionID = junctionID
        self.edgeID = edgeID
        self.extendsSelection = extendsSelection
    }
}

struct NativeNetworkRubberBandSelection: Equatable {
    let worldBounds: SIMD4<Float>
    let extendsSelection: Bool
}

struct NativeEdgeGeometryHandle: Equatable, Identifiable {
    var edgeID: String
    var pointIndex: Int
    var position: SIMD2<Float>

    var id: String {
        "\(edgeID):\(pointIndex)"
    }
}

struct NativeJunctionShapeHandle: Equatable, Identifiable {
    var junctionID: String
    var pointIndex: Int
    var position: SIMD2<Float>

    var id: String {
        "\(junctionID):shape:\(pointIndex)"
    }
}

enum NativeEditorIDValidationResult: Equatable {
    case success(String)
    case failure(String)
}

struct NativeNetworkJunction: Equatable, Identifiable {
    var id: String
    var position: SIMD2<Float>
    var type: String = "priority"
    var radius: Float = Self.defaultRadius
    var shapePoints: [SIMD2<Float>] = []

    static let defaultRadius: Float = 4

    var hasCustomShape: Bool {
        shapePoints.count >= 3
    }
}

struct NativeNetworkEdge: Equatable, Identifiable {
    var id: String
    var fromJunctionID: String
    var toJunctionID: String
    var geometryPoints: [SIMD2<Float>] = []
    var priority: Int16 = 1
    var laneCount: Int = 1
    var speed: Float = 13.89
    var laneWidth: Float = 3.2
    var spreadType: String = "right"
    var allow: String = ""
    var disallow: String = ""
}

struct NativeNetworkSelectionRemoval: Equatable {
    let junctionCount: Int
    let edgeCount: Int
}

struct NativeNetworkSelectionSummary: Equatable {
    let junctionCount: Int
    let edgeCount: Int
}

struct NativeNetworkEditorState: Equatable {
    var isEnabled = false
    var junctions: [NativeNetworkJunction] = []
    var edges: [NativeNetworkEdge] = []
    var selectedJunctionID: String?
    var selectedEdgeID: String?
    var selectedJunctionIDs: Set<String> = []
    var selectedEdgeIDs: Set<String> = []
    var pendingEdgeStartJunctionID: String?
    private var nextJunctionNumber = 0
    private var nextEdgeNumber = 0

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    var previewNextJunctionID: String {
        var candidate = nextJunctionNumber
        while junction(id: "J\(candidate)") != nil {
            candidate += 1
        }
        return "J\(candidate)"
    }

    var selectedObjectCount: Int {
        selectedJunctionIDs.count + selectedEdgeIDs.count
    }

    init(importing graph: NetGraph) {
        isEnabled = true
        junctions = graph.junctions
            .filter { !$0.id.hasPrefix(":") }
            .map { junction in
                let shape = Array(graph.junctionShape(junction))
                return NativeNetworkJunction(
                    id: junction.id,
                    position: junction.position,
                    type: junction.type.isEmpty ? "priority" : junction.type,
                    radius: Self.estimatedJunctionRadius(center: junction.position, shape: shape),
                    shapePoints: shape.count >= 3 ? shape : []
                )
            }

        let junctionIDs = Set(junctions.map(\.id))
        edges = graph.edges.compactMap { edge in
            guard edge.function == .normal, junctionIDs.contains(edge.fromJunction), junctionIDs.contains(edge.toJunction) else {
                return nil
            }
            let lanes = edge.laneRange.count
            let laneWidth = edge.laneRange.compactMap { laneIndex -> Float? in
                let index = Int(laneIndex)
                guard graph.lanes.indices.contains(index) else { return nil }
                let width = graph.lanes[index].width
                return width.isFinite && width > 0 ? width : nil
            }.first ?? 3.2
            return NativeNetworkEdge(
                id: edge.id,
                fromJunctionID: edge.fromJunction,
                toJunctionID: edge.toJunction,
                priority: edge.priority,
                laneCount: max(lanes, 1),
                speed: 13.89,
                laneWidth: laneWidth
            )
        }
        nextJunctionNumber = nextNumber(after: junctions.map(\.id), prefix: "J")
        nextEdgeNumber = nextNumber(after: edges.map(\.id), prefix: "E")
    }

    func junction(id: String) -> NativeNetworkJunction? {
        junctions.first { $0.id == id }
    }

    func edge(id: String) -> NativeNetworkEdge? {
        edges.first { $0.id == id }
    }

    func hasEdge(from startID: String, to endID: String) -> Bool {
        edges.contains { $0.fromJunctionID == startID && $0.toJunctionID == endID }
    }

    func edgeGeometryHandles() -> [NativeEdgeGeometryHandle] {
        edges.flatMap { edge in
            edge.geometryPoints.enumerated().map { index, point in
                NativeEdgeGeometryHandle(edgeID: edge.id, pointIndex: index, position: point)
            }
        }
    }

    func junctionShapeHandles(for junctionIDs: Set<String>) -> [NativeJunctionShapeHandle] {
        guard junctionIDs.isEmpty == false else { return [] }
        return junctions
            .filter { junctionIDs.contains($0.id) && $0.hasCustomShape }
            .flatMap { junction in
                junction.shapePoints.enumerated().map { index, point in
                    NativeJunctionShapeHandle(junctionID: junction.id, pointIndex: index, position: point)
                }
            }
    }

    func edgePath(_ edge: NativeNetworkEdge) -> [SIMD2<Float>] {
        guard
            let from = junction(id: edge.fromJunctionID),
            let to = junction(id: edge.toJunctionID)
        else {
            return edge.geometryPoints
        }
        return [from.position] + edge.geometryPoints + [to.position]
    }

    func junctionShape(for junction: NativeNetworkJunction) -> [SIMD2<Float>] {
        guard junction.hasCustomShape == false else {
            return junction.shapePoints
        }
        return Self.defaultJunctionShape(center: junction.position, radius: junction.radius)
    }

    func objects(in bounds: SIMD4<Float>) -> NativeNetworkSelectionSummary {
        let normalized = Self.normalizedBounds(bounds)
        let junctionCount = junctions.filter { junctionIntersectsBounds($0, bounds: normalized) }.count
        let edgeCount = edges.filter { edgeIntersectsBounds($0, bounds: normalized) }.count
        return NativeNetworkSelectionSummary(junctionCount: junctionCount, edgeCount: edgeCount)
    }

    mutating func addJunction(at position: SIMD2<Float>) -> NativeNetworkJunction {
        let junction = NativeNetworkJunction(id: nextUniqueJunctionID(), position: position)
        junctions.append(junction)
        selectJunction(junction.id)
        return junction
    }

    mutating func addEdge(from startID: String, to endID: String) -> NativeNetworkEdge? {
        guard startID != endID, junction(id: startID) != nil, junction(id: endID) != nil else {
            return nil
        }
        guard edges.contains(where: { $0.fromJunctionID == startID && $0.toJunctionID == endID }) == false else {
            return nil
        }
        let edge = NativeNetworkEdge(id: nextUniqueEdgeID(), fromJunctionID: startID, toJunctionID: endID)
        edges.append(edge)
        selectEdge(edge.id)
        return edge
    }

    mutating func duplicateEdge(_ id: String) -> NativeNetworkEdge? {
        guard let source = edge(id: id) else { return nil }
        guard junction(id: source.fromJunctionID) != nil, junction(id: source.toJunctionID) != nil else { return nil }
        var duplicate = source
        duplicate.id = nextUniqueEdgeID()
        edges.append(duplicate)
        selectEdge(duplicate.id)
        return duplicate
    }

    mutating func reverseEdge(_ id: String) -> NativeNetworkEdge? {
        guard let source = edge(id: id) else { return nil }
        guard junction(id: source.fromJunctionID) != nil, junction(id: source.toJunctionID) != nil else { return nil }
        guard hasEdge(from: source.toJunctionID, to: source.fromJunctionID) == false else { return nil }
        var reverse = source
        reverse.id = nextUniqueEdgeID()
        reverse.fromJunctionID = source.toJunctionID
        reverse.toJunctionID = source.fromJunctionID
        reverse.geometryPoints = Array(source.geometryPoints.reversed())
        edges.append(reverse)
        selectEdge(reverse.id)
        return reverse
    }

    mutating func removeJunction(_ id: String) {
        let removedEdgeIDs = Set(edges.filter { $0.fromJunctionID == id || $0.toJunctionID == id }.map(\.id))
        junctions.removeAll { $0.id == id }
        edges.removeAll { $0.fromJunctionID == id || $0.toJunctionID == id }
        selectedJunctionIDs.remove(id)
        selectedEdgeIDs.subtract(removedEdgeIDs)
        if selectedJunctionID == id {
            selectedJunctionID = nil
        }
        if let selectedEdgeID, removedEdgeIDs.contains(selectedEdgeID) {
            self.selectedEdgeID = nil
        }
        if pendingEdgeStartJunctionID == id {
            pendingEdgeStartJunctionID = nil
        }
    }

    mutating func removeEdge(_ id: String) {
        edges.removeAll { $0.id == id }
        selectedEdgeIDs.remove(id)
        if selectedEdgeID == id {
            selectedEdgeID = nil
        }
    }

    mutating func removeSelectedObjects() -> NativeNetworkSelectionRemoval? {
        var junctionIDs = selectedJunctionIDs
        if let selectedJunctionID {
            junctionIDs.insert(selectedJunctionID)
        }
        var edgeIDs = selectedEdgeIDs
        if let selectedEdgeID {
            edgeIDs.insert(selectedEdgeID)
        }
        guard junctionIDs.isEmpty == false || edgeIDs.isEmpty == false else { return nil }

        for edge in edges where junctionIDs.contains(edge.fromJunctionID) || junctionIDs.contains(edge.toJunctionID) {
            edgeIDs.insert(edge.id)
        }

        let junctionCount = junctions.filter { junctionIDs.contains($0.id) }.count
        let edgeCount = edges.filter { edgeIDs.contains($0.id) }.count

        junctions.removeAll { junctionIDs.contains($0.id) }
        edges.removeAll { edgeIDs.contains($0.id) }
        if let pendingEdgeStartJunctionID, junctionIDs.contains(pendingEdgeStartJunctionID) {
            self.pendingEdgeStartJunctionID = nil
        }
        clearSelection()
        return NativeNetworkSelectionRemoval(junctionCount: junctionCount, edgeCount: edgeCount)
    }

    mutating func moveJunction(_ id: String, to position: SIMD2<Float>) -> Bool {
        guard let index = junctions.firstIndex(where: { $0.id == id }) else { return false }
        let delta = position - junctions[index].position
        junctions[index].position = position
        if junctions[index].hasCustomShape {
            junctions[index].shapePoints = junctions[index].shapePoints.map { $0 + delta }
        }
        return true
    }

    mutating func updateJunction(_ id: String, type: String) -> Bool {
        guard let index = junctions.firstIndex(where: { $0.id == id }) else { return false }
        junctions[index].type = type
        return true
    }

    mutating func updateJunction(_ id: String, radius: Float) -> Bool {
        guard let index = junctions.firstIndex(where: { $0.id == id }), radius.isFinite, radius > 0 else { return false }
        junctions[index].radius = radius
        return true
    }

    mutating func customizeJunctionShape(_ id: String) -> Bool {
        guard let index = junctions.firstIndex(where: { $0.id == id }) else { return false }
        guard junctions[index].hasCustomShape == false else { return false }
        junctions[index].shapePoints = junctionShape(for: junctions[index])
        focusJunction(id, preservingSelection: true)
        return true
    }

    mutating func resetJunctionShape(_ id: String) -> Bool {
        guard let index = junctions.firstIndex(where: { $0.id == id }) else { return false }
        guard junctions[index].hasCustomShape else { return false }
        junctions[index].shapePoints = []
        focusJunction(id, preservingSelection: true)
        return true
    }

    mutating func addShapePoint(toJunction id: String) -> Int? {
        guard let index = junctions.firstIndex(where: { $0.id == id }) else { return nil }
        if junctions[index].hasCustomShape == false {
            junctions[index].shapePoints = junctionShape(for: junctions[index])
        }
        let shape = junctions[index].shapePoints
        guard shape.count >= 3 else { return nil }
        var bestSegmentIndex = 0
        var bestLength: Float = -1
        for pointIndex in 0..<shape.count {
            let nextIndex = (pointIndex + 1) % shape.count
            let length = distance(shape[pointIndex], shape[nextIndex])
            if length > bestLength {
                bestSegmentIndex = pointIndex
                bestLength = length
            }
        }
        let nextIndex = (bestSegmentIndex + 1) % shape.count
        let midpoint = (shape[bestSegmentIndex] + shape[nextIndex]) * 0.5
        let insertionIndex = bestSegmentIndex + 1
        if insertionIndex >= junctions[index].shapePoints.count {
            junctions[index].shapePoints.append(midpoint)
        } else {
            junctions[index].shapePoints.insert(midpoint, at: insertionIndex)
        }
        focusJunction(id, preservingSelection: true)
        return insertionIndex
    }

    mutating func removeLastShapePoint(fromJunction id: String) -> Bool {
        guard let index = junctions.firstIndex(where: { $0.id == id }) else { return false }
        guard junctions[index].shapePoints.count > 3 else { return false }
        junctions[index].shapePoints.removeLast()
        focusJunction(id, preservingSelection: true)
        return true
    }

    mutating func moveJunctionShapePoint(junctionID: String, pointIndex: Int, to position: SIMD2<Float>) -> Bool {
        guard
            let index = junctions.firstIndex(where: { $0.id == junctionID }),
            junctions[index].shapePoints.indices.contains(pointIndex)
        else {
            return false
        }
        junctions[index].shapePoints[pointIndex] = position
        focusJunction(junctionID, preservingSelection: true)
        return true
    }

    mutating func renameJunction(_ id: String, to newID: String) -> Bool {
        guard id != newID else { return false }
        guard junction(id: newID) == nil else { return false }
        guard let index = junctions.firstIndex(where: { $0.id == id }) else { return false }
        junctions[index].id = newID
        for edgeIndex in edges.indices {
            if edges[edgeIndex].fromJunctionID == id {
                edges[edgeIndex].fromJunctionID = newID
            }
            if edges[edgeIndex].toJunctionID == id {
                edges[edgeIndex].toJunctionID = newID
            }
        }
        if selectedJunctionID == id {
            selectedJunctionID = newID
        }
        if selectedJunctionIDs.remove(id) != nil {
            selectedJunctionIDs.insert(newID)
        }
        if pendingEdgeStartJunctionID == id {
            pendingEdgeStartJunctionID = newID
        }
        return true
    }

    mutating func renameEdge(_ id: String, to newID: String) -> Bool {
        guard id != newID else { return false }
        guard edge(id: newID) == nil else { return false }
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        edges[index].id = newID
        if selectedEdgeID == id {
            selectedEdgeID = newID
        }
        if selectedEdgeIDs.remove(id) != nil {
            selectedEdgeIDs.insert(newID)
        }
        return true
    }

    mutating func updateEdge(_ id: String, priority: Int16) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        edges[index].priority = priority
        return true
    }

    mutating func updateEdge(_ id: String, laneCount: Int) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        edges[index].laneCount = max(1, laneCount)
        return true
    }

    mutating func updateEdge(_ id: String, speed: Float) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == id }), speed.isFinite, speed > 0 else { return false }
        edges[index].speed = speed
        return true
    }

    mutating func updateEdge(_ id: String, laneWidth: Float) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == id }), laneWidth.isFinite, laneWidth > 0 else { return false }
        edges[index].laneWidth = laneWidth
        return true
    }

    mutating func updateEdge(_ id: String, fromJunctionID: String) -> Bool {
        guard junction(id: fromJunctionID) != nil else { return false }
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        guard fromJunctionID != edges[index].toJunctionID else { return false }
        edges[index].fromJunctionID = fromJunctionID
        selectedEdgeID = id
        selectedJunctionID = nil
        return true
    }

    mutating func updateEdge(_ id: String, toJunctionID: String) -> Bool {
        guard junction(id: toJunctionID) != nil else { return false }
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        guard toJunctionID != edges[index].fromJunctionID else { return false }
        edges[index].toJunctionID = toJunctionID
        selectedEdgeID = id
        selectedJunctionID = nil
        return true
    }

    mutating func updateEdge(_ id: String, spreadType: String) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        edges[index].spreadType = spreadType
        return true
    }

    mutating func updateEdge(_ id: String, allow: String) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        edges[index].allow = allow
        if allow.isEmpty == false {
            edges[index].disallow = ""
        }
        return true
    }

    mutating func updateEdge(_ id: String, disallow: String) -> Bool {
        guard let index = edges.firstIndex(where: { $0.id == id }) else { return false }
        edges[index].disallow = disallow
        if disallow.isEmpty == false {
            edges[index].allow = ""
        }
        return true
    }

    mutating func addGeometryPoint(toEdge id: String) -> Int? {
        guard let edgeIndex = edges.firstIndex(where: { $0.id == id }) else { return nil }
        let path = edgePath(edges[edgeIndex])
        guard path.count >= 2 else { return nil }
        var bestSegmentIndex = 0
        var bestLength: Float = -1
        for index in 0..<(path.count - 1) {
            let length = distance(path[index], path[index + 1])
            if length > bestLength {
                bestSegmentIndex = index
                bestLength = length
            }
        }
        let midpoint = (path[bestSegmentIndex] + path[bestSegmentIndex + 1]) * 0.5
        let insertionIndex = min(bestSegmentIndex, edges[edgeIndex].geometryPoints.count)
        edges[edgeIndex].geometryPoints.insert(midpoint, at: insertionIndex)
        focusEdge(id, preservingSelection: true)
        return insertionIndex
    }

    mutating func removeLastGeometryPoint(fromEdge id: String) -> Bool {
        guard let edgeIndex = edges.firstIndex(where: { $0.id == id }) else { return false }
        guard edges[edgeIndex].geometryPoints.isEmpty == false else { return false }
        edges[edgeIndex].geometryPoints.removeLast()
        focusEdge(id, preservingSelection: true)
        return true
    }

    mutating func moveEdgeGeometryPoint(edgeID: String, pointIndex: Int, to position: SIMD2<Float>) -> Bool {
        guard
            let edgeIndex = edges.firstIndex(where: { $0.id == edgeID }),
            edges[edgeIndex].geometryPoints.indices.contains(pointIndex)
        else {
            return false
        }
        edges[edgeIndex].geometryPoints[pointIndex] = position
        focusEdge(edgeID, preservingSelection: true)
        return true
    }

    mutating func selectJunction(_ id: String, extending: Bool = false) {
        guard junction(id: id) != nil else { return }
        if extending {
            if selectedJunctionIDs.contains(id) {
                selectedJunctionIDs.remove(id)
                if selectedJunctionID == id {
                    selectedJunctionID = selectedJunctionIDs.sorted().first
                }
            } else {
                selectedJunctionIDs.insert(id)
                selectedJunctionID = id
            }
            selectedEdgeID = nil
        } else {
            selectedJunctionIDs = [id]
            selectedEdgeIDs = []
            selectedJunctionID = id
            selectedEdgeID = nil
        }
    }

    mutating func selectEdge(_ id: String, extending: Bool = false) {
        guard edge(id: id) != nil else { return }
        if extending {
            if selectedEdgeIDs.contains(id) {
                selectedEdgeIDs.remove(id)
                if selectedEdgeID == id {
                    selectedEdgeID = selectedEdgeIDs.sorted().first
                }
            } else {
                selectedEdgeIDs.insert(id)
                selectedEdgeID = id
            }
            selectedJunctionID = nil
        } else {
            selectedEdgeIDs = [id]
            selectedJunctionIDs = []
            selectedEdgeID = id
            selectedJunctionID = nil
        }
    }

    mutating func selectObjects(in bounds: SIMD4<Float>, extending: Bool) -> NativeNetworkSelectionSummary {
        let normalized = Self.normalizedBounds(bounds)
        let junctionIDs = Set(junctions.filter { junctionIntersectsBounds($0, bounds: normalized) }.map(\.id))
        let edgeIDs = Set(edges.filter { edgeIntersectsBounds($0, bounds: normalized) }.map(\.id))

        if extending {
            selectedJunctionIDs.formUnion(junctionIDs)
            selectedEdgeIDs.formUnion(edgeIDs)
        } else {
            selectedJunctionIDs = junctionIDs
            selectedEdgeIDs = edgeIDs
        }

        selectedJunctionID = selectedJunctionIDs.sorted().first
        selectedEdgeID = selectedJunctionID == nil ? selectedEdgeIDs.sorted().first : nil
        return NativeNetworkSelectionSummary(junctionCount: junctionIDs.count, edgeCount: edgeIDs.count)
    }

    mutating func focusJunction(_ id: String, preservingSelection: Bool) {
        if preservingSelection, selectedJunctionIDs.contains(id) {
            selectedJunctionID = id
            selectedEdgeID = nil
        } else {
            selectJunction(id)
        }
    }

    mutating func focusEdge(_ id: String, preservingSelection: Bool) {
        if preservingSelection, selectedEdgeIDs.contains(id) {
            selectedEdgeID = id
            selectedJunctionID = nil
        } else {
            selectEdge(id)
        }
    }

    mutating func clearSelection() {
        selectedJunctionID = nil
        selectedEdgeID = nil
        selectedJunctionIDs = []
        selectedEdgeIDs = []
    }

    private mutating func nextUniqueJunctionID() -> String {
        while junction(id: "J\(nextJunctionNumber)") != nil {
            nextJunctionNumber += 1
        }
        defer { nextJunctionNumber += 1 }
        return "J\(nextJunctionNumber)"
    }

    private mutating func nextUniqueEdgeID() -> String {
        while edge(id: "E\(nextEdgeNumber)") != nil {
            nextEdgeNumber += 1
        }
        defer { nextEdgeNumber += 1 }
        return "E\(nextEdgeNumber)"
    }

    private static func nextNumber(after ids: [String], prefix: String) -> Int {
        let numbers = ids.compactMap { id -> Int? in
            guard id.hasPrefix(prefix) else { return nil }
            return Int(id.dropFirst(prefix.count))
        }
        return (numbers.max() ?? -1) + 1
    }

    private static func estimatedJunctionRadius(center: SIMD2<Float>, shape: [SIMD2<Float>]) -> Float {
        let radius = shape.reduce(Float(0)) { partial, point in
            let dx = point.x - center.x
            let dy = point.y - center.y
            return max(partial, sqrt(dx * dx + dy * dy))
        }
        return radius.isFinite && radius > 0 ? radius : NativeNetworkJunction.defaultRadius
    }

    private func nextNumber(after ids: [String], prefix: String) -> Int {
        Self.nextNumber(after: ids, prefix: prefix)
    }

    private func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func defaultJunctionShape(center: SIMD2<Float>, radius: Float) -> [SIMD2<Float>] {
        let half = radius.isFinite && radius > 0 ? radius : NativeNetworkJunction.defaultRadius
        return [
            SIMD2(center.x - half, center.y - half),
            SIMD2(center.x + half, center.y - half),
            SIMD2(center.x + half, center.y + half),
            SIMD2(center.x - half, center.y + half),
        ]
    }

    private func junctionIntersectsBounds(_ junction: NativeNetworkJunction, bounds: SIMD4<Float>) -> Bool {
        if Self.bounds(bounds, contains: junction.position) {
            return true
        }
        let shape = junctionShape(for: junction)
        if shape.contains(where: { Self.bounds(bounds, contains: $0) }) {
            return true
        }
        guard shape.count > 1 else { return false }
        for index in 0..<shape.count {
            if Self.segmentIntersectsBounds(from: shape[index], to: shape[(index + 1) % shape.count], bounds: bounds) {
                return true
            }
        }
        return false
    }

    private func edgeIntersectsBounds(_ edge: NativeNetworkEdge, bounds: SIMD4<Float>) -> Bool {
        let points = edgePath(edge)
        guard points.isEmpty == false else { return false }
        if points.contains(where: { Self.bounds(bounds, contains: $0) }) {
            return true
        }
        guard points.count > 1 else { return false }
        for index in 0..<(points.count - 1) {
            if Self.segmentIntersectsBounds(from: points[index], to: points[index + 1], bounds: bounds) {
                return true
            }
        }
        return false
    }

    private static func normalizedBounds(_ bounds: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(
            min(bounds.x, bounds.z),
            min(bounds.y, bounds.w),
            max(bounds.x, bounds.z),
            max(bounds.y, bounds.w)
        )
    }

    private static func bounds(_ bounds: SIMD4<Float>, contains point: SIMD2<Float>) -> Bool {
        point.x >= bounds.x && point.x <= bounds.z && point.y >= bounds.y && point.y <= bounds.w
    }

    private static func segmentIntersectsBounds(from start: SIMD2<Float>, to end: SIMD2<Float>, bounds: SIMD4<Float>) -> Bool {
        let segmentBounds = SIMD4(
            min(start.x, end.x),
            min(start.y, end.y),
            max(start.x, end.x),
            max(start.y, end.y)
        )
        guard segmentBounds.z >= bounds.x,
              segmentBounds.x <= bounds.z,
              segmentBounds.w >= bounds.y,
              segmentBounds.y <= bounds.w
        else {
            return false
        }

        let corners = [
            SIMD2<Float>(bounds.x, bounds.y),
            SIMD2<Float>(bounds.z, bounds.y),
            SIMD2<Float>(bounds.z, bounds.w),
            SIMD2<Float>(bounds.x, bounds.w),
        ]
        for index in 0..<corners.count {
            if segmentsIntersect(start, end, corners[index], corners[(index + 1) % corners.count]) {
                return true
            }
        }
        return false
    }

    private static func segmentsIntersect(
        _ a: SIMD2<Float>,
        _ b: SIMD2<Float>,
        _ c: SIMD2<Float>,
        _ d: SIMD2<Float>
    ) -> Bool {
        let o1 = orientation(a, b, c)
        let o2 = orientation(a, b, d)
        let o3 = orientation(c, d, a)
        let o4 = orientation(c, d, b)

        if o1 == 0, onSegment(a, c, b) { return true }
        if o2 == 0, onSegment(a, d, b) { return true }
        if o3 == 0, onSegment(c, a, d) { return true }
        if o4 == 0, onSegment(c, b, d) { return true }
        return (o1 > 0) != (o2 > 0) && (o3 > 0) != (o4 > 0)
    }

    private static func orientation(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
        let value = (b.y - a.y) * (c.x - b.x) - (b.x - a.x) * (c.y - b.y)
        return abs(value) < 0.0001 ? 0 : value
    }

    private static func onSegment(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        b.x >= min(a.x, c.x) - 0.0001 &&
            b.x <= max(a.x, c.x) + 0.0001 &&
            b.y >= min(a.y, c.y) - 0.0001 &&
            b.y <= max(a.y, c.y) + 0.0001
    }
}

enum NativeNetworkGraphBuilder {
    static func makeGraph(from state: NativeNetworkEditorState) -> NetGraph {
        let graph = NetGraph()
        var contentBounds = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)

        for junction in state.junctions {
            let shape = state.junctionShape(for: junction)
            let offset = Int32(graph.junctionShapePoints.count)
            graph.junctionShapePoints.append(contentsOf: shape)
            let bounds = bounds(for: shape)
            let index = Int32(graph.junctions.count)
            graph.junctionIndex[junction.id] = index
            graph.junctions.append(Junction(
                id: junction.id,
                type: junction.type,
                position: junction.position,
                shapeOffset: offset,
                shapeCount: Int32(shape.count),
                bounds: bounds,
                incomingLanes: [],
                internalLanes: []
            ))
            contentBounds = mergeBounds(contentBounds, bounds)
        }

        let junctionByID = Dictionary(uniqueKeysWithValues: state.junctions.map { ($0.id, $0) })
        for nativeEdge in state.edges {
            guard
                let from = junctionByID[nativeEdge.fromJunctionID],
                let to = junctionByID[nativeEdge.toJunctionID]
            else {
                continue
            }
            let laneStart = Int32(graph.lanes.count)
            let laneCount = max(nativeEdge.laneCount, 1)
            let laneWidth = max(nativeEdge.laneWidth, 0.5)
            var edgeBounds = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
            for laneIndex in 0..<laneCount {
                let laneID = "\(nativeEdge.id)_\(laneIndex)"
                let centerline = [from.position] + nativeEdge.geometryPoints + [to.position]
                let shape = laneShape(
                    centerline: centerline,
                    laneIndex: laneIndex,
                    laneCount: laneCount,
                    laneWidth: laneWidth
                )
                let shapeOffset = Int32(graph.laneShapePoints.count)
                graph.laneShapePoints.append(contentsOf: shape)
                let laneBounds = paddedBounds(bounds(for: shape), minimumSpan: 0.5)
                let lane = Lane(
                    id: laneID,
                    edgeIndex: Int32(graph.edges.count),
                    index: Int16(laneIndex),
                    speed: nativeEdge.speed,
                    length: polylineLength(centerline),
                    width: laneWidth,
                    allowsAll: true,
                    shapeOffset: shapeOffset,
                    shapeCount: Int32(shape.count),
                    bounds: laneBounds
                )
                graph.laneIndex[laneID] = Int32(graph.lanes.count)
                graph.lanes.append(lane)
                edgeBounds = mergeBounds(edgeBounds, laneBounds)
                if let junctionIndex = graph.junctionIndex[nativeEdge.toJunctionID] {
                    graph.junctions[Int(junctionIndex)].incomingLanes.append(laneID)
                }
            }
            let laneEnd = Int32(graph.lanes.count)
            graph.edgeIndex[nativeEdge.id] = Int32(graph.edges.count)
            graph.edges.append(Edge(
                id: nativeEdge.id,
                fromJunction: nativeEdge.fromJunctionID,
                toJunction: nativeEdge.toJunctionID,
                function: .normal,
                priority: nativeEdge.priority,
                laneRange: laneStart..<laneEnd,
                bounds: edgeBounds
            ))
            contentBounds = mergeBounds(contentBounds, edgeBounds)
        }

        let declared = isValidBounds(contentBounds)
            ? paddedBounds(contentBounds, minimumSpan: 120)
            : SIMD4<Float>(-60, -60, 60, 60)
        graph.location.convBoundary = SIMD4<Double>(
            Double(declared.x),
            Double(declared.y),
            Double(declared.z),
            Double(declared.w)
        )
        graph.location.origBoundary = graph.location.convBoundary
        return graph
    }

    private static func laneShape(
        centerline: [SIMD2<Float>],
        laneIndex: Int,
        laneCount: Int,
        laneWidth: Float
    ) -> [SIMD2<Float>] {
        guard centerline.count > 1 else { return centerline }
        guard laneCount > 1 else { return centerline }
        let centerOffset = Float(laneIndex) - (Float(laneCount) - 1) * 0.5
        let offsetDistance = centerOffset * (laneWidth + 0.4)
        return centerline.indices.map { index in
            let previous = centerline[max(centerline.startIndex, index - 1)]
            let next = centerline[min(centerline.index(before: centerline.endIndex), index + 1)]
            let direction = next - previous
            let length = max(distance(previous, next), 0.001)
            let normal = SIMD2<Float>(-direction.y / length, direction.x / length)
            return centerline[index] + normal * offsetDistance
        }
    }

    private static func bounds(for points: [SIMD2<Float>]) -> SIMD4<Float> {
        var out = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for point in points {
            out = mergeBounds(out, SIMD4<Float>(point.x, point.y, point.x, point.y))
        }
        return out
    }

    private static func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let dx = b.x - a.x
        let dy = b.y - a.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func polylineLength(_ points: [SIMD2<Float>]) -> Float {
        guard points.count > 1 else { return 0 }
        var total: Float = 0
        for index in 0..<(points.count - 1) {
            total += distance(points[index], points[index + 1])
        }
        return total
    }

    private static func isValidBounds(_ bounds: SIMD4<Float>) -> Bool {
        bounds.x.isFinite && bounds.y.isFinite && bounds.z.isFinite && bounds.w.isFinite && bounds.x <= bounds.z && bounds.y <= bounds.w
    }

    private static func mergeBounds(_ lhs: SIMD4<Float>, _ rhs: SIMD4<Float>) -> SIMD4<Float> {
        if !isValidBounds(lhs) { return rhs }
        if !isValidBounds(rhs) { return lhs }
        return SIMD4(min(lhs.x, rhs.x), min(lhs.y, rhs.y), max(lhs.z, rhs.z), max(lhs.w, rhs.w))
    }

    private static func paddedBounds(_ bounds: SIMD4<Float>, minimumSpan: Float) -> SIMD4<Float> {
        guard isValidBounds(bounds) else { return SIMD4(0, 0, minimumSpan, minimumSpan) }
        var out = bounds
        if out.z - out.x < minimumSpan {
            let mid = (out.x + out.z) * 0.5
            out.x = mid - minimumSpan * 0.5
            out.z = mid + minimumSpan * 0.5
        }
        if out.w - out.y < minimumSpan {
            let mid = (out.y + out.w) * 0.5
            out.y = mid - minimumSpan * 0.5
            out.w = mid + minimumSpan * 0.5
        }
        return out
    }
}

struct NativeNetworkExportPlan: Equatable {
    let netURL: URL
    let nodeURL: URL
    let edgeURL: URL
    let configURL: URL

    init(outputNetURL: URL) {
        let netURL = Self.normalizedNetURL(outputNetURL)
        self.netURL = netURL
        let basePath = Self.basePath(for: netURL)
        nodeURL = URL(fileURLWithPath: "\(basePath).nod.xml")
        edgeURL = URL(fileURLWithPath: "\(basePath).edg.xml")
        configURL = URL(fileURLWithPath: "\(basePath).sumocfg")
    }

    private static func normalizedNetURL(_ url: URL) -> URL {
        let path = url.path
        if path.lowercased().hasSuffix(".net.xml") {
            return url
        }
        let base = path.lowercased().hasSuffix(".xml") ? String(path.dropLast(4)) : path
        return URL(fileURLWithPath: "\(base).net.xml")
    }

    private static func basePath(for netURL: URL) -> String {
        let path = netURL.path
        if path.lowercased().hasSuffix(".net.xml") {
            return String(path.dropLast(".net.xml".count))
        }
        return netURL.deletingPathExtension().path
    }
}

enum NativeNetworkSUMOWriter {
    static func writeSourceFiles(for state: NativeNetworkEditorState, plan: NativeNetworkExportPlan) throws {
        try nodeXML(for: state).write(to: plan.nodeURL, atomically: true, encoding: .utf8)
        try edgeXML(for: state).write(to: plan.edgeURL, atomically: true, encoding: .utf8)
    }

    static func writeConfigFile(plan: NativeNetworkExportPlan) throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <configuration>
            <input>
                <net-file value="\(xmlEscape(plan.netURL.lastPathComponent))"/>
            </input>
        </configuration>

        """
        try xml.write(to: plan.configURL, atomically: true, encoding: .utf8)
    }

    static func nodeXML(for state: NativeNetworkEditorState) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            "<nodes>",
        ]
        for junction in state.junctions.sorted(by: { $0.id < $1.id }) {
            var attributes = [
                #"id="\#(xmlEscape(junction.id))""#,
                #"x="\#(decimal(junction.position.x))""#,
                #"y="\#(decimal(junction.position.y))""#,
                #"type="\#(xmlEscape(junction.type))""#,
            ]
            if let shape = shapeAttribute(for: junction) {
                attributes.append(#"shape="\#(xmlEscape(shape))""#)
            } else if abs(junction.radius - NativeNetworkJunction.defaultRadius) > 0.001 {
                attributes.append(#"radius="\#(decimal(junction.radius))""#)
            }
            lines.append(
                "    <node \(attributes.joined(separator: " "))/>"
            )
        }
        lines.append("</nodes>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    static func edgeXML(for state: NativeNetworkEditorState) -> String {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            "<edges>",
        ]
        for edge in state.edges.sorted(by: { $0.id < $1.id }) {
            var attributes = [
                #"id="\#(xmlEscape(edge.id))""#,
                #"from="\#(xmlEscape(edge.fromJunctionID))""#,
                #"to="\#(xmlEscape(edge.toJunctionID))""#,
                #"priority="\#(edge.priority)""#,
                #"numLanes="\#(edge.laneCount)""#,
                #"speed="\#(decimal(edge.speed))""#,
                #"width="\#(decimal(edge.laneWidth))""#,
                #"spreadType="\#(xmlEscape(edge.spreadType))""#,
            ]
            if edge.allow.isEmpty == false {
                attributes.append(#"allow="\#(xmlEscape(edge.allow))""#)
            }
            if edge.disallow.isEmpty == false {
                attributes.append(#"disallow="\#(xmlEscape(edge.disallow))""#)
            }
            if let shape = shapeAttribute(for: edge, in: state) {
                attributes.append(#"shape="\#(xmlEscape(shape))""#)
            }
            lines.append(
                "    <edge \(attributes.joined(separator: " "))/>"
            )
        }
        lines.append("</edges>")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func decimal(_ value: Float) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func shapeAttribute(for edge: NativeNetworkEdge, in state: NativeNetworkEditorState) -> String? {
        guard edge.geometryPoints.isEmpty == false else { return nil }
        let shape = state.edgePath(edge)
        guard shape.count > 2 else { return nil }
        return shape
            .map { "\(decimal($0.x)),\(decimal($0.y))" }
            .joined(separator: " ")
    }

    private static func shapeAttribute(for junction: NativeNetworkJunction) -> String? {
        guard junction.hasCustomShape else { return nil }
        return junction.shapePoints
            .map { "\(decimal($0.x)),\(decimal($0.y))" }
            .joined(separator: " ")
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct NetEditLaunchPlan: Equatable {
    let url: URL

    var arguments: [String] {
        if url.lastPathComponent.lowercased().hasSuffix(".net.xml") {
            return ["-s", url.path]
        }
        if url.pathExtension.lowercased() == "sumocfg" {
            return ["--sumocfg-file", url.path]
        }
        return ["--sumocfg-file", url.path]
    }
}

struct VehicleViewportSubscriptionRequest: Equatable {
    let anchorJunctionID: String
    let range: Double
}

enum ViewportSubscriptionPlanner {
    static func request(
        graph: NetGraph,
        indexes: SpatialIndexes?,
        visibleBounds: SIMD4<Float>
    ) -> VehicleViewportSubscriptionRequest? {
        guard graph.junctions.isEmpty == false else { return nil }
        let center = SIMD2(
            (visibleBounds.x + visibleBounds.z) * 0.5,
            (visibleBounds.y + visibleBounds.w) * 0.5
        )
        let candidateIndexes = indexes?.junctions.query(in: visibleBounds).map { Int($0) } ?? []
        let candidates = candidateIndexes.isEmpty ? graph.junctions.indices.map { Int($0) } : candidateIndexes
        guard let bestIndex = candidates.min(by: {
            distanceSquared(graph.junctions[$0].position, center) < distanceSquared(graph.junctions[$1].position, center)
        }) else {
            return nil
        }
        let anchor = graph.junctions[bestIndex]
        let corners = [
            SIMD2<Float>(visibleBounds.x, visibleBounds.y),
            SIMD2<Float>(visibleBounds.x, visibleBounds.w),
            SIMD2<Float>(visibleBounds.z, visibleBounds.y),
            SIMD2<Float>(visibleBounds.z, visibleBounds.w),
        ]
        let farthest = corners
            .map { sqrt(distanceSquared(anchor.position, $0)) }
            .max() ?? 0
        let paddedRange = max(Double(farthest) * 1.15, 50)
        return VehicleViewportSubscriptionRequest(anchorJunctionID: anchor.id, range: paddedRange)
    }

    private static func distanceSquared(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

private final class SUMOConfigNetFileParser: NSObject, XMLParserDelegate {
    struct ParsedConfig {
        let netURL: URL
        let additionalURLs: [URL]
    }

    private let baseURL: URL
    private var netFileValue: String?
    private var additionalFileValues: [String] = []
    private var parseError: Error?

    private init(baseURL: URL) {
        self.baseURL = baseURL
    }

    static func netFileURL(in configURL: URL) throws -> URL {
        try parse(configURL: configURL).netURL
    }

    static func parse(configURL: URL) throws -> ParsedConfig {
        guard let parser = XMLParser(contentsOf: configURL) else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: configURL.path])
        }
        let delegate = SUMOConfigNetFileParser(baseURL: configURL.deletingLastPathComponent())
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw delegate.parseError ?? parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        guard let value = delegate.netFileValue else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: "No <net-file> entry found in \(configURL.lastPathComponent)."])
        }
        let additionalURLs = delegate.additionalFileValues.flatMap { value in
            value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .map { URL(fileURLWithPath: $0, relativeTo: delegate.baseURL).standardizedFileURL }
        }
        return ParsedConfig(
            netURL: URL(fileURLWithPath: value, relativeTo: delegate.baseURL).standardizedFileURL,
            additionalURLs: additionalURLs
        )
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "net-file", let value = attributeDict["value"], netFileValue == nil {
            netFileValue = value
        }
        if elementName == "additional-files", let value = attributeDict["value"] {
            additionalFileValues.append(value)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}
