import XCTest
@testable import SumoKit

// Integration tests: spawn real SUMO. Skipped if SUMO is not installed.
final class TraCIIntegrationTests: XCTestCase {
    func makeTinyScenario() throws -> URL {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sumokit-it-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let bundle = Bundle.module
        guard let netSrc = bundle.url(forResource: "tiny", withExtension: "net.xml", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "tiny.net", withExtension: "xml", subdirectory: "Fixtures") else {
            throw XCTSkip("Fixture tiny.net.xml not found in bundle")
        }
        try FileManager.default.copyItem(at: netSrc, to: tmp.appendingPathComponent("tiny.net.xml"))

        let routes = """
        <routes>
            <vType id="car" accel="2.6" decel="4.5" length="5" maxSpeed="13.89"/>
            <route id="r" edges="e1 e2"/>
            <vehicle id="v0" type="car" route="r" depart="0"/>
            <vehicle id="v1" type="car" route="r" depart="1"/>
        </routes>
        """
        let cfg = """
        <configuration>
            <input>
                <net-file value="tiny.net.xml"/>
                <route-files value="rou.rou.xml"/>
            </input>
            <time><begin value="0"/><end value="30"/></time>
        </configuration>
        """
        try routes.write(to: tmp.appendingPathComponent("rou.rou.xml"), atomically: true, encoding: .utf8)
        try cfg.write(to: tmp.appendingPathComponent("cfg.sumocfg"), atomically: true, encoding: .utf8)
        return tmp.appendingPathComponent("cfg.sumocfg")
    }

    func testGetVersionAndStep() async throws {
        guard let sumo = SumoLauncher.locateBinary() else {
            throw XCTSkip("SUMO not installed")
        }
        let cfg = try makeTinyScenario()
        let launcher = SumoLauncher(binaryPath: sumo)
        let handle = try launcher.launch(config: cfg)
        defer { handle.terminate() }

        // Give SUMO a moment to bind the port.
        try await Task.sleep(nanoseconds: 800_000_000)

        if !handle.process.isRunning {
            let err = handle.stderrPipe.fileHandleForReading.availableData
            XCTFail("SUMO died early. stderr:\n\(String(data: err, encoding: .utf8) ?? "(none)")")
            return
        }

        let conn = TraCIConnection(port: handle.port)
        try await conn.connect()
        TraCIClient.traceWire = true
        let client = TraCIClient(connection: conn)

        let v = try await client.getVersion()
        XCTAssertGreaterThan(v.apiVersion, 0)
        XCTAssertTrue(v.identifier.contains("SUMO"), "expected SUMO identifier, got \(v.identifier)")

        try await client.step(targetTime: 0)
        try await client.step(targetTime: 0)
        try await client.close()
        await conn.close()
    }
}
