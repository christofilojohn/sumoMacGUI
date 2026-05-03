import Foundation

public actor TraCIClient {
    private let connection: TraCIConnection
    private static let invalidSubscriptionTime = -1_073_741_824.0

    public init(connection: TraCIConnection) {
        self.connection = connection
    }

    public static var traceWire: Bool = false

    // MARK: - Lifecycle

    public func getVersion() async throws -> (apiVersion: Int32, identifier: String) {
        let body = try await sendCommand(commandID: TraCI.Command.getVersion.rawValue, payload: Data())
        var r = TraCIReader(body)
        try expectResponseBlock(commandID: TraCI.Command.getVersion.rawValue, reader: &r)
        let api = try r.readI32()
        let ident = try r.readString()
        return (api, ident)
    }

    /// Steps the simulation. Returns any subscription results emitted in the trailer.
    @discardableResult
    public func step(targetTime: Double = 0) async throws -> [(UInt8, SubscriptionResult)] {
        var p = TraCIWriter()
        p.writeF64(targetTime)
        let body = try await sendCommand(commandID: TraCI.Command.simulationStep.rawValue, payload: p.data)

        var r = TraCIReader(body)
        return try r.readSubscriptionResponses()
    }

    public func close() async throws {
        _ = try await sendCommand(commandID: TraCI.Command.close.rawValue, payload: Data(),
                                  expectResponseBlock: false)
    }

    public func setOrder(_ order: Int32) async throws {
        var p = TraCIWriter()
        p.writeI32(order)
        _ = try await sendCommand(
            commandID: TraCI.Command.setOrder.rawValue,
            payload: p.data,
            expectResponseBlock: false
        )
    }

    // MARK: - Generic GET

    /// Generic GET. `commandID` is e.g. CMD_GET_VEHICLE_VARIABLE = 0xa4.
    /// Returns the typed value the server wrote (after skipping the response header + echoed varID + objectID).
    public func get(commandID: UInt8, variableID: UInt8, objectID: String) async throws -> TraCIValue {
        var p = TraCIWriter()
        p.writeU8(variableID)
        p.writeString(objectID)
        let body = try await sendCommand(commandID: commandID, payload: p.data)
        var r = TraCIReader(body)
        // Response block
        _ = try r.readCommandLengthHeader()
        let respCmd = try r.readU8()
        let expected = commandID &+ 0x10
        guard respCmd == expected else {
            throw TraCIError.statusError(command: commandID,
                message: "resp cmd 0x\(String(respCmd, radix: 16)) != 0x\(String(expected, radix: 16))")
        }
        _ = try r.readU8()        // echoed variable id
        _ = try r.readString()    // echoed object id
        return try r.readTyped()
    }

    // MARK: - Subscriptions

    public func subscribeVariable(commandID: UInt8, objectID: String,
                                  begin: Double = 0, end: Double = 1e9,
                                  variables: [UInt8]) async throws {
        var p = TraCIWriter()
        p.writeF64(begin)
        p.writeF64(end)
        p.writeString(objectID)
        p.writeU8(UInt8(variables.count))
        for v in variables { p.writeU8(v) }
        let body = try await sendCommand(commandID: commandID, payload: p.data)
        // Server replies with first sample inline. We just consume it without validation.
        _ = body
    }

    public func unsubscribeVariable(commandID: UInt8, objectID: String) async throws {
        try await subscribeVariable(
            commandID: commandID,
            objectID: objectID,
            begin: Self.invalidSubscriptionTime,
            end: Self.invalidSubscriptionTime,
            variables: []
        )
    }

    public func subscribeContext(commandID: UInt8, objectID: String,
                                 begin: Double = 0, end: Double = 1e9,
                                 domain: UInt8, range: Double,
                                 variables: [UInt8]) async throws {
        var p = TraCIWriter()
        p.writeF64(begin)
        p.writeF64(end)
        p.writeString(objectID)
        p.writeU8(domain)
        p.writeF64(range)
        p.writeU8(UInt8(variables.count))
        for v in variables { p.writeU8(v) }
        _ = try await sendCommand(commandID: commandID, payload: p.data)
    }

    public func unsubscribeContext(commandID: UInt8, objectID: String,
                                   domain: UInt8, range: Double = 0) async throws {
        try await subscribeContext(
            commandID: commandID,
            objectID: objectID,
            begin: Self.invalidSubscriptionTime,
            end: Self.invalidSubscriptionTime,
            domain: domain,
            range: range,
            variables: []
        )
    }

    // MARK: - Internals

    @discardableResult
    private func sendCommand(commandID: UInt8, payload: Data, expectResponseBlock: Bool = true) async throws -> Data {
        var w = TraCIWriter()
        w.writeCommand(commandID, payload: payload)
        let framed = w.framed()
        if Self.traceWire { print("→", framed.map { String(format: "%02x", $0) }.joined(separator: " ")) }
        try await connection.send(framed)

        let body = try await connection.receiveMessage()
        if Self.traceWire { print("←", body.map { String(format: "%02x", $0) }.joined(separator: " ")) }

        var r = TraCIReader(body)
        let lenByte = Int(try r.readU8())
        if lenByte == 0 { _ = try r.readI32() }
        let statusCmd = try r.readU8()
        guard statusCmd == commandID else {
            throw TraCIError.statusError(command: commandID,
                message: "status cmd 0x\(String(statusCmd, radix: 16)) != 0x\(String(commandID, radix: 16))")
        }
        let result = try r.readU8()
        let desc = try r.readString()
        if result != 0 {
            throw TraCIError.statusError(command: commandID, message: "result=\(result) \(desc)")
        }
        return body.subdata(in: r.offset..<body.count)
    }

    private func expectResponseBlock(commandID: UInt8, reader: inout TraCIReader) throws {
        _ = try reader.readCommandLengthHeader()
        let cmd = try reader.readU8()
        guard cmd == commandID else {
            throw TraCIError.statusError(command: commandID,
                message: "resp cmd 0x\(String(cmd, radix: 16)) != 0x\(String(commandID, radix: 16))")
        }
    }
}
