import Foundation

public enum NetParseError: Error {
    case ioError(String)
    case malformed(String)
}

/// Streaming SAX parser for SUMO `.net.xml`. Produces a fully-populated `NetGraph`.
/// Designed for >100MB files: only the running attribute set is held in memory at any moment.
public final class NetXMLParser: NSObject, XMLParserDelegate {
    private let graph: NetGraph
    private var error: Error?

    private var currentEdge: Edge?
    private var currentEdgeLanes: [Lane] = []
    private var currentJunction: Junction?
    private var currentTL: TrafficLightLogic?

    public override init() {
        self.graph = NetGraph()
        super.init()
    }

    public static func parse(url: URL) throws -> NetGraph {
        guard let parser = XMLParser(contentsOf: url) else {
            throw NetParseError.ioError("could not open \(url.path)")
        }
        let delegate = NetXMLParser()
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            if let e = delegate.error { throw e }
            throw NetParseError.malformed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return delegate.graph
    }

    public static func parseAdditional(url: URL, into graph: NetGraph) throws {
        guard let parser = XMLParser(contentsOf: url) else {
            throw NetParseError.ioError("could not open \(url.path)")
        }
        let delegate = NetXMLParser(graph: graph)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            if let e = delegate.error { throw e }
            throw NetParseError.malformed(parser.parserError?.localizedDescription ?? "unknown")
        }
    }

    private init(graph: NetGraph) {
        self.graph = graph
        super.init()
    }

    public func parser(_ parser: XMLParser, didStartElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?,
                       attributes attrs: [String : String] = [:]) {
        switch elementName {
        case "location":
            graph.location = NetLocation(
                netOffset: parsePoint(attrs["netOffset"]) ?? .zero,
                convBoundary: parseBox(attrs["convBoundary"]) ?? .zero,
                origBoundary: parseBox(attrs["origBoundary"]) ?? .zero,
                projParameter: attrs["projParameter"] ?? "!"
            )
        case "edge":
            let id = attrs["id"] ?? ""
            let function: EdgeFunction = {
                switch attrs["function"] {
                case "internal": return .internalEdge
                case "connector": return .connector
                case "crossing": return .crossing
                case "walkingarea": return .walkingArea
                default: return .normal
                }
            }()
            currentEdge = Edge(
                id: id,
                fromJunction: attrs["from"] ?? "",
                toJunction: attrs["to"] ?? "",
                function: function,
                priority: Int16(attrs["priority"] ?? "0") ?? 0,
                laneRange: 0..<0,
                bounds: SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
            )
            currentEdgeLanes.removeAll(keepingCapacity: true)
        case "lane":
            guard currentEdge != nil else { return }
            let id = attrs["id"] ?? ""
            let shape = parsePolyline(attrs["shape"] ?? "")
            let off = Int32(graph.laneShapePoints.count)
            graph.laneShapePoints.append(contentsOf: shape)
            let bounds = bounds(of: shape)
            let lane = Lane(
                id: id,
                edgeIndex: -1,                // patched on edge close
                index: Int16(attrs["index"] ?? "0") ?? 0,
                speed: Float(attrs["speed"] ?? "0") ?? 0,
                length: Float(attrs["length"] ?? "0") ?? 0,
                width: Float(attrs["width"] ?? "3.2") ?? 3.2,
                allowsAll: attrs["disallow"] == nil,
                shapeOffset: off,
                shapeCount: Int32(shape.count),
                bounds: bounds
            )
            currentEdgeLanes.append(lane)
        case "junction":
            let id = attrs["id"] ?? ""
            let pos = SIMD2<Float>(
                Float(attrs["x"] ?? "0") ?? 0,
                Float(attrs["y"] ?? "0") ?? 0
            )
            let shape = parsePolyline(attrs["shape"] ?? "")
            let off = Int32(graph.junctionShapePoints.count)
            graph.junctionShapePoints.append(contentsOf: shape)
            currentJunction = Junction(
                id: id,
                type: attrs["type"] ?? "",
                position: pos,
                shapeOffset: off,
                shapeCount: Int32(shape.count),
                bounds: bounds(of: shape),
                incomingLanes: parseSpaceList(attrs["incLanes"]),
                internalLanes: parseSpaceList(attrs["intLanes"])
            )
        case "connection":
            let conn = Connection(
                fromEdge: attrs["from"] ?? "",
                toEdge: attrs["to"] ?? "",
                fromLane: Int16(attrs["fromLane"] ?? "0") ?? 0,
                toLane: Int16(attrs["toLane"] ?? "0") ?? 0,
                via: attrs["via"] ?? "",
                trafficLightID: attrs["tl"] ?? "",
                linkIndex: Int16(attrs["linkIndex"] ?? "-1") ?? -1,
                dir: attrs["dir"] ?? "",
                state: attrs["state"] ?? ""
            )
            graph.connections.append(conn)
        case "tlLogic":
            currentTL = TrafficLightLogic(
                id: attrs["id"] ?? "",
                type: attrs["type"] ?? "",
                programID: attrs["programID"] ?? "0",
                offset: Double(attrs["offset"] ?? "0") ?? 0,
                phases: []
            )
        case "phase":
            guard var tl = currentTL else { return }
            tl.phases.append(TLPhase(
                duration: Double(attrs["duration"] ?? "0") ?? 0,
                minDuration: attrs["minDur"].flatMap(Double.init),
                maxDuration: attrs["maxDur"].flatMap(Double.init),
                state: attrs["state"] ?? ""
            ))
            currentTL = tl
        case "roundabout":
            graph.roundabouts.append(Roundabout(
                nodes: parseSpaceList(attrs["nodes"]),
                edges: parseSpaceList(attrs["edges"])
            ))
        case "poly":
            let shape = parsePolyline(attrs["shape"] ?? "")
            let offset = Int32(graph.polygonShapePoints.count)
            graph.polygonShapePoints.append(contentsOf: shape)
            graph.polygons.append(PolygonShape(
                id: attrs["id"] ?? "",
                type: attrs["type"] ?? "",
                color: parseColor(attrs["color"]) ?? SumoColor(red: 96, green: 130, blue: 166, alpha: 180),
                fill: parseBool(attrs["fill"], defaultValue: true),
                layer: Float(attrs["layer"] ?? "0") ?? 0,
                shapeOffset: offset,
                shapeCount: Int32(shape.count),
                bounds: bounds(of: shape)
            ))
        case "poi":
            guard let position = parsePOIPosition(attrs) else { return }
            graph.pois.append(POI(
                id: attrs["id"] ?? "",
                type: attrs["type"] ?? "",
                color: parseColor(attrs["color"]) ?? SumoColor(red: 247, green: 192, blue: 74, alpha: 255),
                position: position,
                layer: Float(attrs["layer"] ?? "0") ?? 0,
                width: Float(attrs["width"] ?? "8") ?? 8,
                height: Float(attrs["height"] ?? "8") ?? 8,
                imageFile: attrs["imgFile"] ?? ""
            ))
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, didEndElement elementName: String,
                       namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "edge":
            guard var edge = currentEdge else { return }
            let edgeIdx = Int32(graph.edges.count)
            let laneStart = Int32(graph.lanes.count)
            var bounds = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
            for var lane in currentEdgeLanes {
                lane.edgeIndex = edgeIdx
                graph.laneIndex[lane.id] = Int32(graph.lanes.count)
                bounds = unionBounds(bounds, lane.bounds)
                graph.lanes.append(lane)
            }
            edge.laneRange = laneStart..<Int32(graph.lanes.count)
            edge.bounds = bounds
            graph.edgeIndex[edge.id] = edgeIdx
            graph.edges.append(edge)
            currentEdge = nil
            currentEdgeLanes.removeAll(keepingCapacity: true)
        case "junction":
            guard let j = currentJunction else { return }
            graph.junctionIndex[j.id] = Int32(graph.junctions.count)
            graph.junctions.append(j)
            currentJunction = nil
        case "tlLogic":
            if let tl = currentTL { graph.tlLogics.append(tl) }
            currentTL = nil
        default:
            break
        }
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }

    // MARK: -

    private func parsePoint(_ s: String?) -> SIMD2<Double>? {
        guard let s, let comma = s.firstIndex(of: ",") else { return nil }
        let x = Double(s[s.startIndex..<comma]) ?? 0
        let y = Double(s[s.index(after: comma)..<s.endIndex]) ?? 0
        return SIMD2(x, y)
    }

    private func parseBox(_ s: String?) -> SIMD4<Double>? {
        guard let s else { return nil }
        let parts = s.split(separator: ",")
        guard parts.count == 4 else { return nil }
        return SIMD4(Double(parts[0]) ?? 0, Double(parts[1]) ?? 0,
                     Double(parts[2]) ?? 0, Double(parts[3]) ?? 0)
    }

    private func parsePolyline(_ s: String) -> [SIMD2<Float>] {
        guard !s.isEmpty else { return [] }
        var out: [SIMD2<Float>] = []
        out.reserveCapacity(8)
        var i = s.startIndex
        while i < s.endIndex {
            while i < s.endIndex, s[i] == " " { i = s.index(after: i) }
            guard let comma = s[i...].firstIndex(of: ",") else { break }
            let x = Float(s[i..<comma]) ?? 0
            let after = s.index(after: comma)
            var j = after
            while j < s.endIndex, s[j] != " " { j = s.index(after: j) }
            let y = Float(s[after..<j]) ?? 0
            out.append(SIMD2(x, y))
            i = j
        }
        return out
    }

    private func parseSpaceList(_ s: String?) -> [String] {
        guard let s, !s.isEmpty else { return [] }
        return s.split(separator: " ").map(String.init)
    }

    private func parsePOIPosition(_ attrs: [String: String]) -> SIMD2<Float>? {
        guard
            let xValue = attrs["x"] ?? attrs["lon"],
            let yValue = attrs["y"] ?? attrs["lat"],
            let x = Float(xValue),
            let y = Float(yValue)
        else {
            return nil
        }
        return SIMD2(x, y)
    }

    private func parseColor(_ value: String?) -> SumoColor? {
        guard let value else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let channels = parts.map { UInt8(clamping: Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0) }
        return SumoColor(
            red: channels[0],
            green: channels[1],
            blue: channels[2],
            alpha: channels.count == 4 ? channels[3] : 255
        )
    }

    private func parseBool(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value else { return defaultValue }
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return defaultValue
        }
    }

    private func bounds(of pts: [SIMD2<Float>]) -> SIMD4<Float> {
        var b = SIMD4<Float>(.infinity, .infinity, -.infinity, -.infinity)
        for p in pts {
            b.x = min(b.x, p.x); b.y = min(b.y, p.y)
            b.z = max(b.z, p.x); b.w = max(b.w, p.y)
        }
        return b
    }
}
