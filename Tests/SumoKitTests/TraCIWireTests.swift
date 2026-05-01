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
}
