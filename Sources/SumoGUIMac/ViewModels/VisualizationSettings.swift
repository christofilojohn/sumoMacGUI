import Foundation
import SumoKit

enum LaneColorMode: String, CaseIterable, Identifiable {
    case speedLimit
    case laneNumber
    case occupancy
    case edgeType
    case uniform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speedLimit:
            return "By Allowed Speed"
        case .laneNumber:
            return "By Lane Number"
        case .occupancy:
            return "By Occupancy"
        case .edgeType:
            return "By Edge Type"
        case .uniform:
            return "Uniform"
        }
    }
}

enum VehicleColorMode: String, CaseIterable, Identifiable {
    case speed
    case acceleration
    case route
    case type
    case co2
    case colorAttribute
    case uniform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speed:
            return "By Speed"
        case .acceleration:
            return "By Acceleration"
        case .route:
            return "By Route"
        case .type:
            return "By Type"
        case .co2:
            return "By CO2"
        case .colorAttribute:
            return "By Color Attribute"
        case .uniform:
            return "Uniform"
        }
    }
}

enum JunctionColorMode: String, CaseIterable, Identifiable {
    case type
    case load
    case uniform

    var id: String { rawValue }

    var title: String {
        switch self {
        case .type:
            return "By Type"
        case .load:
            return "By Load"
        case .uniform:
            return "Uniform"
        }
    }
}

struct VisualizationColor: Equatable, Sendable {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = red.clamped01
        self.green = green.clamped01
        self.blue = blue.clamped01
        self.alpha = alpha.clamped01
    }

    init(sumoColor: SumoColor) {
        self.init(
            red: Float(sumoColor.red) / 255,
            green: Float(sumoColor.green) / 255,
            blue: Float(sumoColor.blue) / 255,
            alpha: Float(sumoColor.alpha) / 255
        )
    }

    var simd: SIMD4<Float> {
        SIMD4(red, green, blue, alpha)
    }

    var sumoString: String {
        let channels = [red, green, blue, alpha].map {
            String(Int(($0.clamped01 * 255).rounded()))
        }
        return channels.joined(separator: ",")
    }

    static func parse(_ value: String?) -> VisualizationColor? {
        guard let value else { return nil }
        let parts = value.split(separator: ",")
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let channels = parts.map { Float($0.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 }
        let scale: Float = channels.contains { $0 > 1 } ? 255 : 1
        return VisualizationColor(
            red: channels[0] / scale,
            green: channels[1] / scale,
            blue: channels[2] / scale,
            alpha: channels.count == 4 ? channels[3] / scale : 1
        )
    }
}

struct VisualizationPalette: Equatable, Sendable {
    var laneUniform = VisualizationColor(red: 0.58, green: 0.62, blue: 0.66)
    var vehicleUniform = VisualizationColor(red: 0.30, green: 0.72, blue: 0.88)
    var junctionUniform = VisualizationColor(red: 0.24, green: 0.27, blue: 0.30)
    var polygonFill = VisualizationColor(red: 0.28, green: 0.46, blue: 0.66, alpha: 0.42)
    var poi = VisualizationColor(red: 0.97, green: 0.74, blue: 0.25)
    var backgroundTint = VisualizationColor(red: 1, green: 1, blue: 1, alpha: 1)
}

struct BackgroundDecal: Equatable, Sendable {
    var url: URL
    var worldRect: SIMD4<Float>
    var opacity: Float
}

struct VisualizationSettingsSnapshot: Equatable, Sendable {
    var laneColorMode: LaneColorMode = .speedLimit
    var vehicleColorMode: VehicleColorMode = .speed
    var junctionColorMode: JunctionColorMode = .type
    var showPolygons = true
    var showPOIs = true
    var showBackground = true
    var showLegend = true
    var backgroundPath: String?
    var backgroundWorldRect = SIMD4<Float>(0, 0, 1, 1)
    var backgroundOpacity: Float = 0.65
    var palette = VisualizationPalette()

    func xmlData() -> Data {
        let backgroundPathAttribute = backgroundPath.map { " file=\"\(Self.escape($0))\"" } ?? ""
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <viewsettings>
          <streets colorMode="\(laneColorMode.rawValue)"/>
          <vehicles colorMode="\(vehicleColorMode.rawValue)"/>
          <junctions colorMode="\(junctionColorMode.rawValue)"/>
          <polygons enabled="\(showPolygons)"/>
          <pois enabled="\(showPOIs)"/>
          <legend enabled="\(showLegend)"/>
          <background enabled="\(showBackground)"\(backgroundPathAttribute) opacity="\(backgroundOpacity)" xMin="\(backgroundWorldRect.x)" yMin="\(backgroundWorldRect.y)" xMax="\(backgroundWorldRect.z)" yMax="\(backgroundWorldRect.w)"/>
          <palette>
            <color key="laneUniform" value="\(palette.laneUniform.sumoString)"/>
            <color key="vehicleUniform" value="\(palette.vehicleUniform.sumoString)"/>
            <color key="junctionUniform" value="\(palette.junctionUniform.sumoString)"/>
            <color key="polygonFill" value="\(palette.polygonFill.sumoString)"/>
            <color key="poi" value="\(palette.poi.sumoString)"/>
            <color key="backgroundTint" value="\(palette.backgroundTint.sumoString)"/>
          </palette>
        </viewsettings>
        """
        return Data(xml.utf8)
    }

    static func parse(data: Data) throws -> VisualizationSettingsSnapshot {
        let parser = XMLParser(data: data)
        let delegate = VisualizationSettingsXMLParser()
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw delegate.error ?? parser.parserError ?? CocoaError(.fileReadCorruptFile)
        }
        return delegate.snapshot
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class VisualizationSettingsXMLParser: NSObject, XMLParserDelegate {
    var snapshot = VisualizationSettingsSnapshot()
    var error: Error?

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "streets":
            if let value = attributeDict["colorMode"], let mode = LaneColorMode(rawValue: value) {
                snapshot.laneColorMode = mode
            }
        case "vehicles":
            if let value = attributeDict["colorMode"], let mode = VehicleColorMode(rawValue: value) {
                snapshot.vehicleColorMode = mode
            }
        case "junctions":
            if let value = attributeDict["colorMode"], let mode = JunctionColorMode(rawValue: value) {
                snapshot.junctionColorMode = mode
            }
        case "polygons":
            snapshot.showPolygons = parseBool(attributeDict["enabled"], defaultValue: snapshot.showPolygons)
        case "pois":
            snapshot.showPOIs = parseBool(attributeDict["enabled"], defaultValue: snapshot.showPOIs)
        case "legend":
            snapshot.showLegend = parseBool(attributeDict["enabled"], defaultValue: snapshot.showLegend)
        case "background":
            snapshot.showBackground = parseBool(attributeDict["enabled"], defaultValue: snapshot.showBackground)
            snapshot.backgroundPath = attributeDict["file"]
            snapshot.backgroundOpacity = Float(attributeDict["opacity"] ?? "") ?? snapshot.backgroundOpacity
            let xMin = Float(attributeDict["xMin"] ?? "") ?? snapshot.backgroundWorldRect.x
            let yMin = Float(attributeDict["yMin"] ?? "") ?? snapshot.backgroundWorldRect.y
            let xMax = Float(attributeDict["xMax"] ?? "") ?? snapshot.backgroundWorldRect.z
            let yMax = Float(attributeDict["yMax"] ?? "") ?? snapshot.backgroundWorldRect.w
            snapshot.backgroundWorldRect = SIMD4(xMin, yMin, xMax, yMax)
        case "color":
            guard
                let key = attributeDict["key"],
                let color = VisualizationColor.parse(attributeDict["value"])
            else {
                return
            }
            switch key {
            case "laneUniform":
                snapshot.palette.laneUniform = color
            case "vehicleUniform":
                snapshot.palette.vehicleUniform = color
            case "junctionUniform":
                snapshot.palette.junctionUniform = color
            case "polygonFill":
                snapshot.palette.polygonFill = color
            case "poi":
                snapshot.palette.poi = color
            case "backgroundTint":
                snapshot.palette.backgroundTint = color
            default:
                break
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }

    private func parseBool(_ value: String?, defaultValue: Bool) -> Bool {
        guard let value else { return defaultValue }
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return defaultValue
        }
    }
}

private extension Float {
    var clamped01: Float {
        max(0, min(self, 1))
    }
}
