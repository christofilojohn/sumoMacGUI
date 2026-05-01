import Foundation

struct LaunchConfiguration: Equatable {
    let openURL: URL?

    static func from(arguments: [String], currentDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) -> LaunchConfiguration {
        let args = Array(arguments.dropFirst())
        var iterator = args.makeIterator()
        var openPath: String?

        while let arg = iterator.next() {
            switch arg {
            case "-c", "--config":
                openPath = iterator.next()
            case let path where !path.hasPrefix("-") && openPath == nil:
                openPath = path
            default:
                continue
            }
        }

        guard let openPath else {
            return LaunchConfiguration(openURL: nil)
        }

        let url = URL(fileURLWithPath: openPath, relativeTo: currentDirectoryURL).standardizedFileURL
        return LaunchConfiguration(openURL: url)
    }
}
