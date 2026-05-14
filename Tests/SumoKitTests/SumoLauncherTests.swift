import XCTest
@testable import SumoKit

final class SumoLauncherTests: XCTestCase {
    func testLaunchArgumentsUseBareBooleanFlags() {
        let config = URL(fileURLWithPath: "/tmp/example/cfg.sumocfg")

        let arguments = SumoLauncher.arguments(
            config: config,
            port: 8813,
            extraArgs: ["--begin", "10"]
        )

        XCTAssertEqual(arguments, [
            "--remote-port", "8813",
            "-c", "/tmp/example/cfg.sumocfg",
            "--no-step-log",
            "--no-warnings",
            "--begin", "10",
        ])
    }
}
