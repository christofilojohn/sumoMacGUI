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

    @Published private(set) var graph: NetGraph?
    @Published private(set) var sourceURL: URL?
    @Published private(set) var loadState: LoadState = .empty
    @Published private(set) var liveState = SimulationState()
    @Published private(set) var runtimeMessage: String?
    @Published private(set) var selectedVehicleID: String?
    @Published var selectedEdgeID: String?
    @Published var isPlaying = false
    @Published var stepDelay: Double = 0.1

    private let initialOpenURL: URL?
    private var didAttemptInitialLoad = false
    private var session: RunningSUMOSession?
    private var playTask: Task<Void, Never>?
    private var viewportSubscriptionTask: Task<Void, Never>?
    private var latestViewportBounds: SIMD4<Float>?
    private var spatialIndexes: SpatialIndexes?

    init(initialOpenURL: URL? = nil) {
        self.initialOpenURL = initialOpenURL
    }

    deinit {
        playTask?.cancel()
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

    var isExternalTraCIAttached: Bool {
        session?.isAttachedToExternalSUMO == true
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
        guard let graph, let edge = selectedEdge else { return [] }
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
        selectedVehicleID = nil
        selectedEdgeID = nil
        latestViewportBounds = nil
        spatialIndexes = nil
        do {
            let resolved = try resolveInputURL(url)
            let parsed = try await Task.detached(priority: .userInitiated) {
                try NetXMLParser.parse(url: resolved.netURL)
            }.value
            graph = parsed
            spatialIndexes = parsed.makeSpatialIndexes()
            sourceURL = url
            loadState = .ready
            if let configURL = resolved.configURL {
                do {
                    let running = try await RunningSUMOSession.start(
                        config: configURL,
                        subscriptionAnchorID: parsed.junctions.first?.id
                    )
                    session = running
                    if let latestViewportBounds {
                        updateVisibleWorldBounds(latestViewportBounds)
                    }
                    runtimeMessage = "Connected to \(running.versionIdentifier)"
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
        selectedVehicleID = nil
        selectedEdgeID = nil
        latestViewportBounds = nil
        spatialIndexes = nil
        do {
            let resolved = try resolveInputURL(url)
            let parsed = try await Task.detached(priority: .userInitiated) {
                try NetXMLParser.parse(url: resolved.netURL)
            }.value
            graph = parsed
            spatialIndexes = parsed.makeSpatialIndexes()
            sourceURL = url
            loadState = .ready

            do {
                let running = try await RunningSUMOSession.attach(
                    host: host,
                    port: port,
                    clientOrder: clientOrder,
                    subscriptionAnchorID: parsed.junctions.first?.id
                )
                session = running
                if let latestViewportBounds {
                    updateVisibleWorldBounds(latestViewportBounds)
                }
                runtimeMessage = "Attached to \(running.versionIdentifier) at \(host):\(port)"
                isPlaying = true
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
            startPlayback()
        } else {
            playTask?.cancel()
            playTask = nil
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
        await stepSimulation()
    }

    func stop() async {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
        if canRunSimulation {
            if isExternalTraCIAttached {
                runtimeMessage = String(format: "Viewer sync paused at t = %.2fs", liveState.simTime)
            } else {
                runtimeMessage = String(format: "Stopped at t = %.2fs", liveState.simTime)
            }
        }
    }

    private func stepSimulation() async {
        guard let session else { return }
        do {
            liveState = try await session.step()
            runtimeMessage = String(format: "t = %.2fs, %d vehicles", liveState.simTime, liveState.vehicles.count)
        } catch {
            runtimeMessage = "Simulation step failed: \(error.localizedDescription)"
            isPlaying = false
            playTask?.cancel()
            playTask = nil
        }
    }

    func updateVisibleWorldBounds(_ bounds: SIMD4<Float>) {
        guard
            let graph,
            let request = ViewportSubscriptionPlanner.request(
                graph: graph,
                indexes: spatialIndexes,
                visibleBounds: bounds
            )
        else {
            latestViewportBounds = bounds
            return
        }
        latestViewportBounds = bounds
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

    func selectEdge(_ id: String?) {
        let nextID = (selectedEdgeID == id) ? nil : id
        setSelectedEdge(nextID)
    }

    func setSelectedEdge(_ id: String?) {
        selectedEdgeID = id
        if id != nil {
            selectVehicle(nil)
        }
    }

    func selectVehicle(_ id: String?) {
        guard selectedVehicleID != id else { return }
        selectedVehicleID = id
        if id != nil {
            selectedEdgeID = nil
        }
        if id == nil {
            liveState.selectedVehicle = nil
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

    private func startPlayback() {
        playTask?.cancel()
        playTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { return }
                await self.stepSimulation()
                if self.isExternalTraCIAttached {
                    await Task.yield()
                } else {
                    let delay = UInt64(max(self.stepDelay, 0.02) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }
        }
    }

    private func shutdownSession() async {
        playTask?.cancel()
        playTask = nil
        viewportSubscriptionTask?.cancel()
        viewportSubscriptionTask = nil
        isPlaying = false
        if let session {
            await session.close()
        }
        session = nil
    }

    private func resolveInputURL(_ url: URL) throws -> (netURL: URL, configURL: URL?) {
        if url.lastPathComponent.hasSuffix(".net.xml") {
            return (url, nil)
        }
        if url.pathExtension == "sumocfg" {
            return (try SUMOConfigNetFileParser.netFileURL(in: url), url)
        }
        return (url, nil)
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
    private let baseURL: URL
    private var netFileValue: String?
    private var parseError: Error?

    private init(baseURL: URL) {
        self.baseURL = baseURL
    }

    static func netFileURL(in configURL: URL) throws -> URL {
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
        return URL(fileURLWithPath: value, relativeTo: delegate.baseURL).standardizedFileURL
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "net-file", let value = attributeDict["value"], netFileValue == nil {
            netFileValue = value
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}
