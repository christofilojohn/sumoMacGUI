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
    @Published var showPolygons = true
    @Published var showPOIs = true
    @Published var showBackground = true
    @Published var showLegend = true
    @Published var backgroundImageURL: URL?
    @Published var backgroundWorldRect = SIMD4<Float>(0, 0, 1, 1)
    @Published var backgroundOpacity: Float = 0.65
    @Published var visualizationPalette = VisualizationPalette()
    @Published var isVisualizationSettingsPresented = false

    private let initialOpenURL: URL?
    private let userDefaults: UserDefaults
    private var didAttemptInitialLoad = false
    private var session: RunningSUMOSession?
    private var playTask: Task<Void, Never>?
    private var viewportSubscriptionTask: Task<Void, Never>?
    private var vehicleUpdateModeTask: Task<Void, Never>?
    private var hoverRouteTask: Task<Void, Never>?
    private var latestViewportBounds: SIMD4<Float>?
    private var spatialIndexes: SpatialIndexes?
    private var lastPlaybackWallTime: TimeInterval?
    private var lastPlaybackSimTime: Double?
    private var vehicleRouteCache: [String: Set<String>] = [:]
    private var vehicleRouteOrderCache: [String: [String]] = [:]

    private static let recentDocumentsKey = "SumoGUIMac.recentDocuments"
    private static let maxRecentDocumentCount = 8
    private static let maxTrackerSampleCount = 240
    private static let maxTrackerValueSampleCount = 2_000

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
        guard let graph, liveState.vehicles.isEmpty == false else { return [:] }
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
            runtimeMessage = "Simulation step failed: \(error.localizedDescription)"
            isPlaying = false
            playTask?.cancel()
            playTask = nil
            resetPlaybackSpeed()
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
                if self.isExternalTraCIAttached {
                    await Task.yield()
                } else {
                    try? await Task.sleep(nanoseconds: self.playbackDelayNanoseconds())
                }
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
