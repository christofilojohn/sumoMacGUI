import Foundation

// TraCI wire format: big-endian, length-prefixed messages.
// Outer frame: total-length (UInt32 BE) followed by N commands.
// Each command: length (1 byte if <256, else 0 + UInt32 BE), commandID (UInt8), payload.

public struct TraCIWriter {
    public private(set) var data = Data()
    public init() {}

    public mutating func writeU8(_ v: UInt8)   { data.append(v) }
    public mutating func writeI32(_ v: Int32)  { writeBE(UInt32(bitPattern: v)) }
    public mutating func writeU32(_ v: UInt32) { writeBE(v) }
    public mutating func writeF64(_ v: Double) {
        var bits = v.bitPattern.bigEndian
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    public mutating func writeString(_ s: String) {
        let bytes = Array(s.utf8)
        writeI32(Int32(bytes.count))
        data.append(contentsOf: bytes)
    }

    public mutating func writeStringList(_ list: [String]) {
        writeI32(Int32(list.count))
        for s in list { writeString(s) }
    }

    public mutating func writeTypedDouble(_ v: Double) {
        writeU8(TraCI.DataType.double.rawValue)
        writeF64(v)
    }

    public mutating func writeTypedString(_ s: String) {
        writeU8(TraCI.DataType.string.rawValue)
        writeString(s)
    }

    public mutating func writeCommand(_ id: UInt8, payload: Data) {
        let total = payload.count + 2
        if total < 256 {
            writeU8(UInt8(total))
            writeU8(id)
        } else {
            writeU8(0)
            writeI32(Int32(total + 4))
            writeU8(id)
        }
        data.append(payload)
    }

    public func framed() -> Data {
        var out = Data()
        var w = TraCIWriter()
        w.writeI32(Int32(data.count + 4))
        out.append(w.data)
        out.append(data)
        return out
    }

    private mutating func writeBE(_ v: UInt32) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
}

public struct TraCIReader {
    public let data: Data
    public private(set) var offset: Int = 0
    public init(_ data: Data) { self.data = data }

    public var isAtEnd: Bool { offset >= data.count }
    public var remaining: Int { data.count - offset }

    public mutating func readU8() throws -> UInt8 {
        try ensure(1); defer { offset += 1 }
        return data[data.startIndex + offset]
    }

    public mutating func readI32() throws -> Int32 {
        Int32(bitPattern: try readU32())
    }

    public mutating func readU32() throws -> UInt32 {
        try ensure(4)
        var v: UInt32 = 0
        for i in 0..<4 { v = (v << 8) | UInt32(data[data.startIndex + offset + i]) }
        offset += 4
        return v
    }

    public mutating func readF64() throws -> Double {
        try ensure(8)
        var bits: UInt64 = 0
        for i in 0..<8 { bits = (bits << 8) | UInt64(data[data.startIndex + offset + i]) }
        offset += 8
        return Double(bitPattern: bits)
    }

    public mutating func readString() throws -> String {
        let n = Int(try readI32())
        try ensure(n)
        let s = String(bytes: data[(data.startIndex + offset)..<(data.startIndex + offset + n)], encoding: .utf8) ?? ""
        offset += n
        return s
    }

    public mutating func readStringList() throws -> [String] {
        let n = Int(try readI32())
        var out: [String] = []
        out.reserveCapacity(n)
        for _ in 0..<n { out.append(try readString()) }
        return out
    }

    private func ensure(_ n: Int) throws {
        if remaining < n { throw TraCIError.truncated(need: n, have: remaining) }
    }
}

public enum TraCIError: Error, Equatable {
    case truncated(need: Int, have: Int)
    case typeMismatch(expected: UInt8, actual: UInt8)
    case statusError(command: UInt8, message: String)
    case notConnected
    case launchFailed(String)
}
