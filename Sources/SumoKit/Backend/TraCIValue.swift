import Foundation

public enum TraCIValue: Sendable, Equatable {
    case integer(Int32)
    case double(Double)
    case string(String)
    case stringList([String])
    case position2D(Double, Double)
    case position3D(Double, Double, Double)
    case color(UInt8, UInt8, UInt8, UInt8)
    case ubyte(UInt8)
    case byte(Int8)
    case compound([TraCIValue])
    case rawBytes(Data)

    public var asDouble: Double? {
        if case .double(let v) = self { return v }
        if case .integer(let v) = self { return Double(v) }
        return nil
    }
    public var asString: String? {
        if case .string(let s) = self { return s }; return nil
    }
    public var asStringList: [String]? {
        if case .stringList(let l) = self { return l }; return nil
    }
    public var asPosition2D: SIMD2<Double>? {
        if case .position2D(let x, let y) = self { return SIMD2(x, y) }
        return nil
    }
}

public enum TraCITypeCode {
    public static let ubyte: UInt8         = 0x07
    public static let byte: UInt8          = 0x08
    public static let integer: UInt8       = 0x09
    public static let double: UInt8        = 0x0B
    public static let string: UInt8        = 0x0C
    public static let stringList: UInt8    = 0x0E
    public static let compound: UInt8      = 0x0F
    public static let position2D: UInt8    = 0x01
    public static let position3D: UInt8    = 0x03
    public static let positionRoadmap: UInt8 = 0x04
    public static let positionLonLat: UInt8  = 0x00
    public static let polygon: UInt8       = 0x06
    public static let color: UInt8         = 0x11
    public static let boundingBox: UInt8   = 0x05
}

extension TraCIReader {
    public mutating func readTyped() throws -> TraCIValue {
        let tag = try readU8()
        switch tag {
        case TraCITypeCode.ubyte:      return .ubyte(try readU8())
        case TraCITypeCode.byte:       return .byte(Int8(bitPattern: try readU8()))
        case TraCITypeCode.integer:    return .integer(try readI32())
        case TraCITypeCode.double:     return .double(try readF64())
        case TraCITypeCode.string:     return .string(try readString())
        case TraCITypeCode.stringList: return .stringList(try readStringList())
        case TraCITypeCode.position2D:
            let x = try readF64(); let y = try readF64()
            return .position2D(x, y)
        case TraCITypeCode.position3D:
            let x = try readF64(); let y = try readF64(); let z = try readF64()
            return .position3D(x, y, z)
        case TraCITypeCode.color:
            let r = try readU8(); let g = try readU8(); let b = try readU8(); let a = try readU8()
            return .color(r, g, b, a)
        case TraCITypeCode.compound:
            let n = Int(try readI32())
            var out: [TraCIValue] = []
            out.reserveCapacity(n)
            for _ in 0..<n { out.append(try readTyped()) }
            return .compound(out)
        default:
            throw TraCIError.typeMismatch(expected: 0xFF, actual: tag)
        }
    }
}
