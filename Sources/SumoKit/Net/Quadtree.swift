import Foundation

/// A static quadtree over `(payload, bounds)` records — built once after parsing,
/// queried per render frame. Designed for large city-scale networks.
public final class Quadtree<Payload: Sendable>: @unchecked Sendable {
    public struct Entry: Sendable {
        public let payload: Payload
        public let bounds: SIMD4<Float>   // xmin ymin xmax ymax
    }

    private final class Node {
        var bounds: SIMD4<Float>
        var entries: [Entry] = []
        var children: [Node]? = nil
        init(bounds: SIMD4<Float>) { self.bounds = bounds }
    }

    private let root: Node
    private let leafCapacity: Int
    private let maxDepth: Int

    public init(bounds: SIMD4<Float>, leafCapacity: Int = 32, maxDepth: Int = 12) {
        self.root = Node(bounds: bounds)
        self.leafCapacity = leafCapacity
        self.maxDepth = maxDepth
    }

    public func insert(_ entry: Entry) {
        insert(entry, into: root, depth: 0)
    }

    public func query(in box: SIMD4<Float>, _ visit: (Payload) -> Void) {
        queryNode(root, box, visit)
    }

    public func query(in box: SIMD4<Float>) -> [Payload] {
        var out: [Payload] = []
        query(in: box) { out.append($0) }
        return out
    }

    private func insert(_ entry: Entry, into node: Node, depth: Int) {
        if let kids = node.children {
            if let kid = containingChild(for: entry.bounds, in: kids) {
                insert(entry, into: kid, depth: depth + 1)
            } else {
                node.entries.append(entry)
            }
            return
        }
        node.entries.append(entry)
        if node.entries.count > leafCapacity, depth < maxDepth {
            split(node, depth: depth)
        }
    }

    private func split(_ node: Node, depth: Int) {
        let b = node.bounds
        let mx = (b.x + b.z) * 0.5
        let my = (b.y + b.w) * 0.5
        let kids = [
            Node(bounds: SIMD4(b.x, b.y, mx, my)),
            Node(bounds: SIMD4(mx, b.y, b.z, my)),
            Node(bounds: SIMD4(b.x, my, mx, b.w)),
            Node(bounds: SIMD4(mx, my, b.z, b.w)),
        ]
        node.children = kids
        let pending = node.entries
        node.entries.removeAll(keepingCapacity: false)
        for e in pending {
            if let kid = containingChild(for: e.bounds, in: kids) {
                insert(e, into: kid, depth: depth + 1)
            } else {
                node.entries.append(e)
            }
        }
    }

    private func queryNode(_ node: Node, _ box: SIMD4<Float>, _ visit: (Payload) -> Void) {
        guard intersects(node.bounds, box) else { return }
        for e in node.entries where intersects(e.bounds, box) { visit(e.payload) }
        if let kids = node.children {
            for k in kids { queryNode(k, box, visit) }
        }
    }

    @inline(__always)
    private func containingChild(for entryBounds: SIMD4<Float>, in children: [Node]) -> Node? {
        for child in children where contains(child.bounds, entryBounds) {
            return child
        }
        return nil
    }

    @inline(__always)
    private func contains(_ outer: SIMD4<Float>, _ inner: SIMD4<Float>) -> Bool {
        inner.x >= outer.x && inner.z <= outer.z && inner.y >= outer.y && inner.w <= outer.w
    }

    @inline(__always)
    private func intersects(_ a: SIMD4<Float>, _ b: SIMD4<Float>) -> Bool {
        !(a.z < b.x || a.x > b.z || a.w < b.y || a.y > b.w)
    }
}
