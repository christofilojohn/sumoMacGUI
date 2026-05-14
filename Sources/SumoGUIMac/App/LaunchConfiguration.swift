import Foundation

struct LaunchConfiguration: Equatable {
    let openURL: URL?
    let traciPort: Int?
    let traciClientOrder: Int32

    static func from(arguments: [String], currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> LaunchConfiguration {
        let args = Array(arguments.dropFirst())
        var iterator = args.makeIterator()
        var openPath: String?
        var traciPort: Int?
        var traciClientOrder: Int32 = 2

        while let arg = iterator.next() {
            switch arg {
            case "-c", "--config":
                if let next = iterator.next(), isSupportedInputPath(next) {
                    openPath = next
                }
            case "--traci-port":
                if let next = iterator.next(), let port = Int(next), (1...65_535).contains(port) {
                    traciPort = port
                }
            case "--traci-order":
                if let next = iterator.next(), let order = Int32(next) {
                    traciClientOrder = order
                }
            case let path where !path.hasPrefix("-") && openPath == nil && isSupportedInputPath(path):
                openPath = path
            default:
                continue
            }
        }

        guard let openPath else {
            return LaunchConfiguration(openURL: nil, traciPort: traciPort, traciClientOrder: traciClientOrder)
        }

        let url = URL(fileURLWithPath: openPath, relativeTo: currentDirectoryURL).standardizedFileURL
        return LaunchConfiguration(openURL: url, traciPort: traciPort, traciClientOrder: traciClientOrder)
    }

    private static func isSupportedInputPath(_ path: String) -> Bool {
        let filename = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        return filename.hasSuffix(".sumocfg") || filename.hasSuffix(".net.xml")
    }
}
