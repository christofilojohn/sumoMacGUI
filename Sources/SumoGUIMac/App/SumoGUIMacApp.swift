import SwiftUI

@main
struct SumoGUIMacApp: App {
    @StateObject private var simulation: SimulationViewModel
    @StateObject private var viewport = ViewportState()

    init() {
        let launchConfiguration = LaunchConfiguration.from(arguments: CommandLine.arguments)
        _simulation = StateObject(wrappedValue: SimulationViewModel(initialOpenURL: launchConfiguration.openURL))
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(simulation)
                .environmentObject(viewport)
                .task {
                    simulation.performInitialLoadIfNeeded()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    simulation.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    if simulation.recentDocuments.isEmpty {
                        Button("No Recent SUMO Files") {}
                            .disabled(true)
                    } else {
                        ForEach(simulation.recentDocuments) { document in
                            Button(document.title) {
                                simulation.openRecentDocument(document)
                            }
                            .help(document.location)
                        }

                        Divider()

                        Button("Clear Menu") {
                            simulation.clearRecentDocuments()
                        }
                    }
                }

                Button("Attach to TraCI...") {
                    simulation.presentAttachPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                Button("Export Screenshot...") {
                    simulation.presentScreenshotPanel()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(simulation.graph == nil)

                Divider()

                Button("Import Visualization Settings...") {
                    simulation.presentImportVisualizationSettingsPanel()
                }

                Button("Export Visualization Settings...") {
                    simulation.presentExportVisualizationSettingsPanel()
                }
            }
            CommandMenu("View") {
                Button("Visualization Settings...") {
                    simulation.presentVisualizationSettings()
                }
                .keyboardShortcut(",", modifiers: .command)

                Divider()

                Button("Fit Network") {
                    viewport.requestFit()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(simulation.graph == nil)

                Divider()

                Button("Zoom In") {
                    viewport.zoomIn()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(simulation.graph == nil)

                Button("Zoom Out") {
                    viewport.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(simulation.graph == nil)

                Divider()

                Button(simulation.isFollowingSelectedVehicle ? "Stop Following Vehicle" : "Follow Selected Vehicle") {
                    simulation.toggleFollowSelectedVehicle()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!simulation.canFollowSelectedVehicle)
            }
            CommandMenu("Simulation") {
                Button(simulation.isPlaying ? "Pause" : "Play") {
                    simulation.togglePlayPause()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!simulation.canRunSimulation)

                Button("Step") {
                    simulation.stepOnce()
                }
                .keyboardShortcut("s", modifiers: [])
                .disabled(!simulation.canRunSimulation)

                Button("Stop") {
                    Task {
                        await simulation.stop()
                    }
                }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!simulation.canRunSimulation)
            }
        }
    }
}
