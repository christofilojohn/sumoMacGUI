import Foundation

public struct SimulationState: Sendable {
    public var simTime: Double
    public var vehicles: ContiguousArray<VehicleSnapshot>
    public var pois: ContiguousArray<POISnapshot>
    public var selectedVehicle: VehicleDetails?

    public init(
        simTime: Double = 0,
        vehicles: ContiguousArray<VehicleSnapshot> = [],
        pois: ContiguousArray<POISnapshot> = [],
        selectedVehicle: VehicleDetails? = nil
    ) {
        self.simTime = simTime
        self.vehicles = vehicles
        self.pois = pois
        self.selectedVehicle = selectedVehicle
    }
}

public struct POISnapshot: Sendable, Identifiable {
    public let id: String
    public var position: SIMD2<Float>
    public var color: SumoColor?
    public var layer: Float
    public var width: Float
    public var height: Float

    public init(
        id: String,
        position: SIMD2<Float>,
        color: SumoColor? = nil,
        layer: Float = 5,
        width: Float = 2.4,
        height: Float = 2.4
    ) {
        self.id = id
        self.position = position
        self.color = color
        self.layer = layer
        self.width = width
        self.height = height
    }
}

public struct VehicleSnapshot: Sendable, Identifiable {
    public let id: String
    public var position: SIMD2<Float>
    public var angle: Float
    public var speed: Float
    public var typeID: UInt32
    public var acceleration: Float?
    public var co2Emission: Float?
    public var routeID: String?
    public var color: SumoColor?

    public init(
        id: String,
        position: SIMD2<Float>,
        angle: Float,
        speed: Float,
        typeID: UInt32,
        acceleration: Float? = nil,
        co2Emission: Float? = nil,
        routeID: String? = nil,
        color: SumoColor? = nil
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
}

public struct VehicleDetails: Sendable, Equatable, Identifiable {
    public let id: String
    public var position: SIMD2<Float>?
    public var angle: Float?
    public var speed: Float?
    public var acceleration: Float?
    public var lanePosition: Float?
    public var edgeID: String?
    public var laneID: String?
    public var routeID: String?
    public var routeEdgeIDs: [String]
    public var typeID: String?
    public var length: Float?
    public var width: Float?

    public init(
        id: String,
        position: SIMD2<Float>? = nil,
        angle: Float? = nil,
        speed: Float? = nil,
        acceleration: Float? = nil,
        lanePosition: Float? = nil,
        edgeID: String? = nil,
        laneID: String? = nil,
        routeID: String? = nil,
        routeEdgeIDs: [String] = [],
        typeID: String? = nil,
        length: Float? = nil,
        width: Float? = nil
    ) {
        self.id = id
        self.position = position
        self.angle = angle
        self.speed = speed
        self.acceleration = acceleration
        self.lanePosition = lanePosition
        self.edgeID = edgeID
        self.laneID = laneID
        self.routeID = routeID
        self.routeEdgeIDs = routeEdgeIDs
        self.typeID = typeID
        self.length = length
        self.width = width
    }
}
