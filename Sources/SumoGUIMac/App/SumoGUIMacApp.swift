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

                Button("Attach to TraCI...") {
                    simulation.presentAttachPanel()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
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
