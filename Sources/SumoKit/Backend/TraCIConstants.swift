// TraCI protocol constants used by the current client path.
// Keep this small and expand only as commands are wired up.

public enum TraCI {
    public enum Command: UInt8 {
        case getVersion              = 0x00
        case simulationStep          = 0x02
        case setOrder                = 0x03
        case close                   = 0x7F
        case load                    = 0x01

        case getSimulationVariable   = 0xAB
        case getVehicleVariable      = 0xA4
        case getEdgeVariable         = 0xAA
        case getLaneVariable         = 0xA3
        case getJunctionVariable     = 0xA9
        case getTLVariable           = 0xA2
        case getGUIVariable          = 0xAC

        case subscribeSimulation     = 0xDB
        case subscribeVehicle        = 0xD4
        case subscribeVehicleContext = 0x84
    }

    public enum DataType: UInt8 {
        case ubyte         = 0x07
        case byte          = 0x08
        case integer       = 0x09
        case double        = 0x0B
        case string        = 0x0C
        case stringList    = 0x0E
        case compound      = 0x0F
        case position2D    = 0x01
        case color         = 0x11
    }

    public enum VehicleVar: UInt8 {
        case idList    = 0x00
        case position  = 0x42
        case angle     = 0x43
        case speed     = 0x40
        case typeID    = 0x4F
    }

    public enum SimulationVar: UInt8 {
        case time           = 0x66
        case deltaT         = 0x7B
        case loadedNumber   = 0x71
        case minExpected    = 0x7D
    }
}
