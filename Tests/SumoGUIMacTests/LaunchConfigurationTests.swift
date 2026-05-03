import XCTest
@testable import SumoGUIMac

final class LaunchConfigurationTests: XCTestCase {
    func testParsesConfigFlag() {
        let cwd = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let config = LaunchConfiguration.from(
            arguments: ["SumoGUIMac", "-c", "Examples/Tiny/tiny.sumocfg"],
            currentDirectoryURL: cwd
        )

        XCTAssertEqual(
            config.openURL,
            URL(fileURLWithPath: "Examples/Tiny/tiny.sumocfg", relativeTo: cwd).standardizedFileURL
        )
    }

    func testParsesBarePath() {
        let cwd = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let config = LaunchConfiguration.from(
            arguments: ["SumoGUIMac", "Examples/Tiny/tiny.sumocfg"],
            currentDirectoryURL: cwd
        )

        XCTAssertEqual(
            config.openURL,
            URL(fileURLWithPath: "Examples/Tiny/tiny.sumocfg", relativeTo: cwd).standardizedFileURL
        )
    }

    func testIgnoresUnknownFlagsWithoutPath() {
        let config = LaunchConfiguration.from(arguments: ["SumoGUIMac", "--verbose"])
        XCTAssertNil(config.openURL)
    }

    func testIgnoresLaunchServiceFlagValues() {
        let config = LaunchConfiguration.from(arguments: [
            "SumoGUIMac",
            "-ApplePersistenceIgnoreState",
            "YES",
            "-NSDocumentRevisionsDebugMode",
            "YES",
        ])

        XCTAssertNil(config.openURL)
    }

    func testFindsSupportedPathAfterLaunchServiceFlagValues() {
        let cwd = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        let config = LaunchConfiguration.from(
            arguments: [
                "SumoGUIMac",
                "-ApplePersistenceIgnoreState",
                "YES",
                "Examples/Tiny/tiny.net.xml",
            ],
            currentDirectoryURL: cwd
        )

        XCTAssertEqual(
            config.openURL,
            URL(fileURLWithPath: "Examples/Tiny/tiny.net.xml", relativeTo: cwd).standardizedFileURL
        )
    }

    func testIgnoresUnsupportedBarePath() {
        let config = LaunchConfiguration.from(arguments: ["SumoGUIMac", "YES"])
        XCTAssertNil(config.openURL)
    }
}
