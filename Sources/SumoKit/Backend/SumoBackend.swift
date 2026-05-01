import Foundation

public protocol SumoBackend: AnyObject, Sendable {
    func open(config: URL) async throws
    func step(_ count: Int) async throws
    func close() async

    var liveState: AsyncStream<SimulationState> { get }

    var simulation: SimulationDomain { get }
    var vehicle: VehicleDomain { get }
    var edge: EdgeDomain { get }
    var lane: LaneDomain { get }
    var junction: JunctionDomain { get }
    var trafficLight: TrafficLightDomain { get }
    var gui: GUIDomain { get }
}

public protocol SimulationDomain: Sendable {
    func currentTime() async throws -> Double
    func deltaT() async throws -> Double
    func loadedVehicleCount() async throws -> Int
}

public protocol VehicleDomain: Sendable {
    func ids() async throws -> [String]
    func position(of id: String) async throws -> SIMD2<Double>
    func angle(of id: String) async throws -> Double
    func speed(of id: String) async throws -> Double
}

public protocol EdgeDomain: Sendable { func ids() async throws -> [String] }
public protocol LaneDomain: Sendable { func ids() async throws -> [String] }
public protocol JunctionDomain: Sendable { func ids() async throws -> [String] }
public protocol TrafficLightDomain: Sendable { func ids() async throws -> [String] }
public protocol GUIDomain: Sendable { func screenshot(view: String, file: URL) async throws }
