public enum SumoKit {
    public static let targetSumoVersion = "1.26.0"
}

public struct SumoVersionCompatibility: Equatable, Sendable {
    public let apiVersion: Int32
    public let identifier: String
    public let targetVersion: String
    public let observedVersion: String?

    public init(apiVersion: Int32, identifier: String, targetVersion: String = SumoKit.targetSumoVersion) {
        self.apiVersion = apiVersion
        self.identifier = identifier
        self.targetVersion = targetVersion
        self.observedVersion = Self.extractVersion(from: identifier)
    }

    public var isTargetVersion: Bool {
        observedVersion == targetVersion
    }

    public var warning: String? {
        guard let observedVersion else {
            return "Could not determine SUMO version from '\(identifier)'; target is \(targetVersion)."
        }
        guard observedVersion != targetVersion else { return nil }
        return "SUMO \(observedVersion) is connected; this build targets SUMO \(targetVersion)."
    }

    private static func extractVersion(from identifier: String) -> String? {
        let marker = "SUMO "
        guard let markerRange = identifier.range(of: marker) else { return nil }
        let suffix = identifier[markerRange.upperBound...]
        let version = suffix.prefix { character in
            character.isNumber || character == "."
        }
        return version.isEmpty ? nil : String(version)
    }
}
