import SwiftUI
import SumoKit

struct MainWindow: View {
    @EnvironmentObject private var simulation: SimulationViewModel
    @EnvironmentObject private var viewport: ViewportState

    var body: some View {
        NavigationSplitView {
            ObjectSidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } content: {
            NetworkWorkspace(viewport: viewport)
                .navigationSplitViewColumnWidth(min: 520, ideal: 860)
        } detail: {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .frame(minWidth: 1040, minHeight: 680)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    simulation.presentOpenPanel()
                } label: {
                    Label("Open", systemImage: "folder")
                }
                Button {
                    simulation.presentAttachPanel()
                } label: {
                    Label("Attach", systemImage: "link")
                }
                Button {
                    viewport.requestFit()
                } label: {
                    Label("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .disabled(simulation.graph == nil)
                Button {
                    simulation.toggleFollowSelectedVehicle()
                } label: {
                    Label("Follow", systemImage: simulation.isFollowingSelectedVehicle ? "location.fill" : "location")
                }
                .disabled(!simulation.canFollowSelectedVehicle)
                Button {
                    viewport.zoomIn()
                } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                .disabled(simulation.graph == nil)
                Button {
                    viewport.zoomOut()
                } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
                .disabled(simulation.graph == nil)
                Button {
                    simulation.togglePlayPause()
                } label: {
                    Label(simulation.isPlaying ? "Pause" : "Play",
                          systemImage: simulation.isPlaying ? "pause.fill" : "play.fill")
                }
                .disabled(!simulation.canRunSimulation)
                Button {
                    simulation.stepOnce()
                } label: {
                    Label("Step", systemImage: "forward.frame.fill")
                }
                .disabled(!simulation.canRunSimulation)
            }
            ToolbarItemGroup {
                Button {
                    simulation.presentScreenshotPanel()
                } label: {
                    Label("Screenshot", systemImage: "camera")
                }
                .disabled(simulation.graph == nil)
            }
        }
    }
}

private struct NetworkWorkspace: View {
    @EnvironmentObject private var simulation: SimulationViewModel
    let viewport: ViewportState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NetworkView(
                    graph: simulation.graph,
                    simulationState: simulation.liveState,
                    viewport: viewport,
                    selectedEdgeID: simulation.selectedEdgeID,
                    selectedVehicleID: simulation.selectedVehicleID,
                    laneColorMode: simulation.laneColorMode,
                    vehicleColorMode: simulation.vehicleColorMode,
                    screenshotExportRequest: simulation.screenshotExportRequest,
                    onScreenshotExportCompleted: simulation.completeScreenshotExport,
                    onVisibleWorldBoundsChanged: simulation.updateVisibleWorldBounds,
                    onVehiclePicked: simulation.selectVehicle,
                    onEdgePicked: simulation.setSelectedEdge
                )
                    .ignoresSafeArea()
                if simulation.graph == nil {
                    EmptyNetworkState()
                }
            }
            TransportBar()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: simulation.followedVehiclePosition) { _, position in
            guard let position else { return }
            viewport.center(on: position)
        }
    }
}

private struct EmptyNetworkState: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    simulation.presentOpenPanel()
                } label: {
                    Label("Open SUMO Configuration", systemImage: "folder.badge.plus")
                        .font(.title3)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    simulation.presentAttachPanel()
                } label: {
                    Label("Attach to TraCI", systemImage: "link")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }

            Text("Open a .sumocfg or .net.xml file to inspect its network.")
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}

private struct ObjectSidebar: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        List {
            Section("Network") {
                StatRow(title: "Edges", value: simulation.graph?.edges.count ?? 0, icon: "road.lanes")
                StatRow(title: "Lanes", value: simulation.graph?.lanes.count ?? 0, icon: "line.diagonal")
                StatRow(title: "Junctions", value: simulation.graph?.junctions.count ?? 0, icon: "point.topleft.down.curvedto.point.bottomright.up")
                StatRow(title: "TLS", value: simulation.graph?.tlLogics.count ?? 0, icon: "light.beacon.max")
            }
            if let graph = simulation.graph {
                Section("Edges") {
                    ForEach(Array(graph.edges.prefix(80).enumerated()), id: \.offset) { _, edge in
                        Button {
                            simulation.selectEdge(edge.id)
                        } label: {
                            Label(edge.id, systemImage: edge.function == .internalEdge ? "arrow.triangle.turn.up.right.diamond" : "road.lanes")
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowBackground(
                            simulation.selectedEdgeID == edge.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                    }
                }
            }
            if simulation.liveState.vehicles.isEmpty == false {
                Section("Live Vehicles") {
                    ForEach(Array(simulation.liveState.vehicles.prefix(80))) { vehicle in
                        Button {
                            simulation.selectVehicle(vehicle.id)
                        } label: {
                            HStack {
                                Label(vehicle.id, systemImage: "car.side")
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.1f m/s", vehicle.speed))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowBackground(
                            simulation.selectedVehicleID == vehicle.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                    }
                }
            }
        }
        .navigationTitle("Objects")
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(simulation.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(simulation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                Metric("Normal edges", simulation.normalEdges)
                Metric("Internal edges", simulation.internalEdges)
                Metric("Connections", simulation.graph?.connections.count ?? 0)
                Metric("Roundabouts", simulation.graph?.roundabouts.count ?? 0)
                Metric("Vehicles", simulation.liveState.vehicles.count)
            }

            if let selected = simulation.liveState.selectedVehicle {
                Divider()
                VehicleDetailsView(details: selected)
            } else if let selectedVehicleID = simulation.selectedVehicleID {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedVehicleID)
                        .font(.headline)
                    Text("Waiting for next subscription update")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let selectedEdge = simulation.selectedEdgeDetails {
                Divider()
                EdgeDetailsView(details: selectedEdge)
            }

            if case .failed(let message) = simulation.loadState {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Spacer()
        }
        .padding(18)
        .navigationTitle("Inspector")
    }
}

private struct VehicleDetailsView: View {
    let details: VehicleDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(details.id)
                .font(.headline)
                .lineLimit(2)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                DetailMetric("Speed", details.speed.map { String(format: "%.2f m/s", $0) })
                DetailMetric("Accel", details.acceleration.map { String(format: "%.2f m/s2", $0) })
                DetailMetric("Lane pos", details.lanePosition.map { String(format: "%.2f m", $0) })
                DetailMetric("Angle", details.angle.map { String(format: "%.1f deg", $0) })
                DetailMetric("Edge", details.edgeID)
                DetailMetric("Lane", details.laneID)
                DetailMetric("Route", details.routeID)
                DetailMetric("Type", details.typeID)
                DetailMetric("Size", sizeText)
            }
        }
    }

    private var sizeText: String? {
        guard let length = details.length, let width = details.width else { return nil }
        return String(format: "%.1f x %.1f m", length, width)
    }
}

private struct EdgeDetailsView: View {
    let details: SimulationViewModel.SelectedEdgeDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(details.id)
                .font(.headline)
                .lineLimit(2)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                DetailMetric("Function", details.function)
                DetailMetric("From", details.fromJunction)
                DetailMetric("To", details.toJunction)
                DetailMetric("Priority", String(details.priority))
                DetailMetric("Lanes", String(details.laneCount))
                DetailMetric("Connections", String(details.connectionCount))
                DetailMetric("Speed", speedText)
                DetailMetric("Length", lengthText)
                DetailMetric("Bounds", boundsText)
            }
        }
    }

    private var speedText: String? {
        guard let speed = details.speed, speed.isFinite else { return nil }
        return String(format: "%.2f m/s", speed)
    }

    private var lengthText: String? {
        guard let length = details.length else { return nil }
        guard length.isFinite, length > 0 else { return nil }
        return String(format: "%.1f m", length)
    }

    private var boundsText: String? {
        guard let bounds = details.bounds else { return nil }
        return String(format: "%.0f, %.0f - %.0f, %.0f", bounds.x, bounds.y, bounds.z, bounds.w)
    }
}

private struct DetailMetric: View {
    let title: String
    let value: String?

    init(_ title: String, _ value: String?) {
        self.title = title
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value ?? "-")
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

private struct TransportBar: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        HStack(spacing: 14) {
            Button {
                simulation.togglePlayPause()
            } label: {
                Image(systemName: simulation.isPlaying ? "pause.fill" : "play.fill")
            }
            .disabled(!simulation.canRunSimulation)
            .help(simulation.isPlaying ? "Pause" : "Play")

            Button {
                Task {
                    await simulation.stop()
                }
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(!simulation.canRunSimulation)
            .help("Stop")

            Button {
                simulation.stepOnce()
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .disabled(!simulation.canRunSimulation)
            .help("Step")

            Button {
                simulation.toggleFollowSelectedVehicle()
            } label: {
                Image(systemName: simulation.isFollowingSelectedVehicle ? "location.fill" : "location")
            }
            .disabled(!simulation.canFollowSelectedVehicle)
            .help("Follow selected vehicle")

            Menu {
                Picker("Lane Color", selection: $simulation.laneColorMode) {
                    ForEach(LaneColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "road.lanes")
            }
            .help("Lane color mode")

            Menu {
                Picker("Vehicle Color", selection: $simulation.vehicleColorMode) {
                    ForEach(VehicleColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Image(systemName: "car.side")
            }
            .help("Vehicle color mode")

            Slider(value: $simulation.stepDelay, in: 0.02...1.0)
                .frame(width: 130)
                .disabled(!simulation.canRunSimulation || simulation.isExternalTraCIAttached)
                .help("Delay between simulation steps")

            Text(delayText)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 20)

            Text(simTimeText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 82, alignment: .leading)

            Text(speedFactorText)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 64, alignment: .leading)

            Spacer()

            StatusText()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(.bar)
    }

    private var delayText: String {
        if simulation.isExternalTraCIAttached {
            return "external sync"
        }
        return String(format: "%.2fs delay", simulation.stepDelay)
    }

    private var simTimeText: String {
        String(format: "t %.2fs", simulation.liveState.simTime)
    }

    private var speedFactorText: String {
        guard simulation.playbackSpeedFactor > 0 else { return "0.0x" }
        return String(format: "%.1fx", simulation.playbackSpeedFactor)
    }
}

private struct StatusText: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        switch simulation.loadState {
        case .empty:
            Text("Ready")
                .foregroundStyle(.secondary)
        case .loading(let name):
            ProgressView()
                .controlSize(.small)
            Text("Loading \(name)")
                .foregroundStyle(.secondary)
        case .ready:
            Text("Network loaded")
                .foregroundStyle(.secondary)
        case .failed:
            Text("Load failed")
                .foregroundStyle(.red)
        }
    }
}

private struct StatRow: View {
    let title: String
    let value: Int
    let icon: String

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text(value, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}

private struct Metric: View {
    let title: String
    let value: Int

    init(_ title: String, _ value: Int) {
        self.title = title
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .monospacedDigit()
        }
    }
}
