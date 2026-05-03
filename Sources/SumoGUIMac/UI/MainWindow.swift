import AppKit
import SwiftUI
import Charts
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
                    simulation.toggleRotateWithSelectedVehicle()
                    if !simulation.isRotatingWithSelectedVehicle {
                        viewport.resetRotation()
                    }
                } label: {
                    Label(
                        "Heading",
                        systemImage: simulation.isRotatingWithSelectedVehicle ? "location.north.line.fill" : "location.north.line"
                    )
                }
                .disabled(!simulation.isFollowingSelectedVehicle)
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

                Button {
                    simulation.presentVisualizationSettings()
                } label: {
                    Label("Visualization", systemImage: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $simulation.isVisualizationSettingsPresented) {
            VisualizationSettingsPanel()
                .environmentObject(simulation)
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
                    selectedEdgeIDs: simulation.selectedEdgeIDs,
                    selectedVehicleIDs: simulation.selectedVehicleIDs,
                    selectedRouteEdgeIDs: simulation.selectedVehicleRouteEdgeIDs,
                    hoveredRouteEdgeIDs: simulation.previewRouteEdgeIDs,
                    laneColorMode: simulation.laneColorMode,
                    vehicleColorMode: simulation.vehicleColorMode,
                    junctionColorMode: simulation.junctionColorMode,
                    laneOccupancyByID: simulation.laneOccupancyByID,
                    junctionLoadByID: simulation.junctionLoadByID,
                    showPolygons: simulation.showPolygons,
                    showPOIs: simulation.showPOIs,
                    backgroundDecal: simulation.activeBackgroundDecal,
                    palette: simulation.visualizationPalette,
                    screenshotExportRequest: simulation.screenshotExportRequest,
                    onScreenshotExportCompleted: simulation.completeScreenshotExport,
                    onVisibleWorldBoundsChanged: simulation.updateVisibleWorldBounds,
                    onVehiclePicked: simulation.selectVehicle,
                    onVehicleHovered: simulation.hoverVehicle,
                    onEdgePicked: simulation.setSelectedEdge
                )
                    .ignoresSafeArea()
                if simulation.graph == nil {
                    EmptyNetworkState()
                }
                if simulation.showLegend, simulation.graph != nil {
                    VisualizationLegend()
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            TransportBar()
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: simulation.followedVehiclePose) { _, pose in
            guard let pose else { return }
            viewport.center(on: pose.position)
            if simulation.isRotatingWithSelectedVehicle {
                viewport.setRotationDegrees(pose.angle)
            }
        }
        .onChange(of: simulation.isRotatingWithSelectedVehicle) { _, isRotating in
            guard isRotating else {
                viewport.resetRotation()
                return
            }
            if let pose = simulation.followedVehiclePose {
                viewport.setRotationDegrees(pose.angle)
            }
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
                StatRow(title: "Polygons", value: simulation.graph?.polygons.count ?? 0, icon: "hexagon")
                StatRow(title: "POIs", value: simulation.graph?.pois.count ?? 0, icon: "mappin")
            }
            if let graph = simulation.graph {
                Section("Edges") {
                    ForEach(Array(graph.edges.prefix(80).enumerated()), id: \.offset) { _, edge in
                        Button {
                            simulation.selectEdge(edge.id)
                        } label: {
                            Label(edge.id, systemImage: edgeIconName(edgeFunction: edge.function))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .listRowBackground(
                            simulation.selectedEdgeID == edge.id || simulation.selectedEdgeIDs.contains(edge.id)
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .contextMenu {
                            edgeContextMenu(edgeID: edge.id)
                        }
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
                            simulation.selectedVehicleID == vehicle.id || simulation.selectedVehicleIDs.contains(vehicle.id)
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .contextMenu {
                            vehicleContextMenu(for: vehicle)
                        }
                    }
                }
            }
        }
        .navigationTitle("Objects")
    }

    @ViewBuilder
    private func edgeContextMenu(edgeID: String) -> some View {
        Button {
            simulation.setSelectedEdge(edgeID)
        } label: {
            Label("Select Edge", systemImage: "scope")
        }

        Button {
            simulation.toggleEdgeSelection(edgeID)
        } label: {
            Label(
                simulation.selectedEdgeIDs.contains(edgeID) ? "Remove from Selection" : "Add to Selection",
                systemImage: simulation.selectedEdgeIDs.contains(edgeID) ? "minus.circle" : "plus.circle"
            )
        }

        Button {
            simulation.copyObjectID(edgeID, label: "edge")
        } label: {
            Label("Copy Edge ID", systemImage: "doc.on.doc")
        }

        Divider()

        Button {
            simulation.clearSelection()
        } label: {
            Label("Clear Selection", systemImage: "xmark.circle")
        }
        .disabled(!simulation.hasSelection)
    }

    private func edgeIconName(edgeFunction: EdgeFunction) -> String {
        edgeFunction == .internalEdge ? "arrow.triangle.turn.up.right.diamond" : "road.lanes"
    }

    @ViewBuilder
    private func vehicleContextMenu(for vehicle: VehicleSnapshot) -> some View {
        Button {
            simulation.selectVehicle(vehicle.id)
        } label: {
            Label("Select Vehicle", systemImage: "scope")
        }

        Button {
            simulation.toggleVehicleSelection(vehicle.id)
        } label: {
            Label(
                simulation.selectedVehicleIDs.contains(vehicle.id) ? "Remove from Selection" : "Add to Selection",
                systemImage: simulation.selectedVehicleIDs.contains(vehicle.id) ? "minus.circle" : "plus.circle"
            )
        }

        Button {
            if simulation.isFollowingSelectedVehicle && simulation.selectedVehicleID == vehicle.id {
                simulation.toggleFollowSelectedVehicle()
            } else {
                simulation.followVehicle(vehicle.id)
            }
        } label: {
            Label(
                simulation.isFollowingSelectedVehicle && simulation.selectedVehicleID == vehicle.id
                    ? "Stop Following Vehicle"
                    : "Follow Vehicle",
                systemImage: simulation.isFollowingSelectedVehicle && simulation.selectedVehicleID == vehicle.id
                    ? "location.slash"
                    : "location"
            )
        }

        Button {
            simulation.selectRouteForVehicle(vehicle.id)
        } label: {
            Label("Select Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
        }

        Button {
            simulation.copyRouteForVehicle(vehicle.id)
        } label: {
            Label("Copy Route Edges", systemImage: "list.bullet.clipboard")
        }

        Button {
            simulation.copyObjectID(vehicle.id, label: "vehicle")
        } label: {
            Label("Copy Vehicle ID", systemImage: "doc.on.doc")
        }

        Divider()

        Button {
            simulation.clearSelection()
        } label: {
            Label("Clear Selection", systemImage: "xmark.circle")
        }
        .disabled(!simulation.hasSelection)
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var simulation: SimulationViewModel
    @State private var selectedTab: InspectorTab = .parameters

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

            Picker("Inspector", selection: $selectedTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch selectedTab {
            case .parameters:
                ParametersInspector()
            case .subscriptions:
                SubscriptionsInspector()
            case .tracker:
                TrackerInspector()
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

private enum InspectorTab: String, CaseIterable, Identifiable {
    case parameters
    case subscriptions
    case tracker

    var id: Self { self }

    var title: String {
        switch self {
        case .parameters:
            return "Parameters"
        case .subscriptions:
            return "Subscriptions"
        case .tracker:
            return "Tracker"
        }
    }
}

private struct ParametersInspector: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                Metric("Normal edges", simulation.normalEdges)
                Metric("Internal edges", simulation.internalEdges)
                Metric("Connections", simulation.graph?.connections.count ?? 0)
                Metric("Roundabouts", simulation.graph?.roundabouts.count ?? 0)
                Metric("Polygons", simulation.graph?.polygons.count ?? 0)
                Metric("POIs", simulation.graph?.pois.count ?? 0)
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
                    Text("Waiting for next vehicle update")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let selectedEdge = simulation.selectedEdgeDetails {
                Divider()
                EdgeDetailsView(details: selectedEdge)
            }
        }
    }
}

private struct SubscriptionsInspector: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Vehicle updates", selection: $simulation.vehicleUpdateMode) {
                ForEach(VehicleUpdateMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Choose the TraCI vehicle state path")

            Text(simulation.vehicleUpdateMode.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                DetailMetric("Session", sessionText)
                DetailMetric("Vehicle mode", simulation.vehicleUpdateMode.summary)
                DetailMetric("Viewport", simulation.visibleWorldBoundsSummary)
                DetailMetric("Vehicle context", simulation.viewportSubscriptionSummary)
                DetailMetric("Selected vehicle", simulation.selectedVehicleID)
                DetailMetric("Hovered vehicle", simulation.hoveredVehicleID)
                DetailMetric("Selected edges", selectionCountText(simulation.selectedEdgeIDs.count))
                DetailMetric("Selected vehicles", selectionCountText(simulation.selectedVehicleIDs.count))
                DetailMetric("Selected route edges", routeCountText(simulation.selectedVehicleRouteEdgeIDs.count))
                DetailMetric("Hover route edges", routeCountText(simulation.hoveredVehicleRouteEdgeIDs.count))
            }

            Divider()
            BreakpointsPanel()
        }
    }

    private var sessionText: String {
        guard simulation.canRunSimulation else { return "Inactive" }
        return simulation.isExternalTraCIAttached ? "External TraCI" : "Local SUMO"
    }

    private func routeCountText(_ count: Int) -> String? {
        count == 0 ? nil : "\(count)"
    }

    private func selectionCountText(_ count: Int) -> String? {
        count == 0 ? nil : "\(count)"
    }
}

private struct TrackerInspector: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Variable", selection: $simulation.trackerVariable) {
                ForEach(SimulationViewModel.TrackerVariable.allCases) { variable in
                    Text(variable.title).tag(variable)
                }
            }
            .pickerStyle(.menu)

            if simulation.selectedTrackerSamples.isEmpty {
                Text("No tracker samples")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Chart(simulation.selectedTrackerSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.simTime),
                        y: .value(simulation.trackerVariable.axisTitle, sample.value)
                    )
                    .foregroundStyle(by: .value("Series", sample.seriesName))

                    PointMark(
                        x: .value("Time", sample.simTime),
                        y: .value(simulation.trackerVariable.axisTitle, sample.value)
                    )
                    .foregroundStyle(by: .value("Series", sample.seriesName))
                }
                .chartXAxisLabel("Simulation time (s)")
                .chartYAxisLabel(simulation.trackerVariable.axisTitle)
                .frame(height: 170)

                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                    DetailMetric("Samples", String(simulation.selectedTrackerSamples.count))
                    DetailMetric("Latest time", latestTimeText)
                    DetailMetric("Latest value", latestValueText)
                    DetailMetric("Series", latestSeriesText)
                }
            }
        }
    }

    private var latestSample: SimulationViewModel.TrackerValueSample? {
        simulation.selectedTrackerSamples.last
    }

    private var latestTimeText: String? {
        latestSample.map { String(format: "%.2fs", $0.simTime) }
    }

    private var latestValueText: String? {
        guard let latestSample else { return nil }
        return String(format: "%.2f", latestSample.value)
    }

    private var latestSeriesText: String? {
        latestSample?.seriesName
    }
}

private struct BreakpointsPanel: View {
    @EnvironmentObject private var simulation: SimulationViewModel
    @State private var breakpointText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Breakpoints", systemImage: "pause.circle")
                    .font(.headline)
                Spacer()
                Button {
                    simulation.clearBreakpoints()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(simulation.breakpoints.isEmpty)
                .help("Clear breakpoints")
            }

            HStack(spacing: 8) {
                TextField("t (s)", text: $breakpointText)
                    .textFieldStyle(.roundedBorder)
                    .monospacedDigit()
                    .onSubmit(addBreakpoint)

                Button {
                    addBreakpoint()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(parsedBreakpointTime == nil)
                .help("Add breakpoint")
            }

            if simulation.breakpoints.isEmpty {
                Text("No breakpoints")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(simulation.breakpoints) { breakpoint in
                        HStack(spacing: 8) {
                            Text(String(format: "%.2fs", breakpoint.time))
                                .monospacedDigit()
                            Spacer()
                            Button {
                                simulation.jumpToBreakpoint(breakpoint)
                            } label: {
                                Image(systemName: "forward.end")
                            }
                            .buttonStyle(.borderless)
                            .help("Run to breakpoint")
                            Button {
                                simulation.removeBreakpoint(id: breakpoint.id)
                            } label: {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove breakpoint")
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            simulation.jumpToBreakpoint(breakpoint)
                        }
                    }
                }
            }
        }
    }

    private var parsedBreakpointTime: Double? {
        let normalized = breakpointText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else {
            return nil
        }
        return value
    }

    private func addBreakpoint() {
        guard let time = parsedBreakpointTime else { return }
        if simulation.addBreakpoint(at: time) {
            breakpointText = ""
        }
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
                DetailMetric("Route edges", routeEdgesText)
                DetailMetric("Type", details.typeID)
                DetailMetric("Size", sizeText)
            }
        }
    }

    private var sizeText: String? {
        guard let length = details.length, let width = details.width else { return nil }
        return String(format: "%.1f x %.1f m", length, width)
    }

    private var routeEdgesText: String? {
        guard details.routeEdgeIDs.isEmpty == false else { return nil }
        if details.routeEdgeIDs.count <= 6 {
            return details.routeEdgeIDs.joined(separator: " -> ")
        }
        let prefix = details.routeEdgeIDs.prefix(4).joined(separator: " -> ")
        return "\(details.routeEdgeIDs.count) edges: \(prefix) -> ..."
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

private struct VisualizationSettingsPanel: View {
    @EnvironmentObject private var simulation: SimulationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: VisualizationSettingsTab = .background

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Section", selection: $selectedTab) {
                    ForEach(VisualizationSettingsTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding([.horizontal, .top], 18)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                switch selectedTab {
                case .background:
                    BackgroundSettingsTab()
                case .streets:
                    StreetsSettingsTab()
                case .vehicles:
                    VehiclesSettingsTab()
                case .persons:
                    EmptySettingsTab(title: "Persons", icon: "figure.walk")
                case .containers:
                    EmptySettingsTab(title: "Containers", icon: "shippingbox")
                case .junctions:
                    JunctionSettingsTab()
                case .detectors:
                    EmptySettingsTab(title: "Detectors", icon: "sensor")
                case .pois:
                    POISettingsTab()
                case .legend:
                    LegendSettingsTab()
                }
            }
            .frame(minHeight: 360)

            Divider()

            HStack {
                Button {
                    simulation.presentImportVisualizationSettingsPanel()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    simulation.presentExportVisualizationSettingsPanel()
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(18)
        }
        .frame(width: 720, height: 560)
    }
}

private enum VisualizationSettingsTab: String, CaseIterable, Identifiable {
    case background
    case streets
    case vehicles
    case persons
    case containers
    case junctions
    case detectors
    case pois
    case legend

    var id: Self { self }

    var title: String {
        switch self {
        case .background: return "Background"
        case .streets: return "Streets"
        case .vehicles: return "Vehicles"
        case .persons: return "Persons"
        case .containers: return "Containers"
        case .junctions: return "Junctions"
        case .detectors: return "Detectors"
        case .pois: return "POIs"
        case .legend: return "Legend"
        }
    }

    var icon: String {
        switch self {
        case .background: return "photo"
        case .streets: return "road.lanes"
        case .vehicles: return "car.side"
        case .persons: return "figure.walk"
        case .containers: return "shippingbox"
        case .junctions: return "point.topleft.down.curvedto.point.bottomright.up"
        case .detectors: return "sensor"
        case .pois: return "mappin"
        case .legend: return "list.bullet.rectangle"
        }
    }
}

private struct BackgroundSettingsTab: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        SettingsSection {
            Toggle("Show Background", isOn: $simulation.showBackground)

            HStack {
                Text(simulation.backgroundImageURL?.lastPathComponent ?? "No image selected")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    simulation.presentBackgroundImagePanel()
                } label: {
                    Label("Choose", systemImage: "photo.badge.plus")
                }
                Button {
                    simulation.clearBackgroundImage()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(simulation.backgroundImageURL == nil)
            }

            Slider(value: $simulation.backgroundOpacity, in: 0...1)
                .help("Background opacity")

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Min X")
                    worldRectField(index: 0)
                    Text("Min Y")
                    worldRectField(index: 1)
                }
                GridRow {
                    Text("Max X")
                    worldRectField(index: 2)
                    Text("Max Y")
                    worldRectField(index: 3)
                }
            }
        }
    }

    private func worldRectField(index: Int) -> some View {
        TextField(
            "",
            value: Binding<Double>(
                get: { Double(component(index)) },
                set: { simulation.setBackgroundWorldRectComponent(index, value: Float($0)) }
            ),
            format: .number.precision(.fractionLength(2))
        )
        .textFieldStyle(.roundedBorder)
        .monospacedDigit()
        .frame(width: 96)
    }

    private func component(_ index: Int) -> Float {
        switch index {
        case 0: return simulation.backgroundWorldRect.x
        case 1: return simulation.backgroundWorldRect.y
        case 2: return simulation.backgroundWorldRect.z
        default: return simulation.backgroundWorldRect.w
        }
    }
}

private struct StreetsSettingsTab: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        SettingsSection {
            Picker("Color", selection: $simulation.laneColorMode) {
                ForEach(LaneColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            ColorPicker("Uniform Color", selection: paletteBinding(\.laneUniform))
            Toggle("Show Polygons", isOn: $simulation.showPolygons)
            ColorPicker("Polygon Fill", selection: paletteBinding(\.polygonFill), supportsOpacity: true)
        }
    }

    private func paletteBinding(_ keyPath: WritableKeyPath<VisualizationPalette, VisualizationColor>) -> Binding<Color> {
        Binding(
            get: { Color(visualizationColor: simulation.visualizationPalette[keyPath: keyPath]) },
            set: { simulation.visualizationPalette[keyPath: keyPath] = VisualizationColor(color: $0) }
        )
    }
}

private struct VehiclesSettingsTab: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        SettingsSection {
            Picker("Color", selection: $simulation.vehicleColorMode) {
                ForEach(VehicleColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            ColorPicker("Uniform Color", selection: paletteBinding(\.vehicleUniform))
        }
    }

    private func paletteBinding(_ keyPath: WritableKeyPath<VisualizationPalette, VisualizationColor>) -> Binding<Color> {
        Binding(
            get: { Color(visualizationColor: simulation.visualizationPalette[keyPath: keyPath]) },
            set: { simulation.visualizationPalette[keyPath: keyPath] = VisualizationColor(color: $0) }
        )
    }
}

private struct JunctionSettingsTab: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        SettingsSection {
            Picker("Color", selection: $simulation.junctionColorMode) {
                ForEach(JunctionColorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            ColorPicker("Uniform Color", selection: paletteBinding(\.junctionUniform))
        }
    }

    private func paletteBinding(_ keyPath: WritableKeyPath<VisualizationPalette, VisualizationColor>) -> Binding<Color> {
        Binding(
            get: { Color(visualizationColor: simulation.visualizationPalette[keyPath: keyPath]) },
            set: { simulation.visualizationPalette[keyPath: keyPath] = VisualizationColor(color: $0) }
        )
    }
}

private struct POISettingsTab: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        SettingsSection {
            Toggle("Show POIs", isOn: $simulation.showPOIs)
            ColorPicker("POI Color", selection: Binding(
                get: { Color(visualizationColor: simulation.visualizationPalette.poi) },
                set: { simulation.visualizationPalette.poi = VisualizationColor(color: $0) }
            ))
        }
    }
}

private struct LegendSettingsTab: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        SettingsSection {
            Toggle("Show Legend", isOn: $simulation.showLegend)
            ColorPicker("Background Tint", selection: Binding(
                get: { Color(visualizationColor: simulation.visualizationPalette.backgroundTint) },
                set: { simulation.visualizationPalette.backgroundTint = VisualizationColor(color: $0) }
            ), supportsOpacity: true)
        }
    }
}

private struct EmptySettingsTab: View {
    let title: String
    let icon: String

    var body: some View {
        SettingsSection {
            Label(title, systemImage: icon)
                .font(.headline)
            Toggle("Visible", isOn: .constant(false))
                .disabled(true)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct VisualizationLegend: View {
    @EnvironmentObject private var simulation: SimulationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LegendRow(color: simulation.visualizationPalette.laneUniform, title: "Lanes", value: simulation.laneColorMode.title)
            LegendRow(color: simulation.visualizationPalette.vehicleUniform, title: "Vehicles", value: simulation.vehicleColorMode.title)
            LegendRow(color: simulation.visualizationPalette.junctionUniform, title: "Junctions", value: simulation.junctionColorMode.title)
            if simulation.showPolygons {
                LegendRow(color: simulation.visualizationPalette.polygonFill, title: "Polygons", value: "Visible")
            }
            if simulation.showPOIs {
                LegendRow(color: simulation.visualizationPalette.poi, title: "POIs", value: "Visible")
            }
        }
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LegendRow: View {
    let color: VisualizationColor
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(visualizationColor: color))
                .frame(width: 14, height: 10)
            Text(title)
                .font(.caption)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Picker("Lane Coloring Scheme", selection: $simulation.laneColorMode) {
                    ForEach(LaneColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label("Lane Coloring", systemImage: "road.lanes")
            }
            .help("Lane coloring scheme")

            Menu {
                Picker("Vehicle Coloring Scheme", selection: $simulation.vehicleColorMode) {
                    ForEach(VehicleColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label("Vehicle Coloring", systemImage: "car.side")
            }
            .help("Vehicle coloring scheme")

            Menu {
                Picker("Junction Coloring Scheme", selection: $simulation.junctionColorMode) {
                    ForEach(JunctionColorMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } label: {
                Label("Junction Coloring", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .help("Junction coloring scheme")

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

private extension Color {
    init(visualizationColor: VisualizationColor) {
        self.init(
            red: Double(visualizationColor.red),
            green: Double(visualizationColor.green),
            blue: Double(visualizationColor.blue),
            opacity: Double(visualizationColor.alpha)
        )
    }
}

private extension VisualizationColor {
    init(color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        self.init(
            red: Float(nsColor.redComponent),
            green: Float(nsColor.greenComponent),
            blue: Float(nsColor.blueComponent),
            alpha: Float(nsColor.alphaComponent)
        )
    }
}
