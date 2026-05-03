import AppKit
import MetalKit
import QuartzCore
import SwiftUI
import SumoKit

struct NetworkView: NSViewRepresentable {
    let graph: NetGraph?
    let simulationState: SimulationState
    let viewport: ViewportState
    let selectedEdgeID: String?
    let selectedVehicleID: String?
    let laneColorMode: LaneColorMode
    let vehicleColorMode: VehicleColorMode
    let screenshotExportRequest: SimulationViewModel.ScreenshotExportRequest?
    let onScreenshotExportCompleted: (UUID, Result<URL, Error>) -> Void
    let onVisibleWorldBoundsChanged: (SIMD4<Float>) -> Void
    let onVehiclePicked: (String?) -> Void
    let onEdgePicked: (String?) -> Void

    func makeNSView(context: Context) -> NetworkMetalView {
        let view = NetworkMetalView()
        view.viewport = viewport
        view.selectedEdgeID = selectedEdgeID
        view.selectedVehicleID = selectedVehicleID
        view.laneColorMode = laneColorMode
        view.vehicleColorMode = vehicleColorMode
        view.onScreenshotExportCompleted = onScreenshotExportCompleted
        view.onVisibleWorldBoundsChanged = onVisibleWorldBoundsChanged
        view.onVehiclePicked = onVehiclePicked
        view.onEdgePicked = onEdgePicked
        view.screenshotExportRequest = screenshotExportRequest
        return view
    }

    func updateNSView(_ nsView: NetworkMetalView, context: Context) {
        nsView.viewport = viewport
        nsView.graph = graph
        nsView.simulationState = simulationState
        nsView.selectedEdgeID = selectedEdgeID
        nsView.selectedVehicleID = selectedVehicleID
        nsView.laneColorMode = laneColorMode
        nsView.vehicleColorMode = vehicleColorMode
        nsView.onScreenshotExportCompleted = onScreenshotExportCompleted
        nsView.onVisibleWorldBoundsChanged = onVisibleWorldBoundsChanged
        nsView.onVehiclePicked = onVehiclePicked
        nsView.onEdgePicked = onEdgePicked
        nsView.screenshotExportRequest = screenshotExportRequest
    }
}

private final class PassthroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class NetworkMetalView: NSView, MTKViewDelegate {
    private let metalView = PassthroughMTKView()
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var junctionPipeline: MTLRenderPipelineState?
    private var lanePipeline: MTLRenderPipelineState?
    private var vehiclePipeline: MTLRenderPipelineState?
    private var junctionVertexBuffer: MTLBuffer?
    private var junctionVertexCount = 0
    private var laneSegmentBuffer: MTLBuffer?
    private var laneSegmentCount = 0
    private var vehicleInstanceBuffer: MTLBuffer?
    private var vehicleInstanceCount = 0
    private var lastDragLocation: CGPoint?
    private var mouseDownLocation: CGPoint?
    private var didDragBeyondClickSlop = false
    private var lastReportedVisibleBounds: SIMD4<Float>?
    private var vehicleAnimationTimer: Timer?
    private var vehicleAnimationStartTime: TimeInterval = 0
    private var vehicleAnimationDuration: TimeInterval = 0.14
    private var vehicleAnimationSource: [String: VehicleRenderSample] = [:]
    private var vehicleAnimationTarget: [String: VehicleRenderSample] = [:]
    private var magnifyEventMonitor: Any?
    private var handledScreenshotRequestID: UUID?
    var onScreenshotExportCompleted: ((UUID, Result<URL, Error>) -> Void)?
    var onVisibleWorldBoundsChanged: ((SIMD4<Float>) -> Void)?
    var onVehiclePicked: ((String?) -> Void)?
    var onEdgePicked: ((String?) -> Void)?

    var graph: NetGraph? {
        didSet {
            if graph !== oldValue {
                viewport?.requestFit()
                rebuildJunctionBuffer()
                rebuildLaneBuffer()
            }
            rebuildPaths()
        }
    }

    var simulationState = SimulationState() {
        didSet {
            beginVehicleAnimation(to: simulationState.vehicles)
        }
    }

    var selectedEdgeID: String? {
        didSet {
            guard selectedEdgeID != oldValue else { return }
            rebuildLaneBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var selectedVehicleID: String? {
        didSet {
            guard selectedVehicleID != oldValue else { return }
            updateVehicleBuffer(samples: currentVehicleSamplesForDisplay())
        }
    }

    var laneColorMode: LaneColorMode = .speedLimit {
        didSet {
            guard laneColorMode != oldValue else { return }
            rebuildLaneBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var vehicleColorMode: VehicleColorMode = .speed {
        didSet {
            guard vehicleColorMode != oldValue else { return }
            updateVehicleBuffer(samples: currentVehicleSamplesForDisplay())
        }
    }

    var screenshotExportRequest: SimulationViewModel.ScreenshotExportRequest? {
        didSet {
            guard
                let request = screenshotExportRequest,
                request.id != handledScreenshotRequestID
            else {
                return
            }
            handledScreenshotRequestID = request.id
            exportScreenshot(request)
        }
    }

    var viewport: ViewportState? {
        didSet {
            oldValue?.onChange = nil
            viewport?.onChange = { [weak self] in
                self?.rebuildPaths()
            }
            rebuildPaths()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        vehicleAnimationTimer?.invalidate()
        if let magnifyEventMonitor {
            NSEvent.removeMonitor(magnifyEventMonitor)
        }
    }

    override func layout() {
        super.layout()
        metalView.frame = bounds
        rebuildPaths()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        NSCursor.closedHand.set()
        let location = convert(event.locationInWindow, from: nil)
        lastDragLocation = location
        mouseDownLocation = location
        didDragBeyondClickSlop = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let viewport,
            let transform = currentTransform(),
            let lastDragLocation
        else {
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let screenDelta = CGPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y)
        viewport.pan(worldDelta: transform.worldDelta(forScreenDelta: screenDelta))
        self.lastDragLocation = location
        if let mouseDownLocation, screenDistance(from: mouseDownLocation, to: location) > 3 {
            didDragBeyondClickSlop = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        lastDragLocation = nil
        mouseDownLocation = nil
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.openHand.set()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let viewport, let transform = currentTransform() else {
            super.scrollWheel(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        let zoomModifierActive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        if event.hasPreciseScrollingDeltas, !zoomModifierActive {
            let delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
            viewport.pan(worldDelta: transform.worldDelta(forScreenDelta: delta))
        } else if event.scrollingDeltaY != 0 {
            let anchor = transform.worldPoint(forScreenPoint: location)
            let factor = Float(exp(Double(event.scrollingDeltaY) * 0.008))
            viewport.zoom(by: factor, anchorWorld: anchor)
        }
    }

    override func smartMagnify(with event: NSEvent) {
        guard let viewport, let transform = currentTransform() else {
            super.smartMagnify(with: event)
            return
        }
        let location = convert(event.locationInWindow, from: nil)
        let anchor = transform.worldPoint(forScreenPoint: location)
        viewport.zoom(by: 1.8, anchorWorld: anchor)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, let viewport, let transform = currentTransform() {
            let anchor = transform.worldPoint(forScreenPoint: location)
            let factor: Float = event.modifierFlags.contains(.option) ? 0.55 : 1.8
            viewport.zoom(by: factor, anchorWorld: anchor)
        } else if event.clickCount == 1, !didDragBeyondClickSlop {
            pickObject(at: location)
        }
        lastDragLocation = nil
        mouseDownLocation = nil
        didDragBeyondClickSlop = false
        NSCursor.openHand.set()
    }

    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue?.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        if
            let graph,
            let pipeline = junctionPipeline,
            let junctionVertexBuffer,
            junctionVertexCount > 0,
            bounds.width > 10,
            bounds.height > 10
        {
            let transform = currentTransform(for: graph)
            var uniforms = LaneViewportUniforms(transform: transform, viewSize: bounds.size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(junctionVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaneViewportUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: junctionVertexCount)
        }

        if
            let graph,
            let pipeline = lanePipeline,
            let laneSegmentBuffer,
            laneSegmentCount > 0,
            bounds.width > 10,
            bounds.height > 10
        {
            let transform = currentTransform(for: graph)
            var uniforms = LaneViewportUniforms(transform: transform, viewSize: bounds.size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(laneSegmentBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaneViewportUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: laneSegmentCount)
        }

        if
            let graph,
            let pipeline = vehiclePipeline,
            let vehicleInstanceBuffer,
            vehicleInstanceCount > 0,
            bounds.width > 10,
            bounds.height > 10
        {
            let transform = currentTransform(for: graph)
            var uniforms = LaneViewportUniforms(transform: transform, viewSize: bounds.size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(vehicleInstanceBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaneViewportUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: vehicleInstanceCount)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        rebuildPaths()
    }

    private func setup() {
        wantsLayer = true
        device = MTLCreateSystemDefaultDevice()
        metalView.device = device
        metalView.clearColor = MTLClearColor(red: 0.055, green: 0.058, blue: 0.064, alpha: 1)
        metalView.colorPixelFormat = .bgra8Unorm
        commandQueue = device?.makeCommandQueue()
        junctionPipeline = makeRenderPipeline(
            device: device,
            colorPixelFormat: metalView.colorPixelFormat,
            vertexFunction: "junctionVertex",
            fragmentFunction: "junctionFragment"
        )
        lanePipeline = makeRenderPipeline(
            device: device,
            colorPixelFormat: metalView.colorPixelFormat,
            vertexFunction: "laneVertex",
            fragmentFunction: "laneFragment"
        )
        vehiclePipeline = makeRenderPipeline(
            device: device,
            colorPixelFormat: metalView.colorPixelFormat,
            vertexFunction: "vehicleVertex",
            fragmentFunction: "vehicleFragment"
        )
        metalView.delegate = self
        metalView.framebufferOnly = true
        metalView.enableSetNeedsDisplay = true
        metalView.isPaused = true
        metalView.autoresizingMask = [.width, .height]
        addSubview(metalView)

        let tracking = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        installMagnifyMonitorIfNeeded()
    }

    private func installMagnifyMonitorIfNeeded() {
        guard magnifyEventMonitor == nil, window != nil else { return }
        magnifyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, let targetWindow = self.window, event.window === targetWindow else {
                return event
            }
            let locationInView = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(locationInView),
                  let viewport = self.viewport,
                  let transform = self.currentTransform()
            else {
                return event
            }
            let anchor = transform.worldPoint(forScreenPoint: locationInView)
            let factor = Float(exp(Double(event.magnification) * 3.5))
            viewport.zoom(by: factor, anchorWorld: anchor)
            return nil
        }
    }

    private func rebuildPaths() {
        guard let graph, bounds.width > 10, bounds.height > 10 else {
            return
        }

        let transform = currentTransform(for: graph)
        reportVisibleBounds(transform: transform)
        metalView.setNeedsDisplay(bounds)
    }

    private func exportScreenshot(_ request: SimulationViewModel.ScreenshotExportRequest) {
        do {
            try writePNGSnapshot(to: request.url)
            onScreenshotExportCompleted?(request.id, .success(request.url))
        } catch {
            onScreenshotExportCompleted?(request.id, .failure(error))
        }
    }

    private func writePNGSnapshot(to url: URL) throws {
        guard bounds.width > 1, bounds.height > 1 else {
            throw ScreenshotExportError.emptyView
        }

        layoutSubtreeIfNeeded()
        metalView.draw()

        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            throw ScreenshotExportError.couldNotCreateBitmap
        }
        cacheDisplay(in: bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ScreenshotExportError.couldNotEncodePNG
        }
        try data.write(to: url, options: .atomic)
    }

    private func currentTransform() -> ViewTransform? {
        guard let graph else { return nil }
        return currentTransform(for: graph)
    }

    private func currentTransform(for graph: NetGraph) -> ViewTransform {
        let netBounds = graph.bounds()
        let inset: Float = 28
        if let viewport, !viewport.isConfigured {
            viewport.configureToFit(netBounds: netBounds, viewSize: bounds.size, inset: inset)
        }
        return ViewTransform(
            netBounds: netBounds,
            viewSize: bounds.size,
            inset: inset,
            center: viewport?.center,
            pointsPerWorldUnit: viewport?.pointsPerWorldUnit
        )
    }

    private func rebuildJunctionBuffer() {
        guard let graph, let device else {
            junctionVertexBuffer = nil
            junctionVertexCount = 0
            return
        }

        var vertices: [JunctionRenderVertex] = []
        vertices.reserveCapacity(graph.junctions.count * 3)
        for junction in graph.junctions {
            let shape = graph.junctionShape(junction)
            guard shape.count > 2, let first = shape.first else { continue }
            let color = junctionColor(type: junction.type)
            var previousIndex = shape.index(after: shape.startIndex)
            var nextIndex = shape.index(after: previousIndex)
            while nextIndex < shape.endIndex {
                vertices.append(JunctionRenderVertex(position: first, color: color))
                vertices.append(JunctionRenderVertex(position: shape[previousIndex], color: color))
                vertices.append(JunctionRenderVertex(position: shape[nextIndex], color: color))
                previousIndex = nextIndex
                nextIndex = shape.index(after: nextIndex)
            }
        }

        junctionVertexCount = vertices.count
        guard vertices.isEmpty == false else {
            junctionVertexBuffer = nil
            return
        }
        junctionVertexBuffer = vertices.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
    }

    private func junctionColor(type: String) -> SIMD4<Float> {
        switch type {
        case "traffic_light":
            return SIMD4(0.27, 0.34, 0.42, 1)
        case "dead_end":
            return SIMD4(0.20, 0.22, 0.25, 1)
        default:
            return SIMD4(0.24, 0.27, 0.30, 1)
        }
    }

    private func rebuildLaneBuffer() {
        guard let graph, let device else {
            laneSegmentBuffer = nil
            laneSegmentCount = 0
            return
        }
        var segments: [LaneSegmentInstance] = []
        var selectedSegments: [LaneSegmentInstance] = []
        segments.reserveCapacity(graph.lanes.count * 2)
        for lane in graph.lanes {
            guard lane.edgeIndex >= 0, Int(lane.edgeIndex) < graph.edges.count else {
                continue
            }
            let edge = graph.edges[Int(lane.edgeIndex)]
            guard edge.function != .internalEdge else {
                continue
            }
            let points = graph.laneShape(lane)
            guard points.count > 1 else { continue }
            let isSelected = edge.id == selectedEdgeID
            let color = isSelected ? selectedLaneColor() : laneColor(for: lane, edgeFunction: edge.function)
            let baseWidth = lane.width.isFinite && lane.width > 0 ? lane.width : 3.2
            let width = isSelected ? max(baseWidth * 1.8, baseWidth + 1.8) : baseWidth
            var previous = points[points.startIndex]
            var index = points.index(after: points.startIndex)
            while index < points.endIndex {
                let next = points[index]
                let segment = LaneSegmentInstance(
                    points: SIMD4(previous.x, previous.y, next.x, next.y),
                    style: SIMD4(color.x, color.y, color.z, width)
                )
                if isSelected {
                    selectedSegments.append(segment)
                } else {
                    segments.append(segment)
                }
                previous = next
                index = points.index(after: index)
            }
        }
        segments.append(contentsOf: selectedSegments)
        laneSegmentCount = segments.count
        guard segments.isEmpty == false else {
            laneSegmentBuffer = nil
            return
        }
        laneSegmentBuffer = segments.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
    }

    private func laneColor(for lane: Lane, edgeFunction: EdgeFunction) -> SIMD3<Float> {
        switch laneColorMode {
        case .speedLimit:
            return laneSpeedColor(speed: lane.speed)
        case .laneIndex:
            return laneIndexColor(index: lane.index)
        case .edgeType:
            return edgeTypeColor(edgeFunction)
        case .uniform:
            return SIMD3<Float>(0.58, 0.62, 0.66)
        }
    }

    private func laneSpeedColor(speed: Float) -> SIMD3<Float> {
        let t = max(0, min((speed - 5) / 28, 1))
        let low = SIMD3<Float>(0.76, 0.36, 0.28)
        let mid = SIMD3<Float>(0.86, 0.70, 0.30)
        let high = SIMD3<Float>(0.13, 0.77, 0.76)
        if t < 0.5 {
            return mix(low, mid, t * 2)
        }
        return mix(mid, high, (t - 0.5) * 2)
    }

    private func laneIndexColor(index: Int16) -> SIMD3<Float> {
        let palette = [
            SIMD3<Float>(0.20, 0.68, 0.92),
            SIMD3<Float>(0.86, 0.62, 0.22),
            SIMD3<Float>(0.44, 0.74, 0.32),
            SIMD3<Float>(0.84, 0.40, 0.56),
            SIMD3<Float>(0.62, 0.52, 0.92),
        ]
        let paletteIndex = Int(abs(Int(index))) % palette.count
        return palette[paletteIndex]
    }

    private func edgeTypeColor(_ function: EdgeFunction) -> SIMD3<Float> {
        switch function {
        case .normal:
            return SIMD3<Float>(0.40, 0.66, 0.84)
        case .connector:
            return SIMD3<Float>(0.78, 0.60, 0.30)
        case .crossing:
            return SIMD3<Float>(0.70, 0.46, 0.80)
        case .walkingArea:
            return SIMD3<Float>(0.42, 0.70, 0.46)
        case .internalEdge:
            return SIMD3<Float>(0.32, 0.34, 0.36)
        }
    }

    private func selectedLaneColor() -> SIMD3<Float> {
        SIMD3<Float>(1.00, 0.90, 0.28)
    }

    private func rebuildVehicleBuffer() {
        updateVehicleBuffer(samples: simulationState.vehicles.map(VehicleRenderSample.init(snapshot:)))
    }

    private func beginVehicleAnimation(to snapshots: ContiguousArray<VehicleSnapshot>) {
        let target = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, VehicleRenderSample(snapshot: $0)) })
        guard target.isEmpty == false else {
            vehicleAnimationTimer?.invalidate()
            vehicleAnimationTimer = nil
            vehicleAnimationSource = [:]
            vehicleAnimationTarget = [:]
            updateVehicleBuffer(samples: [])
            return
        }

        let source = currentVehicleSamples()
        vehicleAnimationSource = source.isEmpty ? target : source
        vehicleAnimationTarget = target
        vehicleAnimationStartTime = CACurrentMediaTime()
        updateVehicleBuffer(samples: interpolatedVehicleSamples(progress: 0))

        vehicleAnimationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let progress = self.vehicleAnimationProgress()
            self.updateVehicleBuffer(samples: self.interpolatedVehicleSamples(progress: progress))
            if progress >= 1 {
                timer.invalidate()
                self.vehicleAnimationTimer = nil
                self.vehicleAnimationSource = self.vehicleAnimationTarget
            }
        }
        vehicleAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func currentVehicleSamples() -> [String: VehicleRenderSample] {
        Dictionary(uniqueKeysWithValues: currentVehicleSamplesForDisplay().map { ($0.id, $0) })
    }

    private func currentVehicleSamplesForDisplay() -> [VehicleRenderSample] {
        guard vehicleAnimationTarget.isEmpty == false else {
            return simulationState.vehicles.map(VehicleRenderSample.init(snapshot:))
        }
        return interpolatedVehicleSamples(progress: vehicleAnimationProgress())
    }

    private func vehicleAnimationProgress() -> Float {
        guard vehicleAnimationDuration > 0 else { return 1 }
        let elapsed = CACurrentMediaTime() - vehicleAnimationStartTime
        return Float(max(0, min(elapsed / vehicleAnimationDuration, 1)))
    }

    private func interpolatedVehicleSamples(progress: Float) -> [VehicleRenderSample] {
        let eased = progress * progress * (3 - 2 * progress)
        return vehicleAnimationTarget.values.map { target in
            guard let source = vehicleAnimationSource[target.id] else { return target }
            return source.interpolated(to: target, progress: eased)
        }
    }

    private func updateVehicleBuffer(samples: [VehicleRenderSample]) {
        guard let device, samples.isEmpty == false else {
            vehicleInstanceBuffer = nil
            vehicleInstanceCount = 0
            metalView.setNeedsDisplay(bounds)
            return
        }

        var instances: [VehicleInstance] = []
        instances.reserveCapacity(samples.count)
        for vehicle in samples {
            let color = vehicle.id == selectedVehicleID
                ? selectedVehicleColor()
                : vehicleColor(speed: vehicle.speed, typeID: vehicle.typeID)
            instances.append(VehicleInstance(
                pose: SIMD4(vehicle.position.x, vehicle.position.y, vehicle.angle, vehicle.speed),
                color: SIMD4(color.x, color.y, color.z, 1)
            ))
        }
        vehicleInstanceCount = instances.count
        vehicleInstanceBuffer = instances.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
        metalView.setNeedsDisplay(bounds)
    }

    private func vehicleColor(speed: Float, typeID: UInt32) -> SIMD3<Float> {
        switch vehicleColorMode {
        case .speed:
            return vehicleSpeedColor(speed: speed, typeID: typeID)
        case .type:
            return vehicleTypeColor(typeID: typeID)
        case .uniform:
            return SIMD3<Float>(0.30, 0.72, 0.88)
        }
    }

    private func vehicleSpeedColor(speed: Float, typeID: UInt32) -> SIMD3<Float> {
        let t = max(0, min(speed / 32, 1))
        let slow = SIMD3<Float>(0.95, 0.77, 0.25)
        let fast = SIMD3<Float>(0.30, 0.70, 1.00)
        let base = mix(slow, fast, t)
        let typeTint = Float(typeID & 0xFF) / 255
        return mix(base, SIMD3<Float>(0.95, 0.95, 0.95), typeTint * 0.18)
    }

    private func vehicleTypeColor(typeID: UInt32) -> SIMD3<Float> {
        let r = Float((typeID >> 16) & 0xFF) / 255
        let g = Float((typeID >> 8) & 0xFF) / 255
        let b = Float(typeID & 0xFF) / 255
        return mix(SIMD3<Float>(r, g, b), SIMD3<Float>(0.92, 0.92, 0.92), 0.25)
    }

    private func selectedVehicleColor() -> SIMD3<Float> {
        SIMD3<Float>(1.00, 0.96, 0.42)
    }

    private func nearestVehicleID(at screenLocation: CGPoint) -> String? {
        guard let transform = currentTransform() else { return nil }
        let maxPickDistance: CGFloat = 16
        var bestID: String?
        var bestDistance = maxPickDistance
        for vehicle in currentVehicleSamplesForDisplay() {
            let point = transform.point(vehicle.position)
            let distance = screenDistance(from: screenLocation, to: point)
            if distance <= bestDistance {
                bestID = vehicle.id
                bestDistance = distance
            }
        }
        return bestID
    }

    private func nearestEdgeID(at screenLocation: CGPoint) -> String? {
        guard let graph, let transform = currentTransform() else { return nil }
        var bestID: String?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for lane in graph.lanes {
            guard lane.edgeIndex >= 0, Int(lane.edgeIndex) < graph.edges.count else {
                continue
            }
            let edge = graph.edges[Int(lane.edgeIndex)]
            guard edge.function != .internalEdge else {
                continue
            }
            let points = graph.laneShape(lane)
            guard points.count > 1 else { continue }

            let baseWidth = lane.width.isFinite && lane.width > 0 ? lane.width : 3.2
            let renderedHalfWidth = min(max(CGFloat(baseWidth * transform.scale), 1), 18) * 0.5
            let pickThreshold = max(CGFloat(8), renderedHalfWidth + 4)
            var previous = transform.point(points[points.startIndex])
            var index = points.index(after: points.startIndex)
            while index < points.endIndex {
                let next = transform.point(points[index])
                let distance = screenDistance(from: screenLocation, toSegmentStart: previous, end: next)
                if distance <= pickThreshold, distance < bestDistance {
                    bestID = edge.id
                    bestDistance = distance
                }
                previous = next
                index = points.index(after: index)
            }
        }
        return bestID
    }

    private func pickObject(at location: CGPoint) {
        if let vehicleID = nearestVehicleID(at: location) {
            onVehiclePicked?(vehicleID)
            onEdgePicked?(nil)
            return
        }

        onVehiclePicked?(nil)
        onEdgePicked?(nearestEdgeID(at: location))
    }

    private func reportVisibleBounds(transform: ViewTransform) {
        let visible = transform.visibleWorldBounds(viewSize: bounds.size)
        if let lastReportedVisibleBounds, boundsAreClose(lastReportedVisibleBounds, visible) {
            return
        }
        lastReportedVisibleBounds = visible
        onVisibleWorldBoundsChanged?(visible)
    }

    private func makeRenderPipeline(
        device: MTLDevice?,
        colorPixelFormat: MTLPixelFormat,
        vertexFunction: String,
        fragmentFunction: String
    ) -> MTLRenderPipelineState? {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: laneShaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertexFunction)
            descriptor.fragmentFunction = library.makeFunction(name: fragmentFunction)
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("Failed to create Metal pipeline \(vertexFunction)/\(fragmentFunction): \(error.localizedDescription)")
            return nil
        }
    }
}

private enum ScreenshotExportError: LocalizedError {
    case emptyView
    case couldNotCreateBitmap
    case couldNotEncodePNG

    var errorDescription: String? {
        switch self {
        case .emptyView:
            return "The network view is not visible yet."
        case .couldNotCreateBitmap:
            return "Could not create a bitmap for the current network view."
        case .couldNotEncodePNG:
            return "Could not encode the screenshot as PNG."
        }
    }
}

private func boundsAreClose(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool {
    let tolerance: Float = 1
    return abs(a.x - b.x) < tolerance &&
        abs(a.y - b.y) < tolerance &&
        abs(a.z - b.z) < tolerance &&
        abs(a.w - b.w) < tolerance
}

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}

private func screenDistance(from a: CGPoint, to b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}

private func screenDistance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
    let segmentX = end.x - start.x
    let segmentY = end.y - start.y
    let lengthSquared = segmentX * segmentX + segmentY * segmentY
    guard lengthSquared > 0 else {
        return screenDistance(from: point, to: start)
    }

    let projected = ((point.x - start.x) * segmentX + (point.y - start.y) * segmentY) / lengthSquared
    let clamped = min(max(projected, 0), 1)
    let closest = CGPoint(x: start.x + segmentX * clamped, y: start.y + segmentY * clamped)
    return screenDistance(from: point, to: closest)
}

private struct JunctionRenderVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct LaneSegmentInstance {
    var points: SIMD4<Float>
    var style: SIMD4<Float>
}

private struct VehicleInstance {
    var pose: SIMD4<Float>
    var color: SIMD4<Float>
}

private struct VehicleRenderSample {
    let id: String
    var position: SIMD2<Float>
    var angle: Float
    var speed: Float
    var typeID: UInt32

    init(snapshot: VehicleSnapshot) {
        id = snapshot.id
        position = snapshot.position
        angle = snapshot.angle
        speed = snapshot.speed
        typeID = snapshot.typeID
    }

    func interpolated(to target: VehicleRenderSample, progress: Float) -> VehicleRenderSample {
        let clamped = max(0, min(progress, 1))
        var angleDelta = target.angle - angle
        while angleDelta > 180 { angleDelta -= 360 }
        while angleDelta < -180 { angleDelta += 360 }
        return VehicleRenderSample(
            id: target.id,
            position: position + (target.position - position) * clamped,
            angle: angle + angleDelta * clamped,
            speed: speed + (target.speed - speed) * clamped,
            typeID: target.typeID
        )
    }

    private init(id: String, position: SIMD2<Float>, angle: Float, speed: Float, typeID: UInt32) {
        self.id = id
        self.position = position
        self.angle = angle
        self.speed = speed
        self.typeID = typeID
    }
}

private struct LaneViewportUniforms {
    var camera: SIMD4<Float>
    var viewport: SIMD4<Float>

    init(transform: ViewTransform, viewSize: CGSize) {
        camera = SIMD4(transform.center.x, transform.center.y, transform.scale, 0)
        viewport = SIMD4(Float(viewSize.width), Float(viewSize.height), 0, 0)
    }
}

private struct ViewTransform {
    let scale: Float
    private let offsetX: Float
    private let offsetY: Float
    private let height: Float
    let center: SIMD2<Float>

    init(netBounds: SIMD4<Float>, viewSize: CGSize, inset: Float, center: SIMD2<Float>?, pointsPerWorldUnit: Float?) {
        height = Float(viewSize.height)
        let fittedCenter = SIMD2((netBounds.x + netBounds.z) * 0.5, (netBounds.y + netBounds.w) * 0.5)
        self.center = center ?? fittedCenter
        if let pointsPerWorldUnit {
            scale = pointsPerWorldUnit
        } else {
            let width = max(netBounds.z - netBounds.x, 1)
            let netHeight = max(netBounds.w - netBounds.y, 1)
            let availableWidth = max(Float(viewSize.width) - inset * 2, 1)
            let availableHeight = max(Float(viewSize.height) - inset * 2, 1)
            scale = min(availableWidth / width, availableHeight / netHeight)
        }
        offsetX = Float(viewSize.width) * 0.5
        offsetY = Float(viewSize.height) * 0.5
    }

    func point(_ point: SIMD2<Float>) -> CGPoint {
        let x = offsetX + (point.x - center.x) * scale
        let y = height - (offsetY + (point.y - center.y) * scale)
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    func worldPoint(forScreenPoint point: CGPoint) -> SIMD2<Float> {
        let x = (Float(point.x) - offsetX) / scale + center.x
        let y = ((height - Float(point.y)) - offsetY) / scale + center.y
        return SIMD2(x, y)
    }

    func worldDelta(forScreenDelta delta: CGPoint) -> SIMD2<Float> {
        SIMD2(-Float(delta.x) / scale, Float(delta.y) / scale)
    }

    func visibleWorldBounds(viewSize: CGSize) -> SIMD4<Float> {
        let points = [
            worldPoint(forScreenPoint: CGPoint(x: 0, y: 0)),
            worldPoint(forScreenPoint: CGPoint(x: viewSize.width, y: 0)),
            worldPoint(forScreenPoint: CGPoint(x: 0, y: viewSize.height)),
            worldPoint(forScreenPoint: CGPoint(x: viewSize.width, y: viewSize.height)),
        ]
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        return SIMD4(
            xs.min() ?? 0,
            ys.min() ?? 0,
            xs.max() ?? 0,
            ys.max() ?? 0
        )
    }
}

private let laneShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct JunctionRenderVertex {
    packed_float2 position;
    float4 color;
};

struct LaneSegmentInstance {
    float4 points;
    float4 style;
};

struct VehicleInstance {
    float4 pose;
    float4 color;
};

struct LaneViewportUniforms {
    float4 camera;
    float4 viewport;
};

struct LaneVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex LaneVertexOut junctionVertex(
    uint vertexID [[vertex_id]],
    const device JunctionRenderVertex *vertices [[buffer(0)]],
    constant LaneViewportUniforms &uniforms [[buffer(1)]]
) {
    const JunctionRenderVertex junction = vertices[vertexID];
    const float2 world = float2(junction.position);
    const float2 center = uniforms.camera.xy;
    const float scale = uniforms.camera.z;
    const float2 size = uniforms.viewport.xy;
    const float2 screen = float2(
        size.x * 0.5 + (world.x - center.x) * scale,
        size.y * 0.5 - (world.y - center.y) * scale
    );

    LaneVertexOut out;
    out.position = float4(
        (screen.x / size.x) * 2.0 - 1.0,
        1.0 - (screen.y / size.y) * 2.0,
        0.0,
        1.0
    );
    out.color = junction.color;
    return out;
}

fragment float4 junctionFragment(LaneVertexOut in [[stage_in]]) {
    return in.color;
}

vertex LaneVertexOut laneVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device LaneSegmentInstance *segments [[buffer(0)]],
    constant LaneViewportUniforms &uniforms [[buffer(1)]]
) {
    const LaneSegmentInstance segment = segments[instanceID];
    const float2 center = uniforms.camera.xy;
    const float scale = uniforms.camera.z;
    const float2 size = uniforms.viewport.xy;
    const float2 worldStart = segment.points.xy;
    const float2 worldEnd = segment.points.zw;
    const float2 screenStart = float2(
        size.x * 0.5 + (worldStart.x - center.x) * scale,
        size.y * 0.5 - (worldStart.y - center.y) * scale
    );
    const float2 screenEnd = float2(
        size.x * 0.5 + (worldEnd.x - center.x) * scale,
        size.y * 0.5 - (worldEnd.y - center.y) * scale
    );
    const float2 direction = screenEnd - screenStart;
    const float segmentLength = max(length(direction), 0.0001);
    const float2 normal = float2(-direction.y, direction.x) / segmentLength;
    const float halfWidth = clamp(segment.style.w * scale, 1.0, 18.0) * 0.5;

    float2 screen;
    switch (vertexID) {
    case 0:
        screen = screenStart - normal * halfWidth;
        break;
    case 1:
        screen = screenStart + normal * halfWidth;
        break;
    case 2:
        screen = screenEnd - normal * halfWidth;
        break;
    case 3:
        screen = screenEnd - normal * halfWidth;
        break;
    case 4:
        screen = screenStart + normal * halfWidth;
        break;
    default:
        screen = screenEnd + normal * halfWidth;
        break;
    }

    LaneVertexOut out;
    out.position = float4(
        (screen.x / size.x) * 2.0 - 1.0,
        1.0 - (screen.y / size.y) * 2.0,
        0.0,
        1.0
    );
    out.color = float4(segment.style.xyz, 1.0);
    return out;
}

fragment float4 laneFragment(LaneVertexOut in [[stage_in]]) {
    return in.color;
}

struct VehicleVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VehicleVertexOut vehicleVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device VehicleInstance *vehicles [[buffer(0)]],
    constant LaneViewportUniforms &uniforms [[buffer(1)]]
) {
    const VehicleInstance vehicle = vehicles[instanceID];
    const float2 center = uniforms.camera.xy;
    const float scale = uniforms.camera.z;
    const float2 size = uniforms.viewport.xy;
    const float2 world = vehicle.pose.xy;
    const float angle = (90.0 - vehicle.pose.z) * 0.01745329252;
    const float speed = vehicle.pose.w;
    const float2 forward = float2(cos(angle), sin(angle));
    const float2 right = float2(-forward.y, forward.x);
    const float length = clamp(10.0 + speed * 0.18, 8.0, 18.0);
    const float width = clamp(length * 0.48, 4.0, 8.0);
    const float2 screenCenter = float2(
        size.x * 0.5 + (world.x - center.x) * scale,
        size.y * 0.5 - (world.y - center.y) * scale
    );

    float2 screen;
    switch (vertexID) {
    case 0:
        screen = screenCenter + forward * (length * 0.58);
        break;
    case 1:
        screen = screenCenter - forward * (length * 0.42) - right * (width * 0.5);
        break;
    default:
        screen = screenCenter - forward * (length * 0.42) + right * (width * 0.5);
        break;
    }

    VehicleVertexOut out;
    out.position = float4(
        (screen.x / size.x) * 2.0 - 1.0,
        1.0 - (screen.y / size.y) * 2.0,
        0.0,
        1.0
    );
    out.color = vehicle.color;
    return out;
}

fragment float4 vehicleFragment(VehicleVertexOut in [[stage_in]]) {
    return in.color;
}
"""
