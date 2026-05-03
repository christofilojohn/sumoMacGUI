import Foundation

enum LaneColorMode: String, CaseIterable, Identifiable {
    case speedLimit
    case laneIndex
    case edgeType
    case uniform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speedLimit:
            return "Speed Limit"
        case .laneIndex:
            return "Lane Index"
        case .edgeType:
            return "Edge Type"
        case .uniform:
            return "Uniform"
        }
    }
}

enum VehicleColorMode: String, CaseIterable, Identifiable {
    case speed
    case type
    case uniform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed:
            return "Speed"
        case .type:
            return "Type"
        case .uniform:
            return "Uniform"
        }
    }
}
