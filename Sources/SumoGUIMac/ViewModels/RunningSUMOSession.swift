import Foundation
import SumoKit

final class RunningSUMOSession {
    private let handle: SumoLauncher.Handle?
    private let connection: TraCIConnection
    private let client: TraCIClient
    private var viewportSubscription: ViewportVehicleSubscription?
    private var selectedVehicleID: String?
    private var selectedVehicleDetails: VehicleDetails?

    let versionIdentifier: String
    let isAttachedToExternalSUMO: Bool

    private init(
        handle: SumoLauncher.Handle?,
        connection: TraCIConnection,
        client: TraCIClient,
        versionIdentifier: String,
        isAttachedToExternalSUMO: Bool
    ) {
        self.handle = handle
        self.connection = connection
        self.client = client
        self.versionIdentifier = versionIdentifier
        self.isAttachedToExternalSUMO = isAttachedToExternalSUMO
    }

    static func start(config: URL, subscriptionAnchorID: String?) async throws -> RunningSUMOSession {
        guard let sumo = SumoLauncher.locateBinary() else {
            throw RuntimeError("Could not find the SUMO binary. Install SUMO or add `sumo` to a standard location.")
        }

        let launcher = SumoLauncher(binaryPath: sumo)
        let handle = try launcher.launch(config: config)

        try await waitUntilRunning(handle: handle)

        let connection = TraCIConnection(port: handle.port)
        try await connection.connect()
        let client = TraCIClient(connection: connection)
        let version = try await client.getVersion()
        try await client.subscribeSimulation()
        if let subscriptionAnchorID {
            try await client.subscribeVehiclesAroundJunction(subscriptionAnchorID)
        }

        let session = RunningSUMOSession(
            handle: handle,
            connection: connection,
            client: client,
            versionIdentifier: version.identifier,
            isAttachedToExternalSUMO: false
        )
        if let subscriptionAnchorID {
            session.viewportSubscription = ViewportVehicleSubscription(anchorID: subscriptionAnchorID, range: 1e6)
        }
        return session
    }

    static func attach(
        host: String,
        port: Int,
        clientOrder: Int32,
        subscriptionAnchorID: String?
    ) async throws -> RunningSUMOSession {
        guard (1...65_535).contains(port) else {
            throw RuntimeError("TraCI port must be between 1 and 65535.")
        }
        let connection = TraCIConnection(host: host, port: port)
        try await connection.connect(retries: 5, retryDelayMS: 100)
        let client = TraCIClient(connection: connection)
        try await client.setOrder(clientOrder)
        let version = try await client.getVersion()
        try await client.subscribeSimulation()
        if let subscriptionAnchorID {
            try await client.subscribeVehiclesAroundJunction(subscriptionAnchorID)
        }

        let session = RunningSUMOSession(
            handle: nil,
            connection: connection,
            client: client,
            versionIdentifier: version.identifier,
            isAttachedToExternalSUMO: true
        )
        if let subscriptionAnchorID {
            session.viewportSubscription = ViewportVehicleSubscription(anchorID: subscriptionAnchorID, range: 1e6)
        }
        return session
    }

    func step() async throws -> SimulationState {
        let results = try await client.step(targetTime: 0)
        let simTime = results.first(where: { $0.0 == (TraCIClient.DomainCmd.subSimVar &+ 0x10) })?.1.values[TraCIClient.Var.simTime]?.asDouble
        var snapshots = ContiguousArray<VehicleSnapshot>()

        for (command, result) in results where command == (TraCIClient.DomainCmd.subJunctionContext &+ 0x10) {
            guard let vehicleID = subscribedObjectID(from: result.objectID) else {
                continue
            }
            guard let position = result.values[TraCIClient.Var.position]?.asPosition2D else {
                continue
            }
            let angle = Float(result.values[TraCIClient.Var.angle]?.asDouble ?? 0)
            let speed = Float(result.values[TraCIClient.Var.speed]?.asDouble ?? 0)
            let typeID = stableTypeID(from: result.values[TraCIClient.Var.typeID]?.asString ?? "")
            snapshots.append(VehicleSnapshot(
                id: vehicleID,
                position: SIMD2(Float(position.x), Float(position.y)),
                angle: angle,
                speed: speed,
                typeID: typeID
            ))
        }

        for (command, result) in results where command == (TraCIClient.DomainCmd.subVehicleVar &+ 0x10) {
            guard result.objectID == selectedVehicleID else { continue }
            selectedVehicleDetails = vehicleDetails(id: result.objectID, values: result.values)
        }

        if snapshots.isEmpty {
            snapshots = try await pollVehiclesFallback()
        }

        let resolvedSimTime = if let simTime {
            simTime
        } else {
            try await client.simTime()
        }
        return SimulationState(simTime: resolvedSimTime, vehicles: snapshots, selectedVehicle: selectedVehicleDetails)
    }

    func updateVehicleViewport(anchorID: String, range: Double) async throws {
        let next = ViewportVehicleSubscription(anchorID: anchorID, range: range)
        if let current = viewportSubscription, current.isEquivalent(to: next) {
            return
        }
        if let current = viewportSubscription {
            try await client.unsubscribeVehiclesAroundJunction(current.anchorID)
        }
        try await client.subscribeVehiclesAroundJunction(anchorID, range: range)
        viewportSubscription = next
    }

    func selectVehicle(_ id: String?) async throws {
        if selectedVehicleID == id {
            return
        }
        if let selectedVehicleID {
            try? await client.unsubscribeVehicleDetails(selectedVehicleID)
        }
        selectedVehicleID = id
        selectedVehicleDetails = id.map { VehicleDetails(id: $0) }
        if let id {
            try await client.subscribeVehicleDetails(id)
        }
    }

    func close() async {
        if let selectedVehicleID {
            try? await client.unsubscribeVehicleDetails(selectedVehicleID)
        }
        if let viewportSubscription {
            try? await client.unsubscribeVehiclesAroundJunction(viewportSubscription.anchorID)
        }
        if !isAttachedToExternalSUMO {
            try? await client.close()
        }
        await connection.close()
        handle?.terminate()
    }

    func terminateImmediately() {
        handle?.terminate()
    }

    private static func waitUntilRunning(handle: SumoLauncher.Handle) async throws {
        for _ in 0..<40 {
            if handle.process.isRunning {
                try await Task.sleep(nanoseconds: 50_000_000)
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        let stderr = handle.readAvailableStderr()
        throw RuntimeError(stderr.isEmpty ? "SUMO exited before TraCI could connect." : stderr)
    }

    private func pollVehiclesFallback() async throws -> ContiguousArray<VehicleSnapshot> {
        let vehicleIDs = try await client.vehicleIDs()
        var snapshots = ContiguousArray<VehicleSnapshot>()
        snapshots.reserveCapacity(vehicleIDs.count)
        for id in vehicleIDs {
            let position = try await client.vehiclePosition(id)
            let angle = try await client.vehicleAngle(id)
            let speed = try await client.vehicleSpeed(id)
            let typeID = stableTypeID(from: try await client.vehicleType(id))
            snapshots.append(VehicleSnapshot(
                id: id,
                position: SIMD2(Float(position.x), Float(position.y)),
                angle: Float(angle),
                speed: Float(speed),
                typeID: typeID
            ))
        }
        return snapshots
    }

    private func vehicleDetails(id: String, values: [UInt8: TraCIValue]) -> VehicleDetails {
        let position = values[TraCIClient.Var.position]?.asPosition2D
        return VehicleDetails(
            id: id,
            position: position.map { SIMD2(Float($0.x), Float($0.y)) },
            angle: values[TraCIClient.Var.angle]?.asDouble.map(Float.init),
            speed: values[TraCIClient.Var.speed]?.asDouble.map(Float.init),
            acceleration: values[TraCIClient.Var.acceleration]?.asDouble.map(Float.init),
            lanePosition: values[TraCIClient.Var.lanePosition]?.asDouble.map(Float.init),
            edgeID: values[TraCIClient.Var.edgeID]?.asString,
            laneID: values[TraCIClient.Var.laneID]?.asString,
            routeID: values[TraCIClient.Var.routeID]?.asString,
            typeID: values[TraCIClient.Var.typeID]?.asString,
            length: values[TraCIClient.Var.lengthVar]?.asDouble.map(Float.init),
            width: values[TraCIClient.Var.widthVar]?.asDouble.map(Float.init)
        )
    }

    private func subscribedObjectID(from syntheticID: String) -> String? {
        guard let separator = syntheticID.range(of: "::") else { return nil }
        return String(syntheticID[separator.upperBound...])
    }

    private func stableTypeID(from type: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for byte in type.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        return hash
    }
}

private struct ViewportVehicleSubscription {
    let anchorID: String
    let range: Double

    func isEquivalent(to other: ViewportVehicleSubscription) -> Bool {
        anchorID == other.anchorID && abs(range - other.range) < max(25, range * 0.10)
    }
}

struct RuntimeError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
