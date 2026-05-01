import Foundation

// Per-domain typed wrappers around `TraCIClient.get`. Constants from upstream header.
// Kept thin on purpose: anything not here can be reached via raw client.get(...).

public extension TraCIClient {
    enum DomainCmd {
        public static let getInductionLoop: UInt8 = 0xA0
        public static let getMultiEntryExit: UInt8 = 0xA1
        public static let getTL: UInt8           = 0xA2
        public static let getLane: UInt8         = 0xA3
        public static let getVehicle: UInt8      = 0xA4
        public static let getVehicleType: UInt8  = 0xA5
        public static let getRoute: UInt8        = 0xA6
        public static let getPOI: UInt8          = 0xA7
        public static let getPolygon: UInt8      = 0xA8
        public static let getJunction: UInt8     = 0xA9
        public static let getEdge: UInt8         = 0xAA
        public static let getSim: UInt8          = 0xAB
        public static let getGUI: UInt8          = 0xAC

        public static let subVehicleVar: UInt8     = 0xD4
        public static let subVehicleContext: UInt8 = 0x84
        public static let subJunctionContext: UInt8 = 0x89
        public static let subSimVar: UInt8         = 0xDB
    }

    enum Var {
        public static let idList: UInt8        = 0x00
        public static let idCount: UInt8       = 0x01
        public static let speed: UInt8         = 0x40
        public static let position: UInt8      = 0x42
        public static let position3D: UInt8    = 0x39
        public static let angle: UInt8         = 0x43
        public static let typeID: UInt8        = 0x4F
        public static let routeID: UInt8       = 0x53
        public static let route: UInt8         = 0x57
        public static let lengthVar: UInt8     = 0x44
        public static let widthVar: UInt8      = 0x4D
        public static let color: UInt8         = 0x45
        public static let acceleration: UInt8  = 0x72
        public static let lanePosition: UInt8  = 0x56
        public static let edgeID: UInt8        = 0x50
        public static let laneID: UInt8        = 0x51

        public static let simTime: UInt8       = 0x66
        public static let deltaT: UInt8        = 0x7B
        public static let loadedNumber: UInt8  = 0x71
        public static let minExpected: UInt8   = 0x7D
        public static let arrivedNumber: UInt8 = 0x79
        public static let departedNumber: UInt8 = 0x73
    }

    // MARK: simulation

    func simTime() async throws -> Double {
        try (await get(commandID: DomainCmd.getSim, variableID: Var.simTime, objectID: "")).asDouble ?? 0
    }
    func simDeltaT() async throws -> Double {
        try (await get(commandID: DomainCmd.getSim, variableID: Var.deltaT, objectID: "")).asDouble ?? 0
    }
    func simMinExpected() async throws -> Int32 {
        if case .integer(let v) = try await get(commandID: DomainCmd.getSim, variableID: Var.minExpected, objectID: "") {
            return v
        }
        return 0
    }

    // MARK: vehicle

    func vehicleIDs() async throws -> [String] {
        try (await get(commandID: DomainCmd.getVehicle, variableID: Var.idList, objectID: "")).asStringList ?? []
    }
    func vehiclePosition(_ id: String) async throws -> SIMD2<Double> {
        try (await get(commandID: DomainCmd.getVehicle, variableID: Var.position, objectID: id)).asPosition2D ?? .zero
    }
    func vehicleSpeed(_ id: String) async throws -> Double {
        try (await get(commandID: DomainCmd.getVehicle, variableID: Var.speed, objectID: id)).asDouble ?? 0
    }
    func vehicleAngle(_ id: String) async throws -> Double {
        try (await get(commandID: DomainCmd.getVehicle, variableID: Var.angle, objectID: id)).asDouble ?? 0
    }
    func vehicleType(_ id: String) async throws -> String {
        try (await get(commandID: DomainCmd.getVehicle, variableID: Var.typeID, objectID: id)).asString ?? ""
    }

    // MARK: edge / lane / junction id-list helpers

    func edgeIDs() async throws -> [String] {
        try (await get(commandID: DomainCmd.getEdge, variableID: Var.idList, objectID: "")).asStringList ?? []
    }
    func laneIDs() async throws -> [String] {
        try (await get(commandID: DomainCmd.getLane, variableID: Var.idList, objectID: "")).asStringList ?? []
    }
    func junctionIDs() async throws -> [String] {
        try (await get(commandID: DomainCmd.getJunction, variableID: Var.idList, objectID: "")).asStringList ?? []
    }
    func tlIDs() async throws -> [String] {
        try (await get(commandID: DomainCmd.getTL, variableID: Var.idList, objectID: "")).asStringList ?? []
    }

    // MARK: high-level subscription helpers

    /// Subscribes to viewport-bulk vehicle data: every vehicle in range of `egoEdgeOrJunction`
    /// emits position+angle+speed+type per step. Use after first `step`.
    func subscribeVehiclesAround(egoID: String, range: Double = 1e6) async throws {
        try await subscribeContext(
            commandID: DomainCmd.subVehicleContext,
            objectID: egoID,
            domain: DomainCmd.getVehicle,
            range: range,
            variables: [Var.position, Var.angle, Var.speed, Var.typeID]
        )
    }

    /// Subscribes to all vehicles around a junction within `range`.
    func subscribeVehiclesAroundJunction(_ junctionID: String, range: Double = 1e6) async throws {
        try await subscribeContext(
            commandID: DomainCmd.subJunctionContext,
            objectID: junctionID,
            domain: DomainCmd.getVehicle,
            range: range,
            variables: [Var.position, Var.angle, Var.speed, Var.typeID]
        )
    }

    func unsubscribeVehiclesAroundJunction(_ junctionID: String) async throws {
        try await unsubscribeContext(
            commandID: DomainCmd.subJunctionContext,
            objectID: junctionID,
            domain: DomainCmd.getVehicle
        )
    }

    func subscribeVehicleDetails(_ vehicleID: String) async throws {
        try await subscribeVariable(
            commandID: DomainCmd.subVehicleVar,
            objectID: vehicleID,
            variables: [
                Var.position,
                Var.angle,
                Var.speed,
                Var.acceleration,
                Var.lanePosition,
                Var.edgeID,
                Var.laneID,
                Var.routeID,
                Var.typeID,
                Var.lengthVar,
                Var.widthVar,
            ]
        )
    }

    func unsubscribeVehicleDetails(_ vehicleID: String) async throws {
        try await unsubscribeVariable(commandID: DomainCmd.subVehicleVar, objectID: vehicleID)
    }

    /// Subscribes to scalar simulation vars (time + counts) for HUD.
    func subscribeSimulation() async throws {
        try await subscribeVariable(
            commandID: DomainCmd.subSimVar,
            objectID: "",
            variables: [Var.simTime, Var.minExpected, Var.loadedNumber, Var.arrivedNumber, Var.departedNumber]
        )
    }
}
