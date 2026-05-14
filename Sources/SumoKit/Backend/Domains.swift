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
        public static let edges: UInt8         = 0x54
        public static let route: UInt8         = 0x57
        public static let lengthVar: UInt8     = 0x44
        public static let widthVar: UInt8      = 0x4D
        public static let color: UInt8         = 0x45
        public static let co2Emission: UInt8   = 0x60
        public static let acceleration: UInt8  = 0x72
        public static let lastStepOccupancy: UInt8 = 0x13
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

    // MARK: generic domain helpers

    func idList(commandID: UInt8) async throws -> [String] {
        try (await get(commandID: commandID, variableID: Var.idList, objectID: "")).asStringList ?? []
    }

    func idCount(commandID: UInt8) async throws -> Int32 {
        if case .integer(let value) = try await get(commandID: commandID, variableID: Var.idCount, objectID: "") {
            return value
        }
        return 0
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
    func simLoadedNumber() async throws -> Int32 {
        if case .integer(let value) = try await get(commandID: DomainCmd.getSim, variableID: Var.loadedNumber, objectID: "") {
            return value
        }
        return 0
    }
    func simArrivedNumber() async throws -> Int32 {
        if case .integer(let value) = try await get(commandID: DomainCmd.getSim, variableID: Var.arrivedNumber, objectID: "") {
            return value
        }
        return 0
    }
    func simDepartedNumber() async throws -> Int32 {
        if case .integer(let value) = try await get(commandID: DomainCmd.getSim, variableID: Var.departedNumber, objectID: "") {
            return value
        }
        return 0
    }

    // MARK: vehicle

    func vehicleIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getVehicle)
    }
    func vehicleCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getVehicle)
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
    func vehicleRoute(_ id: String) async throws -> [String] {
        try (await get(commandID: DomainCmd.getVehicle, variableID: Var.edges, objectID: id)).asStringList ?? []
    }

    // MARK: edge / lane / junction id-list helpers

    func edgeIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getEdge)
    }
    func edgeCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getEdge)
    }
    func laneIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getLane)
    }
    func laneCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getLane)
    }
    func laneSpeed(_ id: String) async throws -> Double {
        try (await get(commandID: DomainCmd.getLane, variableID: Var.speed, objectID: id)).asDouble ?? 0
    }
    func laneLength(_ id: String) async throws -> Double {
        try (await get(commandID: DomainCmd.getLane, variableID: Var.lengthVar, objectID: id)).asDouble ?? 0
    }
    func laneLastStepOccupancy(_ id: String) async throws -> Double {
        try (await get(commandID: DomainCmd.getLane, variableID: Var.lastStepOccupancy, objectID: id)).asDouble ?? 0
    }
    func junctionIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getJunction)
    }
    func junctionCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getJunction)
    }
    func tlIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getTL)
    }
    func tlCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getTL)
    }
    func routeIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getRoute)
    }
    func routeCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getRoute)
    }
    func routeEdges(_ id: String) async throws -> [String] {
        try (await get(commandID: DomainCmd.getRoute, variableID: Var.edges, objectID: id)).asStringList ?? []
    }
    func poiIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getPOI)
    }
    func poiCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getPOI)
    }
    func poiPosition(_ id: String) async throws -> SIMD2<Double> {
        try (await get(commandID: DomainCmd.getPOI, variableID: Var.position, objectID: id)).asPosition2D ?? .zero
    }
    func poiColor(_ id: String) async throws -> SumoColor? {
        try (await get(commandID: DomainCmd.getPOI, variableID: Var.color, objectID: id)).asColor
    }
    func polygonIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getPolygon)
    }
    func polygonCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getPolygon)
    }
    func guiViewIDs() async throws -> [String] {
        try await idList(commandID: DomainCmd.getGUI)
    }
    func guiViewCount() async throws -> Int32 {
        try await idCount(commandID: DomainCmd.getGUI)
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
            variables: [Var.position, Var.angle, Var.speed, Var.typeID, Var.acceleration, Var.routeID, Var.co2Emission, Var.color]
        )
    }

    /// Subscribes to all vehicles around a junction within `range`.
    func subscribeVehiclesAroundJunction(_ junctionID: String, range: Double = 1e6) async throws {
        try await subscribeContext(
            commandID: DomainCmd.subJunctionContext,
            objectID: junctionID,
            domain: DomainCmd.getVehicle,
            range: range,
            variables: [Var.position, Var.angle, Var.speed, Var.typeID, Var.acceleration, Var.routeID, Var.co2Emission, Var.color]
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
