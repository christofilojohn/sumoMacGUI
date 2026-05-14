import Foundation

public struct SumoLauncher {
    public var binaryPath: URL
    public var extraArgs: [String]

    public init(binaryPath: URL, extraArgs: [String] = []) {
        self.binaryPath = binaryPath
        self.extraArgs = extraArgs
    }

    public static func locateBinary() -> URL? {
        locateTool(named: "sumo")
    }

    public static func locateTool(named executableName: String) -> URL? {
        if let path = executableInPATH(named: executableName) {
            return path
        }
        if let sumoHome = ProcessInfo.processInfo.environment["SUMO_HOME"] {
            let root = URL(fileURLWithPath: sumoHome)
            let candidates = [
                root.appendingPathComponent("bin").appendingPathComponent(executableName),
                root.deletingLastPathComponent().appendingPathComponent("bin").appendingPathComponent(executableName),
                root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("bin").appendingPathComponent(executableName),
            ]
            for path in candidates where FileManager.default.isExecutableFile(atPath: path.path) {
                return path
            }
        }
        let candidates = [
            "/Library/Frameworks/EclipseSUMO.framework/Versions/Current/EclipseSUMO/bin/\(executableName)",
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func executableInPATH(named executableName: String) -> URL? {
        guard executableName.contains("/") == false else { return nil }
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory)).appendingPathComponent(executableName)
            if FileManager.default.isExecutableFile(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    public final class Handle {
        public let process: Process
        public let port: Int
        let stderrPipe: Pipe

        init(process: Process, port: Int, stderrPipe: Pipe) {
            self.process = process
            self.port = port
            self.stderrPipe = stderrPipe
        }

        public func terminate() {
            if process.isRunning { process.terminate() }
        }

        public func readAvailableStderr() -> String {
            let data = stderrPipe.fileHandleForReading.availableData
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    public func launch(config: URL, port: Int? = nil) throws -> Handle {
        let chosenPort = port ?? Self.findFreePort()
        let proc = Process()
        proc.executableURL = binaryPath
        proc.currentDirectoryURL = config.deletingLastPathComponent()
        proc.arguments = Self.arguments(config: config, port: chosenPort, extraArgs: extraArgs)

        let stderr = Pipe()
        proc.standardError = stderr
        proc.standardOutput = Pipe()

        do { try proc.run() } catch {
            throw TraCIError.launchFailed(error.localizedDescription)
        }
        return Handle(process: proc, port: chosenPort, stderrPipe: stderr)
    }

    static func arguments(config: URL, port: Int, extraArgs: [String]) -> [String] {
        [
            "--remote-port", String(port),
            "-c", config.path,
            "--no-step-log",
            "--no-warnings",
        ] + extraArgs
    }

    static func findFreePort() -> Int {
        let s = socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(s) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian
        addr.sin_port = 0
        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(s, $0, len) }
        }
        var bound = sockaddr_in()
        var l = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.getsockname(s, $0, &l) }
        }
        return Int(UInt16(bigEndian: bound.sin_port))
    }
}
