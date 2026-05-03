import Foundation
import Darwin
import SumoKit

let arguments = CommandLine.arguments.dropFirst()
guard let path = arguments.first else {
    FileHandle.standardError.write(Data("Usage: swift run -c release NetParseBenchmark <network.net.xml>\n".utf8))
    exit(2)
}

let url = URL(fileURLWithPath: path).standardizedFileURL
let parseStart = Date()
let graph = try NetXMLParser.parse(url: url)
let parseDuration = Date().timeIntervalSince(parseStart)

let indexStart = Date()
let indexes = graph.makeSpatialIndexes()
let indexDuration = Date().timeIntervalSince(indexStart)

let laneBounds = graph.lanes.reduce(nil as SIMD4<Float>?) { partial, lane in
    guard lane.bounds.x.isFinite, lane.bounds.y.isFinite, lane.bounds.z.isFinite, lane.bounds.w.isFinite else {
        return partial
    }
    guard lane.bounds.x <= lane.bounds.z, lane.bounds.y <= lane.bounds.w else {
        return partial
    }
    guard let partial else { return lane.bounds }
    return SIMD4(
        min(partial.x, lane.bounds.x),
        min(partial.y, lane.bounds.y),
        max(partial.z, lane.bounds.z),
        max(partial.w, lane.bounds.w)
    )
}
let fullLaneHits = laneBounds.map { indexes.lanes.query(in: $0).count } ?? 0
let estimatedBytes =
    graph.edges.count * MemoryLayout<Edge>.stride +
    graph.lanes.count * MemoryLayout<Lane>.stride +
    graph.junctions.count * MemoryLayout<Junction>.stride +
    graph.connections.count * MemoryLayout<Connection>.stride +
    graph.laneShapePoints.count * MemoryLayout<SIMD2<Float>>.stride +
    graph.junctionShapePoints.count * MemoryLayout<SIMD2<Float>>.stride

print("file=\(url.path)")
print(String(format: "parse_seconds=%.3f", parseDuration))
print(String(format: "index_seconds=%.3f", indexDuration))
print("edges=\(graph.edges.count)")
print("lanes=\(graph.lanes.count)")
print("junctions=\(graph.junctions.count)")
print("connections=\(graph.connections.count)")
print("indexed_lane_hits=\(fullLaneHits)")
print(String(format: "estimated_pod_mb=%.2f", Double(estimatedBytes) / 1_048_576.0))
