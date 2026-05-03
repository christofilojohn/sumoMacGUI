import XCTest
@testable import SumoKit

final class TraCIWireTests: XCTestCase {
    func testRoundTripPrimitives() throws {
        var w = TraCIWriter()
        w.writeU8(0x42)
        w.writeI32(-1)
        w.writeF64(3.14159)
        w.writeString("hello")
        w.writeStringList(["a", "bb", "ccc"])

        var r = TraCIReader(w.data)
        XCTAssertEqual(try r.readU8(), 0x42)
        XCTAssertEqual(try r.readI32(), -1)
        XCTAssertEqual(try r.readF64(), 3.14159, accuracy: 1e-9)
        XCTAssertEqual(try r.readString(), "hello")
        XCTAssertEqual(try r.readStringList(), ["a", "bb", "ccc"])
        XCTAssertTrue(r.isAtEnd)
    }

    func testShortCommandFraming() {
        var w = TraCIWriter()
        var payload = TraCIWriter()
        payload.writeU8(0x01)
        w.writeCommand(TraCI.Command.simulationStep.rawValue, payload: payload.data)
        // length(1) + cmdID(1) + payload(1) = 3 prefix byte
        XCTAssertEqual(w.data[0], 3)
        XCTAssertEqual(w.data[1], TraCI.Command.simulationStep.rawValue)
        XCTAssertEqual(w.data[2], 0x01)
    }

    func testTruncationDetected() {
        var r = TraCIReader(Data([0x01, 0x02]))
        XCTAssertThrowsError(try r.readI32())
    }

    func testVersionCompatibilityWarnsOnDifferentSUMOVersion() {
        let matching = SumoVersionCompatibility(apiVersion: 21, identifier: "SUMO 1.26.0")
        XCTAssertTrue(matching.isTargetVersion)
        XCTAssertNil(matching.warning)

        let mismatched = SumoVersionCompatibility(apiVersion: 21, identifier: "SUMO 1.25.0")
        XCTAssertFalse(mismatched.isTargetVersion)
        XCTAssertEqual(mismatched.observedVersion, "1.25.0")
        XCTAssertEqual(mismatched.warning, "SUMO 1.25.0 is connected; this build targets SUMO 1.26.0.")
    }

    func testSubscriptionTrailerParsesVariableAndContextResponses() throws {
        var body = TraCIWriter()
        body.writeI32(2)

        var vehiclePayload = TraCIWriter()
        vehiclePayload.writeString("veh0")
        vehiclePayload.writeU8(1)
        vehiclePayload.writeU8(TraCIClient.Var.speed)
        vehiclePayload.writeU8(0)
        vehiclePayload.writeTypedDouble(12.5)
        body.writeCommand(TraCIClient.DomainCmd.subVehicleVar &+ 0x10, payload: vehiclePayload.data)

        var contextPayload = TraCIWriter()
        contextPayload.writeString("junction0")
        contextPayload.writeU8(TraCIClient.DomainCmd.getVehicle)
        contextPayload.writeU8(2)
        contextPayload.writeI32(1)
        contextPayload.writeString("veh1")
        contextPayload.writeU8(TraCIClient.Var.position)
        contextPayload.writeU8(0)
        contextPayload.writeU8(TraCITypeCode.position2D)
        contextPayload.writeF64(4)
        contextPayload.writeF64(5)
        contextPayload.writeU8(TraCIClient.Var.speed)
        contextPayload.writeU8(0)
        contextPayload.writeTypedDouble(8.5)
        body.writeCommand(TraCIClient.DomainCmd.subJunctionContext &+ 0x10, payload: contextPayload.data)

        var reader = TraCIReader(body.data)
        let responses = try reader.readSubscriptionResponses()

        XCTAssertEqual(responses.count, 2)
        XCTAssertEqual(responses[0].0, TraCIClient.DomainCmd.subVehicleVar &+ 0x10)
        XCTAssertEqual(responses[0].1.objectID, "veh0")
        XCTAssertEqual(responses[0].1.values[TraCIClient.Var.speed]?.asDouble, 12.5)

        XCTAssertEqual(responses[1].0, TraCIClient.DomainCmd.subJunctionContext &+ 0x10)
        XCTAssertEqual(responses[1].1.objectID, "junction0::veh1")
        XCTAssertEqual(responses[1].1.values[TraCIClient.Var.position]?.asPosition2D, SIMD2(4, 5))
        XCTAssertEqual(responses[1].1.values[TraCIClient.Var.speed]?.asDouble, 8.5)
    }
}
