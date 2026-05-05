import Foundation

public struct NetLocation: Sendable {
    public var netOffset: SIMD2<Double>
    public var convBoundary: SIMD4<Double>   // xmin, ymin, xmax, ymax
    public var origBoundary: SIMD4<Double>
    public var projParameter: String
}

public struct LaneShape: Sendable {
    public var points: ContiguousArray<SIMD2<Float>>
}

public struct SumoColor: Sendable, Equatable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

public struct SpatialIndexes: @unchecked Sendable {
    public let lanes: Quadtree<Int32>
    public let edges: Quadtree<Int32>
    public let junctions: Quadtree<Int32>
}

public struct Lane: Sendable {
    public var id: String
    public var edgeIndex: Int32
    public var index: Int16
    public var speed: Float
    public var length: Float
    public var width: Float
    public var allowsAll: Bool
    public var shapeOffset: Int32
    public var shapeCount: Int32
    public var bounds: SIMD4<Float>   // xmin ymin xmax ymax

    public init(
        id: String,
        edgeIndex: Int32,
        index: Int16,
        speed: Float,
        length: Float,
        width: Float,
        allowsAll: Bool,
        shapeOffset: Int32,
        shapeCount: Int32,
        bounds: SIMD4<Float>
    ) {
        self.id = id
        self.edgeIndex = edgeIndex
        self.index = index
        self.speed = speed
        self.length = length
        self.width = width
        self.allowsAll = allowsAll
        self.shapeOffset = shapeOffset
        self.shapeCount = shapeCount
        self.bounds = bounds
    }
}

public struct Edge: Sendable {
    public var id: String
    public var fromJunction: String
    public var toJunction: String
    public var function: EdgeFunction
    public var priority: Int16
    public var laneRange: Range<Int32>
    public var bounds: SIMD4<Float>

    public init(
        id: String,
        fromJunction: String,
        toJunction: String,
        function: EdgeFunction,
        priority: Int16,
        laneRange: Range<Int32>,
        bounds: SIMD4<Float>
    ) {
        self.id = id
        self.fromJunction = fromJunction
        self.toJunction = toJunction
        self.function = function
        self.priority = priority
        self.laneRange = laneRange
        self.bounds = bounds
    }
}

public enum EdgeFunction: UInt8, Sendable {
    case normal = 0
    case internalEdge = 1
    case connector = 2
    case crossing = 3
    case walkingArea = 4
}

public struct Junction: Sendable {
    public var id: String
    public var type: String
    public var position: SIMD2<Float>
    public var shapeOffset: Int32
    public var shapeCount: Int32
    public var bounds: SIMD4<Float>
    public var incomingLanes: [String]
    public var internalLanes: [String]

    public init(
        id: String,
        type: String,
        position: SIMD2<Float>,
        shapeOffset: Int32,
        shapeCount: Int32,
        bounds: SIMD4<Float>,
        incomingLanes: [String],
        internalLanes: [String]
    ) {
        self.id = id
        self.type = type
        self.position = position
        self.shapeOffset = shapeOffset
        self.shapeCount = shapeCount
        self.bounds = bounds
        self.incomingLanes = incomingLanes
        self.internalLanes = internalLanes
    }
}

public struct Connection: Sendable {
    public var fromEdge: String
    public var toEdge: String
    public var fromLane: Int16
    public var toLane: Int16
    public var via: String
    public var trafficLightID: String
    public var linkIndex: Int16
    public var dir: String
    public var state: String
}

public struct TrafficLightLogic: Sendable {
    public var id: String
    public var type: String
    public var programID: String
    public var offset: Double
    public var phases: [TLPhase]
}

public struct TLPhase: Sendable {
    public var duration: Double
    public var minDuration: Double?
    public var maxDuration: Double?
    public var state: String
}

public struct Roundabout: Sendable {
    public var nodes: [String]
    public var edges: [String]
}

public struct PolygonShape: Sendable {
    public var id: String
    public var type: String
    public var color: SumoColor
    public var fill: Bool
    public var layer: Float
    public var shapeOffset: Int32
    public var shapeCount: Int32
    public var bounds: SIMD4<Float>
}

public struct POI: Sendable {
    public var id: String
    public var type: String
    public var color: SumoColor
    public var position: SIMD2<Float>
    public var layer: Float
    public var width: Float
    public var height: Float
    public var imageFile: String
}

public final class NetGraph: @unchecked Sendable {
    public var location = NetLocation(netOffset: .zero, convBoundary: .zero,
                                      origBoundary: .zero, projParameter: "!")
    public var edges = ContiguousArray<Edge>()
    public var lanes = ContiguousArray<Lane>()
    public var junctions = ContiguousArray<Junction>()
    public var connections = ContiguousArray<Connection>()
    public var tlLogics = ContiguousArray<TrafficLightLogic>()
    public var roundabouts = ContiguousArray<Roundabout>()
    public var polygons = ContiguousArray<PolygonShape>()
    public var pois = ContiguousArray<POI>()
    public var laneShapePoints = ContiguousArray<SIMD2<Float>>()
    public var junctionShapePoints = ContiguousArray<SIMD2<Float>>()
    public var polygonShapePoints = ContiguousArray<SIMD2<Float>>()

    public var edgeIndex: [String: Int32] = [:]
    public var laneIndex: [String: Int32] = [:]
    public var junctionIndex: [String: Int32] = [:]

    public init() {}

    public func bounds() -> SIMD4<Float> {
        let declared = SIMD4<Float>(Float(location.convBoundary.x), Float(location.convBoundary.y),
                                    Float(location.convBoundary.z), Float(location.convBoundary.w))
        let content = contentBounds()
        if shouldIndex(declared), shouldIndex(content) {
            return unionBounds(declared, content)
        }
        if shouldIndex(declared) {
            return declared
        }
        if shouldIndex(content) {
            return content
        }
        return SIMD4<Float>(0, 0, 1, 1)
    }

    public func laneShape(_ lane: Lane) -> ArraySlice<SIMD2<Float>> {
        let lo = Int(lane.shapeOffset)
        let hi = lo + Int(lane.shapeCount)
        return laneShapePoints[lo..<hi]
    }
    public func junctionShape(_ j: Junction) -> ArraySlice<SIMD2<Float>> {
        let lo = Int(j.shapeOffset)
        let hi = lo + Int(j.shapeCount)
        return junctionShapePoints[lo..<hi]
    }
    public func polygonShape(_ polygon: PolygonShape) -> ArraySlice<SIMD2<Float>> {
        let lo = Int(polygon.shapeOffset)
        let hi = lo + Int(polygon.shapeCount)
        return polygonShapePoints[lo..<hi]
    }

    public func makeSpatialIndexes(includeInternalEdges: Bool = false) -> SpatialIndexes {
        let rootBounds = padded(bounds())
        let laneTree = Quadtree<Int32>(bounds: rootBounds)
        let edgeTree = Quadtree<Int32>(bounds: rootBounds)
        let junctionTree = Quadtree<Int32>(bounds: rootBounds)

        for (i, lane) in lanes.enumerated() where shouldIndex(lane.bounds) {
            if !includeInternalEdges, lane.edgeIndex >= 0, edges[Int(lane.edgeIndex)].function == .internalEdge {
                continue
            }
            laneTree.insert(.init(payload: Int32(i), bounds: padded(lane.bounds)))
        }
        for (i, edge) in edges.enumerated() where shouldIndex(edge.bounds) {
            if !includeInternalEdges, edge.function == .internalEdge { continue }
            edgeTree.insert(.init(payload: Int32(i), bounds: padded(edge.bounds)))
        }
        for (i, junction) in junctions.enumerated() {
            let bounds = shouldIndex(junction.bounds) ? junction.bounds :
                SIMD4(junction.position.x, junction.position.y, junction.position.x, junction.position.y)
            junctionTree.insert(.init(payload: Int32(i), bounds: padded(bounds)))
        }
        return SpatialIndexes(lanes: laneTree, edges: edgeTree, junctions: junctionTree)
    }

    private func contentBounds() -> SIMD4<Float> {
        var b = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for edge in edges where shouldIndex(edge.bounds) {
            b = unionBounds(b, edge.bounds)
        }
        for junction in junctions {
            let jb = shouldIndex(junction.bounds)
                ? junction.bounds
                : SIMD4(junction.position.x, junction.position.y, junction.position.x, junction.position.y)
            b = unionBounds(b, jb)
        }
        for polygon in polygons where shouldIndex(polygon.bounds) {
            b = unionBounds(b, polygon.bounds)
        }
        for poi in pois {
            b = unionBounds(b, SIMD4(poi.position.x, poi.position.y, poi.position.x, poi.position.y))
        }
        return b
    }
}

@inline(__always)
func shouldIndex(_ b: SIMD4<Float>) -> Bool {
    b.x.isFinite && b.y.isFinite && b.z.isFinite && b.w.isFinite && b.x <= b.z && b.y <= b.w
}

@inline(__always)
func unionBounds(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> SIMD4<Float> {
    if !shouldIndex(a) { return b }
    if !shouldIndex(b) { return a }
    return SIMD4<Float>(min(a.x, b.x), min(a.y, b.y), max(a.z, b.z), max(a.w, b.w))
}

@inline(__always)
func padded(_ b: SIMD4<Float>, minimumSpan: Float = 1) -> SIMD4<Float> {
    guard shouldIndex(b) else { return SIMD4<Float>(0, 0, minimumSpan, minimumSpan) }
    var out = b
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
