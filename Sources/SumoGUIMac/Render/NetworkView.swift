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
    let selectedEdgeIDs: Set<String>
    let selectedVehicleIDs: Set<String>
    let selectedJunctionIDs: Set<String>
    let selectedRouteEdgeIDs: Set<String>
    let hoveredRouteEdgeIDs: Set<String>
    let laneColorMode: LaneColorMode
    let vehicleColorMode: VehicleColorMode
    let junctionColorMode: JunctionColorMode
    let laneOccupancyByID: [String: Float]
    let junctionLoadByID: [String: Int]
    let showLaneDirectionArrows: Bool
    let showPolygons: Bool
    let showPOIs: Bool
    let backgroundDecal: BackgroundDecal?
    let palette: VisualizationPalette
    let nativeEditTool: NativeNetworkEditTool?
    let nativeEdgeGeometryHandles: [NativeEdgeGeometryHandle]
    let nativeJunctionShapeHandles: [NativeJunctionShapeHandle]
    let screenshotExportRequest: SimulationViewModel.ScreenshotExportRequest?
    let onScreenshotExportCompleted: (UUID, Result<URL, Error>) -> Void
    let onVisibleWorldBoundsChanged: (SIMD4<Float>) -> Void
    let onVehiclePicked: (String?) -> Void
    let onVehicleHovered: (String?) -> Void
    let onEdgePicked: (String?) -> Void
    let onNativeEditClick: (NativeNetworkCanvasClick) -> Void
    let onNativeRubberBandSelection: (NativeNetworkRubberBandSelection) -> Void
    let onNativeJunctionMoved: (String, SIMD2<Float>) -> Void
    let onNativeJunctionMoveEnded: () -> Void
    let onNativeEdgeGeometryPointMoved: (String, Int, SIMD2<Float>) -> Void
    let onNativeEdgeGeometryPointMoveEnded: () -> Void
    let onNativeJunctionShapePointMoved: (String, Int, SIMD2<Float>) -> Void
    let onNativeJunctionShapePointMoveEnded: () -> Void
    let onNativeDelete: () -> Void
    let onNativeCancel: () -> Void

    func makeNSView(context: Context) -> NetworkMetalView {
        let view = NetworkMetalView()
        view.viewport = viewport
        view.selectedEdgeID = selectedEdgeID
        view.selectedVehicleID = selectedVehicleID
        view.selectedEdgeIDs = selectedEdgeIDs
        view.selectedVehicleIDs = selectedVehicleIDs
        view.selectedJunctionIDs = selectedJunctionIDs
        view.selectedRouteEdgeIDs = selectedRouteEdgeIDs
        view.hoveredRouteEdgeIDs = hoveredRouteEdgeIDs
        view.laneColorMode = laneColorMode
        view.vehicleColorMode = vehicleColorMode
        view.junctionColorMode = junctionColorMode
        view.laneOccupancyByID = laneOccupancyByID
        view.junctionLoadByID = junctionLoadByID
        view.showLaneDirectionArrows = showLaneDirectionArrows
        view.showPolygons = showPolygons
        view.showPOIs = showPOIs
        view.backgroundDecal = backgroundDecal
        view.palette = palette
        view.nativeEditTool = nativeEditTool
        view.nativeEdgeGeometryHandles = nativeEdgeGeometryHandles
        view.nativeJunctionShapeHandles = nativeJunctionShapeHandles
        view.onScreenshotExportCompleted = onScreenshotExportCompleted
        view.onVisibleWorldBoundsChanged = onVisibleWorldBoundsChanged
        view.onVehiclePicked = onVehiclePicked
        view.onVehicleHovered = onVehicleHovered
        view.onEdgePicked = onEdgePicked
        view.onNativeEditClick = onNativeEditClick
        view.onNativeRubberBandSelection = onNativeRubberBandSelection
        view.onNativeJunctionMoved = onNativeJunctionMoved
        view.onNativeJunctionMoveEnded = onNativeJunctionMoveEnded
        view.onNativeEdgeGeometryPointMoved = onNativeEdgeGeometryPointMoved
        view.onNativeEdgeGeometryPointMoveEnded = onNativeEdgeGeometryPointMoveEnded
        view.onNativeJunctionShapePointMoved = onNativeJunctionShapePointMoved
        view.onNativeJunctionShapePointMoveEnded = onNativeJunctionShapePointMoveEnded
        view.onNativeDelete = onNativeDelete
        view.onNativeCancel = onNativeCancel
        view.screenshotExportRequest = screenshotExportRequest
        return view
    }

    func updateNSView(_ nsView: NetworkMetalView, context: Context) {
        nsView.viewport = viewport
        let wasNativeEditing = nsView.nativeEditTool != nil
        if nativeEditTool != nil, wasNativeEditing {
            nsView.replaceGraphPreservingViewport(graph)
        } else {
            nsView.graph = graph
        }
        nsView.simulationState = simulationState
        nsView.selectedEdgeID = selectedEdgeID
        nsView.selectedVehicleID = selectedVehicleID
        nsView.selectedEdgeIDs = selectedEdgeIDs
        nsView.selectedVehicleIDs = selectedVehicleIDs
        nsView.selectedJunctionIDs = selectedJunctionIDs
        nsView.selectedRouteEdgeIDs = selectedRouteEdgeIDs
        nsView.hoveredRouteEdgeIDs = hoveredRouteEdgeIDs
        nsView.laneColorMode = laneColorMode
        nsView.vehicleColorMode = vehicleColorMode
        nsView.junctionColorMode = junctionColorMode
        nsView.laneOccupancyByID = laneOccupancyByID
        nsView.junctionLoadByID = junctionLoadByID
        nsView.showLaneDirectionArrows = showLaneDirectionArrows
        nsView.showPolygons = showPolygons
        nsView.showPOIs = showPOIs
        nsView.backgroundDecal = backgroundDecal
        nsView.palette = palette
        nsView.nativeEditTool = nativeEditTool
        nsView.nativeEdgeGeometryHandles = nativeEdgeGeometryHandles
        nsView.nativeJunctionShapeHandles = nativeJunctionShapeHandles
        nsView.onScreenshotExportCompleted = onScreenshotExportCompleted
        nsView.onVisibleWorldBoundsChanged = onVisibleWorldBoundsChanged
        nsView.onVehiclePicked = onVehiclePicked
        nsView.onVehicleHovered = onVehicleHovered
        nsView.onEdgePicked = onEdgePicked
        nsView.onNativeEditClick = onNativeEditClick
        nsView.onNativeRubberBandSelection = onNativeRubberBandSelection
        nsView.onNativeJunctionMoved = onNativeJunctionMoved
        nsView.onNativeJunctionMoveEnded = onNativeJunctionMoveEnded
        nsView.onNativeEdgeGeometryPointMoved = onNativeEdgeGeometryPointMoved
        nsView.onNativeEdgeGeometryPointMoveEnded = onNativeEdgeGeometryPointMoveEnded
        nsView.onNativeJunctionShapePointMoved = onNativeJunctionShapePointMoved
        nsView.onNativeJunctionShapePointMoveEnded = onNativeJunctionShapePointMoveEnded
        nsView.onNativeDelete = onNativeDelete
        nsView.onNativeCancel = onNativeCancel
        nsView.screenshotExportRequest = screenshotExportRequest
    }
}

private final class PassthroughMTKView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class RubberBandOverlayView: NSView {
    var rubberBandRect: CGRect? {
        didSet {
            needsDisplay = true
        }
    }

    var handlePoints: [CGPoint] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for point in handlePoints {
            let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
            let path = NSBezierPath(ovalIn: rect)
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
        guard let rect = rubberBandRect, rect.width > 1, rect.height > 1 else { return }
        let path = NSBezierPath(rect: rect)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.78).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

final class NetworkMetalView: NSView, MTKViewDelegate {
    private let metalView = PassthroughMTKView()
    private let rubberBandOverlayView = RubberBandOverlayView()
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var backgroundPipeline: MTLRenderPipelineState?
    private var junctionPipeline: MTLRenderPipelineState?
    private var lanePipeline: MTLRenderPipelineState?
    private var laneArrowPipeline: MTLRenderPipelineState?
    private var vehiclePipeline: MTLRenderPipelineState?
    private var backgroundTexture: MTLTexture?
    private var backgroundVertexBuffer: MTLBuffer?
    private var backgroundVertexCount = 0
    private var polygonVertexBuffer: MTLBuffer?
    private var polygonVertexCount = 0
    private var poiVertexBuffer: MTLBuffer?
    private var poiVertexCount = 0
    private var junctionVertexBuffer: MTLBuffer?
    private var junctionVertexCount = 0
    private var laneSegmentBuffer: MTLBuffer?
    private var laneSegmentCount = 0
    private var laneArrowBuffer: MTLBuffer?
    private var laneArrowCount = 0
    private var lastLaneLODScale: Float?
    private var vehicleInstanceBuffer: MTLBuffer?
    private var vehicleInstanceCount = 0
    private var vehicleInstanceCapacity = 0
    private var lastVehicleLODScale: Float?
    private var lastDragLocation: CGPoint?
    private var mouseDownLocation: CGPoint?
    private var didDragBeyondClickSlop = false
    private var nativeDragJunctionID: String?
    private var nativeDragEdgeGeometryHandle: NativeEdgeGeometryHandle?
    private var nativeDragJunctionShapeHandle: NativeJunctionShapeHandle?
    private var nativeRubberBandStart: CGPoint?
    private var nativeRubberBandCurrent: CGPoint?
    private var nativeRubberBandExtendsSelection = false
    private var lastReportedVisibleBounds: SIMD4<Float>?
    private var vehicleAnimationTimer: Timer?
    private var vehicleAnimationStartTime: TimeInterval = 0
    private var vehicleAnimationDuration: TimeInterval = 0.14
    private var vehicleAnimationSource: [String: VehicleRenderSample] = [:]
    private var vehicleAnimationTarget: [String: VehicleRenderSample] = [:]
    private var magnifyEventMonitor: Any?
    private var preservesViewportForGraphReplacement = false
    private var handledScreenshotRequestID: UUID?
    private var lastHoveredVehicleID: String?
    var onScreenshotExportCompleted: ((UUID, Result<URL, Error>) -> Void)?
    var onVisibleWorldBoundsChanged: ((SIMD4<Float>) -> Void)?
    var onVehiclePicked: ((String?) -> Void)?
    var onVehicleHovered: ((String?) -> Void)?
    var onEdgePicked: ((String?) -> Void)?
    var onNativeEditClick: ((NativeNetworkCanvasClick) -> Void)?
    var onNativeRubberBandSelection: ((NativeNetworkRubberBandSelection) -> Void)?
    var onNativeJunctionMoved: ((String, SIMD2<Float>) -> Void)?
    var onNativeJunctionMoveEnded: (() -> Void)?
    var onNativeEdgeGeometryPointMoved: ((String, Int, SIMD2<Float>) -> Void)?
    var onNativeEdgeGeometryPointMoveEnded: (() -> Void)?
    var onNativeJunctionShapePointMoved: ((String, Int, SIMD2<Float>) -> Void)?
    var onNativeJunctionShapePointMoveEnded: (() -> Void)?
    var onNativeDelete: (() -> Void)?
    var onNativeCancel: (() -> Void)?
    var nativeEdgeGeometryHandles: [NativeEdgeGeometryHandle] = [] {
        didSet {
            guard nativeEdgeGeometryHandles != oldValue else { return }
            updateNativeHandleOverlay()
        }
    }
    var nativeJunctionShapeHandles: [NativeJunctionShapeHandle] = [] {
        didSet {
            guard nativeJunctionShapeHandles != oldValue else { return }
            updateNativeHandleOverlay()
        }
    }
    var nativeEditTool: NativeNetworkEditTool? {
        didSet {
            guard nativeEditTool != oldValue else { return }
            updateCursorForCurrentMode()
            updateNativeHandleOverlay()
        }
    }

    var graph: NetGraph? {
        didSet {
            if graph !== oldValue {
                if !preservesViewportForGraphReplacement {
                    viewport?.requestFit()
                }
                lastLaneLODScale = nil
                lastVehicleLODScale = nil
                rebuildBackgroundBuffer()
                rebuildPolygonBuffer()
                rebuildPOIBuffer()
                rebuildJunctionBuffer()
                rebuildLaneBuffer()
            }
            rebuildPaths()
        }
    }

    func replaceGraphPreservingViewport(_ graph: NetGraph?) {
        preservesViewportForGraphReplacement = true
        self.graph = graph
        preservesViewportForGraphReplacement = false
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

    var selectedEdgeIDs: Set<String> = [] {
        didSet {
            guard selectedEdgeIDs != oldValue else { return }
            rebuildLaneBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var selectedVehicleIDs: Set<String> = [] {
        didSet {
            guard selectedVehicleIDs != oldValue else { return }
            updateVehicleBuffer(samples: currentVehicleSamplesForDisplay())
        }
    }

    var selectedJunctionIDs: Set<String> = [] {
        didSet {
            guard selectedJunctionIDs != oldValue else { return }
            rebuildJunctionBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var selectedRouteEdgeIDs: Set<String> = [] {
        didSet {
            guard selectedRouteEdgeIDs != oldValue else { return }
            rebuildLaneBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var hoveredRouteEdgeIDs: Set<String> = [] {
        didSet {
            guard hoveredRouteEdgeIDs != oldValue else { return }
            rebuildLaneBuffer()
            metalView.setNeedsDisplay(bounds)
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

    var junctionColorMode: JunctionColorMode = .type {
        didSet {
            guard junctionColorMode != oldValue else { return }
            rebuildJunctionBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var laneOccupancyByID: [String: Float] = [:] {
        didSet {
            guard laneColorMode == .occupancy, laneOccupancyByID != oldValue else { return }
            rebuildLaneBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var junctionLoadByID: [String: Int] = [:] {
        didSet {
            guard junctionColorMode == .load, junctionLoadByID != oldValue else { return }
            rebuildJunctionBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var showLaneDirectionArrows = true {
        didSet {
            guard showLaneDirectionArrows != oldValue else { return }
            rebuildLaneBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var showPolygons = true {
        didSet {
            guard showPolygons != oldValue else { return }
            rebuildPolygonBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var showPOIs = true {
        didSet {
            guard showPOIs != oldValue else { return }
            rebuildPOIBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var backgroundDecal: BackgroundDecal? {
        didSet {
            guard backgroundDecal != oldValue else { return }
            if backgroundDecal?.url != oldValue?.url {
                loadBackgroundTexture()
            }
            rebuildBackgroundBuffer()
            metalView.setNeedsDisplay(bounds)
        }
    }

    var palette = VisualizationPalette() {
        didSet {
            guard palette != oldValue else { return }
            rebuildBackgroundBuffer()
            rebuildPolygonBuffer()
            rebuildPOIBuffer()
            rebuildJunctionBuffer()
            rebuildLaneBuffer()
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
        rubberBandOverlayView.frame = bounds
        rebuildPaths()
    }

    private func rendererLocation(for event: NSEvent) -> CGPoint {
        let viewLocation = convert(event.locationInWindow, from: nil)
        return RendererCoordinateSpace.rendererLocation(
            forViewLocation: viewLocation,
            boundsHeight: bounds.height,
            isFlipped: isFlipped
        )
    }

    private func overlayRect(fromRendererStart start: CGPoint, toRendererEnd end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func normalizedWorldBounds(from start: SIMD2<Float>, to end: SIMD2<Float>) -> SIMD4<Float> {
        SIMD4(
            min(start.x, end.x),
            min(start.y, end.y),
            max(start.x, end.x),
            max(start.y, end.y)
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if nativeEditTool == nil {
            NSCursor.closedHand.set()
        }
        let location = rendererLocation(for: event)
        lastDragLocation = location
        mouseDownLocation = location
        didDragBeyondClickSlop = false
        if nativeEditTool == .select {
            nativeDragJunctionShapeHandle = nearestNativeJunctionShapeHandle(at: location)
            nativeDragEdgeGeometryHandle = nativeDragJunctionShapeHandle == nil ? nearestNativeEdgeGeometryHandle(at: location) : nil
            nativeDragJunctionID = nativeDragJunctionShapeHandle == nil && nativeDragEdgeGeometryHandle == nil
                ? nearestJunctionID(at: location)
                : nil
            if nativeDragJunctionShapeHandle == nil, nativeDragEdgeGeometryHandle == nil, nativeDragJunctionID == nil {
                nativeRubberBandStart = location
                nativeRubberBandCurrent = nil
                nativeRubberBandExtendsSelection = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
            } else {
                nativeRubberBandStart = nil
                nativeRubberBandCurrent = nil
                nativeRubberBandExtendsSelection = false
            }
        } else {
            nativeDragJunctionID = nil
            nativeDragEdgeGeometryHandle = nil
            nativeDragJunctionShapeHandle = nil
            nativeRubberBandStart = nil
            nativeRubberBandCurrent = nil
            nativeRubberBandExtendsSelection = false
        }
        rubberBandOverlayView.rubberBandRect = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard
            let viewport,
            let transform = currentTransform(),
            let lastDragLocation
        else {
            return
        }
        let location = rendererLocation(for: event)
        if let nativeDragJunctionID {
            onNativeJunctionMoved?(nativeDragJunctionID, transform.worldPoint(forScreenPoint: location))
            self.lastDragLocation = location
            if let mouseDownLocation, screenDistance(from: mouseDownLocation, to: location) > 3 {
                didDragBeyondClickSlop = true
                updateHoveredVehicle(nil)
            }
            return
        }
        if let nativeDragJunctionShapeHandle {
            onNativeJunctionShapePointMoved?(
                nativeDragJunctionShapeHandle.junctionID,
                nativeDragJunctionShapeHandle.pointIndex,
                transform.worldPoint(forScreenPoint: location)
            )
            self.lastDragLocation = location
            if let mouseDownLocation, screenDistance(from: mouseDownLocation, to: location) > 3 {
                didDragBeyondClickSlop = true
                updateHoveredVehicle(nil)
            }
            return
        }
        if let nativeDragEdgeGeometryHandle {
            onNativeEdgeGeometryPointMoved?(
                nativeDragEdgeGeometryHandle.edgeID,
                nativeDragEdgeGeometryHandle.pointIndex,
                transform.worldPoint(forScreenPoint: location)
            )
            self.lastDragLocation = location
            if let mouseDownLocation, screenDistance(from: mouseDownLocation, to: location) > 3 {
                didDragBeyondClickSlop = true
                updateHoveredVehicle(nil)
            }
            return
        }
        if let nativeRubberBandStart, nativeEditTool == .select, event.modifierFlags.contains(.option) == false {
            nativeRubberBandCurrent = location
            self.lastDragLocation = location
            if screenDistance(from: nativeRubberBandStart, to: location) > 3 {
                didDragBeyondClickSlop = true
                rubberBandOverlayView.rubberBandRect = overlayRect(fromRendererStart: nativeRubberBandStart, toRendererEnd: location)
                updateHoveredVehicle(nil)
            }
            return
        }
        let screenDelta = CGPoint(x: location.x - lastDragLocation.x, y: location.y - lastDragLocation.y)
        viewport.pan(worldDelta: transform.worldDelta(forScreenDelta: screenDelta))
        self.lastDragLocation = location
        if let mouseDownLocation, screenDistance(from: mouseDownLocation, to: location) > 3 {
            didDragBeyondClickSlop = true
            updateHoveredVehicle(nil)
        }
    }

    override func mouseExited(with event: NSEvent) {
        if nativeDragJunctionID != nil {
            onNativeJunctionMoveEnded?()
        }
        if nativeDragEdgeGeometryHandle != nil {
            onNativeEdgeGeometryPointMoveEnded?()
        }
        if nativeDragJunctionShapeHandle != nil {
            onNativeJunctionShapePointMoveEnded?()
        }
        lastDragLocation = nil
        mouseDownLocation = nil
        nativeDragJunctionID = nil
        nativeDragEdgeGeometryHandle = nil
        nativeDragJunctionShapeHandle = nil
        nativeRubberBandStart = nil
        nativeRubberBandCurrent = nil
        nativeRubberBandExtendsSelection = false
        rubberBandOverlayView.rubberBandRect = nil
        updateHoveredVehicle(nil)
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursorForCurrentMode()
        let location = rendererLocation(for: event)
        updateHoveredVehicle(nearestVehicleID(at: location))
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursorForCurrentMode()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let viewport, let transform = currentTransform() else {
            super.scrollWheel(with: event)
            return
        }

        let location = rendererLocation(for: event)
        let zoomModifierActive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option)
        updateHoveredVehicle(nil)
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
        let location = rendererLocation(for: event)
        let anchor = transform.worldPoint(forScreenPoint: location)
        viewport.zoom(by: 1.8, anchorWorld: anchor)
    }

    override func mouseUp(with event: NSEvent) {
        let location = rendererLocation(for: event)
        if let nativeRubberBandStart,
           let nativeRubberBandCurrent,
           didDragBeyondClickSlop,
           let transform = currentTransform()
        {
            let startWorld = transform.worldPoint(forScreenPoint: nativeRubberBandStart)
            let endWorld = transform.worldPoint(forScreenPoint: nativeRubberBandCurrent)
            onNativeRubberBandSelection?(NativeNetworkRubberBandSelection(
                worldBounds: normalizedWorldBounds(from: startWorld, to: endWorld),
                extendsSelection: nativeRubberBandExtendsSelection
            ))
        } else if event.clickCount == 2, let viewport, let transform = currentTransform() {
            let anchor = transform.worldPoint(forScreenPoint: location)
            let factor: Float = event.modifierFlags.contains(.option) ? 0.55 : 1.8
            viewport.zoom(by: factor, anchorWorld: anchor)
        } else if event.clickCount == 1, !didDragBeyondClickSlop {
            if handleNativeEditClick(at: location, event: event) == false {
                pickObject(at: location)
            }
        }
        updateHoveredVehicle(nearestVehicleID(at: location))
        if nativeDragJunctionID != nil {
            onNativeJunctionMoveEnded?()
        }
        if nativeDragEdgeGeometryHandle != nil {
            onNativeEdgeGeometryPointMoveEnded?()
        }
        if nativeDragJunctionShapeHandle != nil {
            onNativeJunctionShapePointMoveEnded?()
        }
        lastDragLocation = nil
        mouseDownLocation = nil
        nativeDragJunctionID = nil
        nativeDragEdgeGeometryHandle = nil
        nativeDragJunctionShapeHandle = nil
        nativeRubberBandStart = nil
        nativeRubberBandCurrent = nil
        nativeRubberBandExtendsSelection = false
        rubberBandOverlayView.rubberBandRect = nil
        didDragBeyondClickSlop = false
        updateCursorForCurrentMode()
    }

    override func keyDown(with event: NSEvent) {
        guard nativeEditTool != nil else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 51, 117:
            onNativeDelete?()
        case 53:
            onNativeCancel?()
        default:
            super.keyDown(with: event)
        }
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
            let pipeline = backgroundPipeline,
            let backgroundTexture,
            let backgroundVertexBuffer,
            backgroundVertexCount > 0,
            bounds.width > 10,
            bounds.height > 10
        {
            let transform = currentTransform(for: graph)
            var uniforms = LaneViewportUniforms(transform: transform, viewSize: bounds.size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(backgroundVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaneViewportUniforms>.stride, index: 1)
            encoder.setFragmentTexture(backgroundTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: backgroundVertexCount)
        }

        if
            let graph,
            let pipeline = junctionPipeline,
            let polygonVertexBuffer,
            polygonVertexCount > 0,
            bounds.width > 10,
            bounds.height > 10
        {
            let transform = currentTransform(for: graph)
            var uniforms = LaneViewportUniforms(transform: transform, viewSize: bounds.size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(polygonVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaneViewportUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: polygonVertexCount)
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
            let pipeline = junctionPipeline,
            let poiVertexBuffer,
            poiVertexCount > 0,
            bounds.width > 10,
            bounds.height > 10
        {
            let transform = currentTransform(for: graph)
            var uniforms = LaneViewportUniforms(transform: transform, viewSize: bounds.size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(poiVertexBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaneViewportUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: poiVertexCount)
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
            let pipeline = laneArrowPipeline,
            let laneArrowBuffer,
            laneArrowCount > 0,
            bounds.width > 10,
            bounds.height > 10
        {
            let transform = currentTransform(for: graph)
            var uniforms = LaneViewportUniforms(transform: transform, viewSize: bounds.size)
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBuffer(laneArrowBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<LaneViewportUniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3, instanceCount: laneArrowCount)
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
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 9, instanceCount: vehicleInstanceCount)
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
        backgroundPipeline = makeRenderPipeline(
            device: device,
            colorPixelFormat: metalView.colorPixelFormat,
            vertexFunction: "backgroundVertex",
            fragmentFunction: "backgroundFragment"
        )
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
        laneArrowPipeline = makeRenderPipeline(
            device: device,
            colorPixelFormat: metalView.colorPixelFormat,
            vertexFunction: "laneArrowVertex",
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
        rubberBandOverlayView.autoresizingMask = [.width, .height]
        rubberBandOverlayView.wantsLayer = true
        rubberBandOverlayView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(rubberBandOverlayView)

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
            let locationInRenderer = self.rendererLocation(for: event)
            guard self.bounds.contains(locationInView),
                  let viewport = self.viewport,
                  let transform = self.currentTransform()
            else {
                return event
            }
            let anchor = transform.worldPoint(forScreenPoint: locationInRenderer)
            let factor = Float(exp(Double(event.magnification) * 3.5))
            viewport.zoom(by: factor, anchorWorld: anchor)
            return nil
        }
    }

    private func rebuildPaths() {
        guard let graph, bounds.width > 10, bounds.height > 10 else {
            rubberBandOverlayView.handlePoints = []
            return
        }

        let transform = currentTransform(for: graph)
        reportVisibleBounds(transform: transform)
        refreshLODDependentBuffers(transform: transform)
        updateNativeHandleOverlay(transform: transform)
        metalView.setNeedsDisplay(bounds)
    }

    private func updateNativeHandleOverlay(transform: ViewTransform? = nil) {
        guard nativeEditTool == .select else {
            rubberBandOverlayView.handlePoints = []
            return
        }
        guard let transform = transform ?? currentTransform() else {
            rubberBandOverlayView.handlePoints = []
            return
        }
        rubberBandOverlayView.handlePoints =
            nativeJunctionShapeHandles.map { transform.point($0.position) } +
            nativeEdgeGeometryHandles.map { transform.point($0.position) }
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
            pointsPerWorldUnit: viewport?.pointsPerWorldUnit,
            rotationRadians: viewport?.rotationRadians ?? 0
        )
    }

    private func loadBackgroundTexture() {
        guard let device, let url = backgroundDecal?.url else {
            backgroundTexture = nil
            return
        }
        do {
            backgroundTexture = try MTKTextureLoader(device: device).newTexture(
                URL: url,
                options: [
                    MTKTextureLoader.Option.SRGB: false,
                    MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.bottomLeft,
                ]
            )
        } catch {
            backgroundTexture = nil
            NSLog("Failed to load background decal \(url.path): \(error.localizedDescription)")
        }
    }

    private func rebuildBackgroundBuffer() {
        guard let device, let decal = backgroundDecal, backgroundTexture != nil else {
            backgroundVertexBuffer = nil
            backgroundVertexCount = 0
            return
        }
        let rect = decal.worldRect
        let tint = SIMD4(
            palette.backgroundTint.red,
            palette.backgroundTint.green,
            palette.backgroundTint.blue,
            max(0, min(decal.opacity, 1)) * palette.backgroundTint.alpha
        )
        let vertices = [
            BackgroundRenderVertex(position: SIMD2(rect.x, rect.y), texCoord: SIMD2(0, 0), tint: tint),
            BackgroundRenderVertex(position: SIMD2(rect.z, rect.y), texCoord: SIMD2(1, 0), tint: tint),
            BackgroundRenderVertex(position: SIMD2(rect.x, rect.w), texCoord: SIMD2(0, 1), tint: tint),
            BackgroundRenderVertex(position: SIMD2(rect.x, rect.w), texCoord: SIMD2(0, 1), tint: tint),
            BackgroundRenderVertex(position: SIMD2(rect.z, rect.y), texCoord: SIMD2(1, 0), tint: tint),
            BackgroundRenderVertex(position: SIMD2(rect.z, rect.w), texCoord: SIMD2(1, 1), tint: tint),
        ]
        backgroundVertexCount = vertices.count
        backgroundVertexBuffer = vertices.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
    }

    private func rebuildPolygonBuffer() {
        guard let graph, let device, showPolygons else {
            polygonVertexBuffer = nil
            polygonVertexCount = 0
            return
        }

        var vertices: [JunctionRenderVertex] = []
        for polygon in graph.polygons.sorted(by: { $0.layer < $1.layer }) {
            let shape = graph.polygonShape(polygon)
            guard shape.count > 2, let first = shape.first else { continue }
            let color = polygonColor(polygon)
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

        polygonVertexCount = vertices.count
        guard vertices.isEmpty == false else {
            polygonVertexBuffer = nil
            return
        }
        polygonVertexBuffer = vertices.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
    }

    private func rebuildPOIBuffer() {
        guard let graph, let device, showPOIs else {
            poiVertexBuffer = nil
            poiVertexCount = 0
            return
        }

        var vertices: [JunctionRenderVertex] = []
        for poi in graph.pois.sorted(by: { $0.layer < $1.layer }) {
            let halfWidth = max(poi.width, 6) * 0.5
            let halfHeight = max(poi.height, 6) * 0.5
            let center = poi.position
            let color = poiColor(poi)
            let bottom = SIMD2(center.x, center.y - halfHeight)
            let right = SIMD2(center.x + halfWidth, center.y)
            let top = SIMD2(center.x, center.y + halfHeight)
            let left = SIMD2(center.x - halfWidth, center.y)
            vertices.append(JunctionRenderVertex(position: bottom, color: color))
            vertices.append(JunctionRenderVertex(position: right, color: color))
            vertices.append(JunctionRenderVertex(position: top, color: color))
            vertices.append(JunctionRenderVertex(position: bottom, color: color))
            vertices.append(JunctionRenderVertex(position: top, color: color))
            vertices.append(JunctionRenderVertex(position: left, color: color))
        }

        poiVertexCount = vertices.count
        guard vertices.isEmpty == false else {
            poiVertexBuffer = nil
            return
        }
        poiVertexBuffer = vertices.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
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
            let color = junctionColor(junction)
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

    private func junctionColor(_ junction: Junction) -> SIMD4<Float> {
        if selectedJunctionIDs.contains(junction.id) {
            let color = selectedLaneColor()
            return SIMD4(color.x, color.y, color.z, 1)
        }
        switch junctionColorMode {
        case .type:
            return junctionTypeColor(type: junction.type)
        case .load:
            let liveLoad = Float(junctionLoadByID[junction.id] ?? junction.incomingLanes.count)
            let t = max(0, min(liveLoad / 12, 1))
            let low = SIMD3<Float>(0.20, 0.32, 0.42)
            let high = SIMD3<Float>(0.95, 0.42, 0.24)
            let color = mix(low, high, t)
            return SIMD4(color.x, color.y, color.z, 1)
        case .uniform:
            return palette.junctionUniform.simd
        }
    }

    private func junctionTypeColor(type: String) -> SIMD4<Float> {
        switch type {
        case "traffic_light":
            return SIMD4(0.27, 0.34, 0.42, 1)
        case "dead_end":
            return SIMD4(0.20, 0.22, 0.25, 1)
        default:
            return SIMD4(0.24, 0.27, 0.30, 1)
        }
    }

    private func polygonColor(_ polygon: PolygonShape) -> SIMD4<Float> {
        let parsed = VisualizationColor(sumoColor: polygon.color).simd
        let fallback = palette.polygonFill.simd
        if polygon.color == SumoColor(red: 96, green: 130, blue: 166, alpha: 180) {
            return fallback
        }
        return SIMD4(parsed.x, parsed.y, parsed.z, polygon.fill ? min(parsed.w, 0.65) : 0.30)
    }

    private func poiColor(_ poi: POI) -> SIMD4<Float> {
        if poi.color == SumoColor(red: 247, green: 192, blue: 74, alpha: 255) {
            return palette.poi.simd
        }
        return VisualizationColor(sumoColor: poi.color).simd
    }

    private func refreshLODDependentBuffers(transform: ViewTransform) {
        if shouldRebuildLODBuffer(previousScale: lastLaneLODScale, nextScale: transform.scale) {
            rebuildLaneBuffer(scale: transform.scale)
        }
        if shouldRebuildLODBuffer(previousScale: lastVehicleLODScale, nextScale: transform.scale) {
            updateVehicleBuffer(samples: currentVehicleSamplesForDisplay(), scale: transform.scale)
        }
    }

    private func shouldRebuildLODBuffer(previousScale: Float?, nextScale: Float) -> Bool {
        guard nextScale.isFinite else { return false }
        guard let previousScale, previousScale.isFinite else { return true }
        return abs(previousScale - nextScale) > Float.ulpOfOne
    }

    private func currentRenderScale() -> Float {
        viewport?.pointsPerWorldUnit ?? 1
    }

    private func rebuildLaneBuffer(scale: Float? = nil) {
        guard let graph, let device else {
            laneSegmentBuffer = nil
            laneSegmentCount = 0
            laneArrowBuffer = nil
            laneArrowCount = 0
            lastLaneLODScale = nil
            return
        }
        let renderScale = scale ?? currentRenderScale()
        var segments: [LaneSegmentInstance] = []
        var hoverSegments: [LaneSegmentInstance] = []
        var routeSegments: [LaneSegmentInstance] = []
        var selectedSegments: [LaneSegmentInstance] = []
        var arrows: [LaneArrowInstance] = []
        var hoverArrows: [LaneArrowInstance] = []
        var routeArrows: [LaneArrowInstance] = []
        var selectedArrows: [LaneArrowInstance] = []
        segments.reserveCapacity(graph.lanes.count * 2)
        if showLaneDirectionArrows {
            arrows.reserveCapacity(graph.lanes.count)
        }
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
            let isSelected = edge.id == selectedEdgeID || selectedEdgeIDs.contains(edge.id)
            let isSelectedRoute = !isSelected && selectedRouteEdgeIDs.contains(edge.id)
            let isHoveredRoute = !isSelected && !isSelectedRoute && hoveredRouteEdgeIDs.contains(edge.id)
            let laneCount = max(edge.laneRange.count, 1)
            let color = laneSegmentColor(
                lane: lane,
                edgeFunction: edge.function,
                laneCount: laneCount,
                isSelected: isSelected,
                isSelectedRoute: isSelectedRoute,
                isHoveredRoute: isHoveredRoute
            )
            let baseWidth = lane.width.isFinite && lane.width > 0 ? lane.width : 3.2
            let width = laneSegmentWidth(
                baseWidth: baseWidth,
                isSelected: isSelected,
                isSelectedRoute: isSelectedRoute,
                isHoveredRoute: isHoveredRoute
            )
            guard let renderWidth = RenderLOD.laneDisplayWorldWidth(
                worldWidth: width,
                scale: renderScale,
                emphasized: isSelected || isSelectedRoute || isHoveredRoute
            ) else {
                continue
            }
            var previous = points[points.startIndex]
            var index = points.index(after: points.startIndex)
            while index < points.endIndex {
                let next = points[index]
                let segment = LaneSegmentInstance(
                    points: SIMD4(previous.x, previous.y, next.x, next.y),
                    style: SIMD4(color.x, color.y, color.z, renderWidth)
                )
                let segmentArrows = showLaneDirectionArrows
                    ? laneArrowInstances(
                        from: previous,
                        to: next,
                        laneScreenWidth: renderWidth * renderScale,
                        renderScale: renderScale,
                        laneColor: color
                    )
                    : []
                if isSelected {
                    selectedSegments.append(segment)
                    selectedArrows.append(contentsOf: segmentArrows)
                } else if isSelectedRoute {
                    routeSegments.append(segment)
                    routeArrows.append(contentsOf: segmentArrows)
                } else if isHoveredRoute {
                    hoverSegments.append(segment)
                    hoverArrows.append(contentsOf: segmentArrows)
                } else {
                    segments.append(segment)
                    arrows.append(contentsOf: segmentArrows)
                }
                previous = next
                index = points.index(after: index)
            }
        }
        lastLaneLODScale = renderScale
        segments.append(contentsOf: hoverSegments)
        segments.append(contentsOf: routeSegments)
        segments.append(contentsOf: selectedSegments)
        arrows.append(contentsOf: hoverArrows)
        arrows.append(contentsOf: routeArrows)
        arrows.append(contentsOf: selectedArrows)
        laneSegmentCount = segments.count
        laneArrowCount = arrows.count
        guard segments.isEmpty == false else {
            laneSegmentBuffer = nil
            laneArrowBuffer = nil
            return
        }
        laneSegmentBuffer = segments.withUnsafeBytes { bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }
        if arrows.isEmpty {
            laneArrowBuffer = nil
        } else {
            laneArrowBuffer = arrows.withUnsafeBytes { bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }
        }
    }

    private func laneArrowInstances(
        from start: SIMD2<Float>,
        to end: SIMD2<Float>,
        laneScreenWidth: Float,
        renderScale: Float,
        laneColor: SIMD3<Float>
    ) -> [LaneArrowInstance] {
        let delta = end - start
        let worldLength = simd_length(delta)
        guard worldLength.isFinite, worldLength > 0.001 else { return [] }

        let segmentScreenLength = worldLength * renderScale
        guard LaneDirectionArrows.shouldRender(
            laneScreenWidth: laneScreenWidth,
            segmentScreenLength: segmentScreenLength,
            scale: renderScale
        ) else {
            return []
        }

        let direction = delta / worldLength
        let metrics = LaneDirectionArrows.arrowScreenMetrics(laneScreenWidth: laneScreenWidth)
        let color = laneDirectionArrowColor(on: laneColor)
        return LaneDirectionArrows.placementFractions(segmentScreenLength: segmentScreenLength).map { fraction in
            let center = start + delta * fraction
            return LaneArrowInstance(
                pose: SIMD4(center.x, center.y, direction.x, direction.y),
                color: color,
                metrics: SIMD4(metrics.x, metrics.y, 0, 0)
            )
        }
    }

    private func laneDirectionArrowColor(on laneColor: SIMD3<Float>) -> SIMD4<Float> {
        let luminance = laneColor.x * 0.2126 + laneColor.y * 0.7152 + laneColor.z * 0.0722
        if luminance > 0.62 {
            return SIMD4(0.05, 0.06, 0.07, 0.78)
        }
        return SIMD4(0.96, 0.98, 1.00, 0.76)
    }

    private func laneSegmentColor(
        lane: Lane,
        edgeFunction: EdgeFunction,
        laneCount: Int,
        isSelected: Bool,
        isSelectedRoute: Bool,
        isHoveredRoute: Bool
    ) -> SIMD3<Float> {
        if isSelected {
            return selectedLaneColor()
        }
        if isSelectedRoute {
            return selectedRouteColor()
        }
        if isHoveredRoute {
            return hoveredRouteColor()
        }
        return laneColor(for: lane, edgeFunction: edgeFunction, laneCount: laneCount)
    }

    private func laneSegmentWidth(
        baseWidth: Float,
        isSelected: Bool,
        isSelectedRoute: Bool,
        isHoveredRoute: Bool
    ) -> Float {
        if isSelected {
            return max(baseWidth * 1.8, baseWidth + 1.8)
        }
        if isSelectedRoute {
            return max(baseWidth * 1.45, baseWidth + 1.2)
        }
        if isHoveredRoute {
            return max(baseWidth * 1.3, baseWidth + 0.8)
        }
        return baseWidth
    }

    private func laneColor(for lane: Lane, edgeFunction: EdgeFunction, laneCount: Int) -> SIMD3<Float> {
        switch laneColorMode {
        case .speedLimit:
            return laneSpeedColor(speed: lane.speed)
        case .laneNumber:
            return laneNumberColor(count: laneCount)
        case .occupancy:
            return laneOccupancyColor(occupancy: laneOccupancyByID[lane.id] ?? 0)
        case .edgeType:
            return edgeTypeColor(edgeFunction)
        case .uniform:
            let color = palette.laneUniform
            return SIMD3(color.red, color.green, color.blue)
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

    private func laneNumberColor(count: Int) -> SIMD3<Float> {
        let palette = [
            SIMD3<Float>(0.20, 0.68, 0.92),
            SIMD3<Float>(0.86, 0.62, 0.22),
            SIMD3<Float>(0.44, 0.74, 0.32),
            SIMD3<Float>(0.84, 0.40, 0.56),
            SIMD3<Float>(0.62, 0.52, 0.92),
        ]
        let paletteIndex = max(count - 1, 0) % palette.count
        return palette[paletteIndex]
    }

    private func laneOccupancyColor(occupancy: Float) -> SIMD3<Float> {
        let t = max(0, min(occupancy / 100, 1))
        let low = SIMD3<Float>(0.22, 0.70, 0.58)
        let mid = SIMD3<Float>(0.90, 0.72, 0.24)
        let high = SIMD3<Float>(0.88, 0.28, 0.24)
        if t < 0.5 {
            return mix(low, mid, t * 2)
        }
        return mix(mid, high, (t - 0.5) * 2)
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

    private func selectedRouteColor() -> SIMD3<Float> {
        SIMD3<Float>(1.00, 0.52, 0.18)
    }

    private func hoveredRouteColor() -> SIMD3<Float> {
        SIMD3<Float>(0.45, 0.76, 1.00)
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

    private func updateVehicleBuffer(samples: [VehicleRenderSample], scale: Float? = nil) {
        let renderScale = scale ?? currentRenderScale()
        lastVehicleLODScale = renderScale
        guard let device else {
            vehicleInstanceBuffer = nil
            vehicleInstanceCount = 0
            vehicleInstanceCapacity = 0
            metalView.setNeedsDisplay(bounds)
            return
        }

        guard samples.isEmpty == false, let size = RenderLOD.vehicleScreenSize(scale: renderScale) else {
            vehicleInstanceCount = 0
            metalView.setNeedsDisplay(bounds)
            return
        }

        var instances: [VehicleInstance] = []
        instances.reserveCapacity(samples.count)
        for vehicle in samples {
            let isSelected = vehicle.id == selectedVehicleID || selectedVehicleIDs.contains(vehicle.id)
            let color = isSelected ? selectedVehicleColor() : vehicleColor(for: vehicle)
            instances.append(VehicleInstance(
                pose: SIMD4(vehicle.position.x, vehicle.position.y, vehicle.angle, vehicle.speed),
                color: SIMD4(color.x, color.y, color.z, 1),
                metrics: SIMD4(size.x, size.y, 0, 0)
            ))
        }
        vehicleInstanceCount = instances.count
        guard instances.isEmpty == false else {
            metalView.setNeedsDisplay(bounds)
            return
        }

        if vehicleInstanceBuffer == nil || vehicleInstanceCapacity < instances.count {
            let nextCapacity = max(instances.count, max(vehicleInstanceCapacity * 2, 256))
            vehicleInstanceBuffer = device.makeBuffer(
                length: nextCapacity * MemoryLayout<VehicleInstance>.stride,
                options: .storageModeShared
            )
            vehicleInstanceCapacity = nextCapacity
        }

        if let vehicleInstanceBuffer {
            instances.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress {
                    vehicleInstanceBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
                }
            }
        }
        metalView.setNeedsDisplay(bounds)
    }

    private func vehicleColor(for vehicle: VehicleRenderSample) -> SIMD3<Float> {
        switch vehicleColorMode {
        case .speed:
            return vehicleSpeedColor(speed: vehicle.speed, typeID: vehicle.typeID)
        case .acceleration:
            return vehicleAccelerationColor(acceleration: vehicle.acceleration ?? 0)
        case .route:
            return vehicleRouteColor(routeID: vehicle.routeID)
        case .type:
            return vehicleTypeColor(typeID: vehicle.typeID)
        case .co2:
            return vehicleCO2Color(co2Emission: vehicle.co2Emission ?? 0)
        case .colorAttribute:
            if let color = vehicle.color {
                let parsed = VisualizationColor(sumoColor: color)
                return SIMD3(parsed.red, parsed.green, parsed.blue)
            }
            return vehicleTypeColor(typeID: vehicle.typeID)
        case .uniform:
            let color = palette.vehicleUniform
            return SIMD3(color.red, color.green, color.blue)
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

    private func vehicleAccelerationColor(acceleration: Float) -> SIMD3<Float> {
        let clamped = max(-4, min(acceleration, 4))
        if clamped < 0 {
            return mix(SIMD3<Float>(0.92, 0.26, 0.22), SIMD3<Float>(0.82, 0.82, 0.82), (clamped + 4) / 4)
        }
        return mix(SIMD3<Float>(0.82, 0.82, 0.82), SIMD3<Float>(0.28, 0.78, 0.38), clamped / 4)
    }

    private func vehicleRouteColor(routeID: String?) -> SIMD3<Float> {
        vehicleTypeColor(typeID: stableHash(routeID ?? "route"))
    }

    private func vehicleCO2Color(co2Emission: Float) -> SIMD3<Float> {
        let t = max(0, min(co2Emission / 2_000, 1))
        return mix(SIMD3<Float>(0.35, 0.78, 0.46), SIMD3<Float>(0.86, 0.30, 0.24), t)
    }

    private func selectedVehicleColor() -> SIMD3<Float> {
        SIMD3<Float>(1.00, 0.96, 0.42)
    }

    private func nearestVehicleID(at screenLocation: CGPoint) -> String? {
        guard let transform = currentTransform() else { return nil }
        guard RenderLOD.vehicleScreenSize(scale: transform.scale) != nil else { return nil }
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
            let isSelected = edge.id == selectedEdgeID || selectedEdgeIDs.contains(edge.id)
            let isSelectedRoute = !isSelected && selectedRouteEdgeIDs.contains(edge.id)
            let isHoveredRoute = !isSelected && !isSelectedRoute && hoveredRouteEdgeIDs.contains(edge.id)
            let width = laneSegmentWidth(
                baseWidth: baseWidth,
                isSelected: isSelected,
                isSelectedRoute: isSelectedRoute,
                isHoveredRoute: isHoveredRoute
            )
            guard let renderWidth = RenderLOD.laneDisplayWorldWidth(
                worldWidth: width,
                scale: transform.scale,
                emphasized: isSelected || isSelectedRoute || isHoveredRoute
            ) else { continue }
            let renderedHalfWidth = min(
                max(CGFloat(renderWidth * transform.scale), CGFloat(RenderLOD.minimumLaneScreenWidth)),
                CGFloat(RenderLOD.maximumLaneScreenWidth)
            ) * 0.5
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

    private func nearestJunctionID(at screenLocation: CGPoint) -> String? {
        guard let graph, let transform = currentTransform() else { return nil }
        let pickThreshold: CGFloat = 14
        var bestID: String?
        var bestDistance = pickThreshold
        for junction in graph.junctions {
            let point = transform.point(junction.position)
            let distance = screenDistance(from: screenLocation, to: point)
            if distance <= bestDistance {
                bestID = junction.id
                bestDistance = distance
            }
        }
        return bestID
    }

    private func nearestNativeEdgeGeometryHandle(at screenLocation: CGPoint) -> NativeEdgeGeometryHandle? {
        guard let transform = currentTransform() else { return nil }
        let pickThreshold: CGFloat = 12
        var bestHandle: NativeEdgeGeometryHandle?
        var bestDistance = pickThreshold
        for handle in nativeEdgeGeometryHandles {
            let point = transform.point(handle.position)
            let distance = screenDistance(from: screenLocation, to: point)
            if distance <= bestDistance {
                bestHandle = handle
                bestDistance = distance
            }
        }
        return bestHandle
    }

    private func nearestNativeJunctionShapeHandle(at screenLocation: CGPoint) -> NativeJunctionShapeHandle? {
        guard let transform = currentTransform() else { return nil }
        let pickThreshold: CGFloat = 12
        var bestHandle: NativeJunctionShapeHandle?
        var bestDistance = pickThreshold
        for handle in nativeJunctionShapeHandles {
            let point = transform.point(handle.position)
            let distance = screenDistance(from: screenLocation, to: point)
            if distance <= bestDistance {
                bestHandle = handle
                bestDistance = distance
            }
        }
        return bestHandle
    }

    private func handleNativeEditClick(at location: CGPoint, event: NSEvent) -> Bool {
        guard nativeEditTool != nil, let transform = currentTransform() else { return false }
        let click = NativeNetworkCanvasClick(
            worldPosition: transform.worldPoint(forScreenPoint: location),
            junctionID: nearestJunctionID(at: location),
            edgeID: nearestEdgeID(at: location),
            extendsSelection: event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        )
        onNativeEditClick?(click)
        return true
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

    private func updateHoveredVehicle(_ vehicleID: String?) {
        guard lastHoveredVehicleID != vehicleID else { return }
        lastHoveredVehicleID = vehicleID
        onVehicleHovered?(vehicleID)
    }

    private func updateCursorForCurrentMode() {
        if nativeEditTool == nil {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
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
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
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

private func stableHash(_ value: String) -> UInt32 {
    var hash: UInt32 = 2166136261
    for byte in value.utf8 {
        hash ^= UInt32(byte)
        hash &*= 16777619
    }
    return hash
}

enum RenderLOD {
    static let minimumLaneScreenWidth: Float = 0.5
    static let maximumLaneScreenWidth: Float = 96
    static let minimumVehicleScreenSize: Float = 2
    static let defaultVehicleLength: Float = 5
    static let defaultVehicleWidth: Float = 2

    static func shouldRenderLane(worldWidth: Float, scale: Float) -> Bool {
        guard worldWidth.isFinite, scale.isFinite, worldWidth > 0, scale > 0 else {
            return false
        }
        return worldWidth * scale >= minimumLaneScreenWidth
    }

    static func laneDisplayWorldWidth(worldWidth: Float, scale: Float, emphasized: Bool = false) -> Float? {
        guard shouldRenderLane(worldWidth: worldWidth, scale: scale) else {
            return nil
        }

        let screenWidth = min(worldWidth * scale, maximumLaneScreenWidth)
        if emphasized {
            return screenWidth / scale
        }

        let separatorGap = min(1, max(0.22, screenWidth * 0.28))
        let displayScreenWidth = max(minimumLaneScreenWidth, screenWidth - separatorGap)
        return displayScreenWidth / scale
    }

    static func vehicleScreenSize(
        scale: Float,
        length: Float = defaultVehicleLength,
        width: Float = defaultVehicleWidth
    ) -> SIMD2<Float>? {
        guard
            scale.isFinite,
            length.isFinite,
            width.isFinite,
            scale > 0,
            length > 0,
            width > 0
        else {
            return nil
        }
        let size = SIMD2(length * scale, width * scale)
        return max(size.x, size.y) >= minimumVehicleScreenSize ? size : nil
    }
}

enum LaneDirectionArrows {
    static let minimumLaneScreenWidth: Float = 2.5
    static let minimumSegmentScreenLength: Float = 34
    static let endpointInsetScreen: Float = 18
    static let preferredScreenSpacing: Float = 112
    static let maximumArrowsPerSegment = 3

    static func shouldRender(laneScreenWidth: Float, segmentScreenLength: Float, scale: Float) -> Bool {
        guard
            laneScreenWidth.isFinite,
            segmentScreenLength.isFinite,
            scale.isFinite,
            laneScreenWidth >= minimumLaneScreenWidth,
            segmentScreenLength >= minimumSegmentScreenLength,
            scale > 0
        else {
            return false
        }
        return true
    }

    static func placementFractions(segmentScreenLength: Float) -> [Float] {
        guard segmentScreenLength.isFinite, segmentScreenLength >= minimumSegmentScreenLength else { return [] }
        let usableLength = max(segmentScreenLength - endpointInsetScreen * 2, 1)
        let arrowCount = min(
            maximumArrowsPerSegment,
            max(1, Int((usableLength / preferredScreenSpacing).rounded()))
        )
        return (0..<arrowCount).map { index in
            let offset = endpointInsetScreen + usableLength * (Float(index) + 0.5) / Float(arrowCount)
            return max(0, min(offset / segmentScreenLength, 1))
        }
    }

    static func arrowScreenMetrics(laneScreenWidth: Float) -> SIMD2<Float> {
        let width = max(6, min(laneScreenWidth * 0.52, 20))
        let length = max(10, min(laneScreenWidth * 0.85, 32))
        return SIMD2(length, width)
    }
}

enum VehicleHeading {
    static func screenRadians(sumoDegrees: Float, viewportRotationRadians: Float) -> Float {
        ((sumoDegrees - 90) * .pi / 180) - viewportRotationRadians
    }

    static func sumoDegrees(from source: SIMD2<Float>, to target: SIMD2<Float>) -> Float? {
        let delta = target - source
        guard simd_length_squared(delta) > 0.0001 else { return nil }
        return normalizedDegrees(atan2(delta.x, delta.y) * 180 / .pi)
    }

    static func interpolatedSUMODegrees(
        from sourceAngle: Float,
        to targetAngle: Float,
        sourcePosition: SIMD2<Float>,
        targetPosition: SIMD2<Float>,
        progress: Float
    ) -> Float {
        let clamped = max(0, min(progress, 1))
        let baseAngle = mixDegrees(sourceAngle, targetAngle, progress: clamped)
        guard let movementAngle = sumoDegrees(from: sourcePosition, to: targetPosition) else {
            return baseAngle
        }

        let midTurnWeight = sin(clamped * .pi)
        return mixDegrees(baseAngle, movementAngle, progress: min(midTurnWeight * 0.65, 0.65))
    }

    static func mixDegrees(_ source: Float, _ target: Float, progress: Float) -> Float {
        let clamped = max(0, min(progress, 1))
        return normalizedDegrees(source + shortestDeltaDegrees(from: source, to: target) * clamped)
    }

    static func shortestDeltaDegrees(from source: Float, to target: Float) -> Float {
        var delta = normalizedDegrees(target) - normalizedDegrees(source)
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        return delta
    }

    private static func normalizedDegrees(_ degrees: Float) -> Float {
        guard degrees.isFinite else { return 0 }
        var normalized = degrees.truncatingRemainder(dividingBy: 360)
        if normalized < 0 {
            normalized += 360
        }
        return normalized
    }
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

private struct BackgroundRenderVertex {
    var position: SIMD2<Float>
    var texCoord: SIMD2<Float>
    var tint: SIMD4<Float>
}

private struct JunctionRenderVertex {
    var position: SIMD2<Float>
    var color: SIMD4<Float>
}

private struct LaneSegmentInstance {
    var points: SIMD4<Float>
    var style: SIMD4<Float>
}

private struct LaneArrowInstance {
    var pose: SIMD4<Float>
    var color: SIMD4<Float>
    var metrics: SIMD4<Float>
}

private struct VehicleInstance {
    var pose: SIMD4<Float>
    var color: SIMD4<Float>
    var metrics: SIMD4<Float>
}

private struct VehicleRenderSample {
    let id: String
    var position: SIMD2<Float>
    var angle: Float
    var speed: Float
    var typeID: UInt32
    var acceleration: Float?
    var co2Emission: Float?
    var routeID: String?
    var color: SumoColor?

    init(snapshot: VehicleSnapshot) {
        id = snapshot.id
        position = snapshot.position
        angle = snapshot.angle
        speed = snapshot.speed
        typeID = snapshot.typeID
        acceleration = snapshot.acceleration
        co2Emission = snapshot.co2Emission
        routeID = snapshot.routeID
        color = snapshot.color
    }

    func interpolated(to target: VehicleRenderSample, progress: Float) -> VehicleRenderSample {
        let clamped = max(0, min(progress, 1))
        return VehicleRenderSample(
            id: target.id,
            position: position + (target.position - position) * clamped,
            angle: VehicleHeading.interpolatedSUMODegrees(
                from: angle,
                to: target.angle,
                sourcePosition: position,
                targetPosition: target.position,
                progress: clamped
            ),
            speed: speed + (target.speed - speed) * clamped,
            typeID: target.typeID,
            acceleration: interpolateOptional(acceleration, target.acceleration, progress: clamped),
            co2Emission: interpolateOptional(co2Emission, target.co2Emission, progress: clamped),
            routeID: target.routeID ?? routeID,
            color: target.color ?? color
        )
    }

    private init(
        id: String,
        position: SIMD2<Float>,
        angle: Float,
        speed: Float,
        typeID: UInt32,
        acceleration: Float?,
        co2Emission: Float?,
        routeID: String?,
        color: SumoColor?
    ) {
        self.id = id
        self.position = position
        self.angle = angle
        self.speed = speed
        self.typeID = typeID
        self.acceleration = acceleration
        self.co2Emission = co2Emission
        self.routeID = routeID
        self.color = color
    }

    private func interpolateOptional(_ source: Float?, _ target: Float?, progress: Float) -> Float? {
        guard let target else { return source }
        guard let source else { return target }
        return source + (target - source) * progress
    }
}

private struct LaneViewportUniforms {
    var camera: SIMD4<Float>
    var viewport: SIMD4<Float>

    init(transform: ViewTransform, viewSize: CGSize) {
        camera = SIMD4(transform.center.x, transform.center.y, transform.scale, transform.rotationRadians)
        viewport = SIMD4(Float(viewSize.width), Float(viewSize.height), 0, 0)
    }
}

enum RendererCoordinateSpace {
    static func rendererLocation(forViewLocation viewLocation: CGPoint, boundsHeight: CGFloat, isFlipped: Bool) -> CGPoint {
        if isFlipped {
            return viewLocation
        }
        return CGPoint(x: viewLocation.x, y: boundsHeight - viewLocation.y)
    }
}

struct ViewTransform {
    let scale: Float
    let rotationRadians: Float
    private let offsetX: Float
    private let offsetY: Float
    private let height: Float
    let center: SIMD2<Float>

    init(
        netBounds: SIMD4<Float>,
        viewSize: CGSize,
        inset: Float,
        center: SIMD2<Float>?,
        pointsPerWorldUnit: Float?,
        rotationRadians: Float
    ) {
        height = Float(viewSize.height)
        let fittedCenter = SIMD2((netBounds.x + netBounds.z) * 0.5, (netBounds.y + netBounds.w) * 0.5)
        self.center = center ?? fittedCenter
        self.rotationRadians = rotationRadians.isFinite ? rotationRadians : 0
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
        let rotated = rotate(point - center)
        let x = offsetX + rotated.x * scale
        let y = height - (offsetY + rotated.y * scale)
        return CGPoint(x: CGFloat(x), y: CGFloat(y))
    }

    func worldPoint(forScreenPoint point: CGPoint) -> SIMD2<Float> {
        let rotated = SIMD2(
            (Float(point.x) - offsetX) / scale,
            ((height - Float(point.y)) - offsetY) / scale
        )
        return center + inverseRotate(rotated)
    }

    func worldDelta(forScreenDelta delta: CGPoint) -> SIMD2<Float> {
        inverseRotate(SIMD2(-Float(delta.x) / scale, Float(delta.y) / scale))
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

    private func rotate(_ vector: SIMD2<Float>) -> SIMD2<Float> {
        let c = cos(rotationRadians)
        let s = sin(rotationRadians)
        return SIMD2(vector.x * c - vector.y * s, vector.x * s + vector.y * c)
    }

    private func inverseRotate(_ vector: SIMD2<Float>) -> SIMD2<Float> {
        let c = cos(rotationRadians)
        let s = sin(rotationRadians)
        return SIMD2(vector.x * c + vector.y * s, -vector.x * s + vector.y * c)
    }
}

private let laneShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct JunctionRenderVertex {
    packed_float2 position;
    float4 color;
};

struct BackgroundRenderVertex {
    packed_float2 position;
    packed_float2 texCoord;
    float4 tint;
};

struct LaneSegmentInstance {
    float4 points;
    float4 style;
};

struct LaneArrowInstance {
    float4 pose;
    float4 color;
    float4 metrics;
};

struct VehicleInstance {
    float4 pose;
    float4 color;
    float4 metrics;
};

struct LaneViewportUniforms {
    float4 camera;
    float4 viewport;
};

struct LaneVertexOut {
    float4 position [[position]];
    float4 color;
};

struct BackgroundVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 tint;
};

float2 worldToScreen(float2 world, constant LaneViewportUniforms &uniforms) {
    const float2 center = uniforms.camera.xy;
    const float scale = uniforms.camera.z;
    const float rotation = uniforms.camera.w;
    const float c = cos(rotation);
    const float s = sin(rotation);
    const float2 delta = world - center;
    const float2 rotated = float2(delta.x * c - delta.y * s, delta.x * s + delta.y * c);
    const float2 size = uniforms.viewport.xy;
    return float2(
        size.x * 0.5 + rotated.x * scale,
        size.y * 0.5 - rotated.y * scale
    );
}

float4 screenToClip(float2 screen, float2 size) {
    return float4(
        (screen.x / size.x) * 2.0 - 1.0,
        1.0 - (screen.y / size.y) * 2.0,
        0.0,
        1.0
    );
}

vertex BackgroundVertexOut backgroundVertex(
    uint vertexID [[vertex_id]],
    const device BackgroundRenderVertex *vertices [[buffer(0)]],
    constant LaneViewportUniforms &uniforms [[buffer(1)]]
) {
    const BackgroundRenderVertex backgroundVertexData = vertices[vertexID];
    const float2 world = float2(backgroundVertexData.position);
    const float2 size = uniforms.viewport.xy;
    const float2 screen = worldToScreen(world, uniforms);

    BackgroundVertexOut out;
    out.position = screenToClip(screen, size);
    out.texCoord = float2(backgroundVertexData.texCoord);
    out.tint = backgroundVertexData.tint;
    return out;
}

fragment float4 backgroundFragment(
    BackgroundVertexOut in [[stage_in]],
    texture2d<float> backgroundTexture [[texture(0)]]
) {
    constexpr sampler textureSampler(address::clamp_to_edge, filter::linear);
    return backgroundTexture.sample(textureSampler, in.texCoord) * in.tint;
}

vertex LaneVertexOut junctionVertex(
    uint vertexID [[vertex_id]],
    const device JunctionRenderVertex *vertices [[buffer(0)]],
    constant LaneViewportUniforms &uniforms [[buffer(1)]]
) {
    const JunctionRenderVertex junction = vertices[vertexID];
    const float2 world = float2(junction.position);
    const float2 size = uniforms.viewport.xy;
    const float2 screen = worldToScreen(world, uniforms);

    LaneVertexOut out;
    out.position = screenToClip(screen, size);
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
    const float scale = uniforms.camera.z;
    const float2 size = uniforms.viewport.xy;
    const float2 worldStart = segment.points.xy;
    const float2 worldEnd = segment.points.zw;
    const float2 screenStart = worldToScreen(worldStart, uniforms);
    const float2 screenEnd = worldToScreen(worldEnd, uniforms);
    const float2 direction = screenEnd - screenStart;
    const float segmentLength = max(length(direction), 0.0001);
    const float2 normal = float2(-direction.y, direction.x) / segmentLength;
    const float halfWidth = clamp(segment.style.w * scale, 0.5, 96.0) * 0.5;

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
    out.position = screenToClip(screen, size);
    out.color = float4(segment.style.xyz, 1.0);
    return out;
}

vertex LaneVertexOut laneArrowVertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device LaneArrowInstance *arrows [[buffer(0)]],
    constant LaneViewportUniforms &uniforms [[buffer(1)]]
) {
    const LaneArrowInstance arrow = arrows[instanceID];
    const float2 size = uniforms.viewport.xy;
    const float2 worldCenter = arrow.pose.xy;
    const float2 screenCenter = worldToScreen(worldCenter, uniforms);
    float2 forward = worldToScreen(worldCenter + arrow.pose.zw, uniforms) - screenCenter;
    const float forwardLength = length(forward);
    forward = forwardLength > 0.0001 ? forward / forwardLength : float2(1.0, 0.0);
    const float2 right = float2(-forward.y, forward.x);
    const float arrowLength = clamp(arrow.metrics.x, 8.0, 22.0);
    const float arrowWidth = clamp(arrow.metrics.y, 5.0, 14.0);

    float2 screen;
    switch (vertexID) {
    case 0:
        screen = screenCenter + forward * (arrowLength * 0.58);
        break;
    case 1:
        screen = screenCenter - forward * (arrowLength * 0.42) - right * (arrowWidth * 0.5);
        break;
    default:
        screen = screenCenter - forward * (arrowLength * 0.42) + right * (arrowWidth * 0.5);
        break;
    }

    LaneVertexOut out;
    out.position = screenToClip(screen, size);
    out.color = arrow.color;
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
    const float2 size = uniforms.viewport.xy;
    const float2 world = vehicle.pose.xy;
    const float angle = (vehicle.pose.z - 90.0) * 0.01745329252 - uniforms.camera.w;
    const float2 forward = float2(cos(angle), sin(angle));
    const float2 right = float2(-forward.y, forward.x);
    const float length = clamp(vehicle.metrics.x, 2.0, 34.0);
    const float width = clamp(vehicle.metrics.y, 1.0, 14.0);
    const float2 screenCenter = worldToScreen(world, uniforms);
    const float2 nose = screenCenter + forward * (length * 0.58);
    const float2 frontRight = screenCenter + forward * (length * 0.14) + right * (width * 0.52);
    const float2 rearRight = screenCenter - forward * (length * 0.44) + right * (width * 0.42);
    const float2 rearLeft = screenCenter - forward * (length * 0.44) - right * (width * 0.42);
    const float2 frontLeft = screenCenter + forward * (length * 0.14) - right * (width * 0.52);

    float2 screen;
    switch (vertexID) {
    case 0:
        screen = nose;
        break;
    case 1:
        screen = frontRight;
        break;
    case 2:
        screen = frontLeft;
        break;
    case 3:
        screen = frontRight;
        break;
    case 4:
        screen = rearRight;
        break;
    case 5:
        screen = rearLeft;
        break;
    case 6:
        screen = frontRight;
        break;
    case 7:
        screen = rearLeft;
        break;
    default:
        screen = frontLeft;
        break;
    }

    VehicleVertexOut out;
    out.position = screenToClip(screen, size);
    out.color = vehicle.color;
    return out;
}

fragment float4 vehicleFragment(VehicleVertexOut in [[stage_in]]) {
    return in.color;
}
"""
