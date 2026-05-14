import SwiftUI

@main
struct SumoGUIMacApp: App {
    @StateObject private var simulation: SimulationViewModel
    @StateObject private var viewport = ViewportState()

    init() {
        let launchConfiguration = LaunchConfiguration.from(arguments: CommandLine.arguments)
        _simulation = StateObject(wrappedValue: SimulationViewModel(
            initialOpenURL: launchConfiguration.openURL,
            initialTraciPort: launchConfiguration.traciPort,
            initialTraciClientOrder: launchConfiguration.traciClientOrder
        ))
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

                Button("Open Current in NetEdit") {
                    simulation.openCurrentDocumentInNetEdit()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(simulation.sourceURL == nil)

                Button("Open File in NetEdit...") {
                    simulation.presentNetEditOpenPanel()
                }

                Button("New Network in NetEdit") {
                    simulation.createNewNetworkInNetEdit()
                }

                Divider()

                Button("New Native Network Draft") {
                    Task {
                        await simulation.beginNativeNetworkEditing()
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Convert Current to Native Draft") {
                    Task {
                        await simulation.beginNativeNetworkEditingFromCurrentOrNew()
                    }
                }
                .disabled(simulation.graph == nil)

                Button("Export Native Network...") {
                    simulation.presentNativeNetworkExportPanel()
                }
                .disabled(!simulation.nativeNetworkCanExport)

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
            CommandMenu("Editor") {
                Button("Select Tool") {
                    simulation.setNativeEditTool(.select)
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(!simulation.nativeNetworkEditingEnabled)

                Button("Junction Tool") {
                    simulation.setNativeEditTool(.junction)
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(!simulation.nativeNetworkEditingEnabled)

                Button("Edge Tool") {
                    simulation.setNativeEditTool(.edge)
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(!simulation.nativeNetworkEditingEnabled)

                Divider()

                Button("Undo Native Editor Change") {
                    simulation.undoNativeEditorChange()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!simulation.nativeEditorCanUndo)

                Button("Redo Native Editor Change") {
                    simulation.redoNativeEditorChange()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!simulation.nativeEditorCanRedo)

                Divider()

                Button(simulation.nativeSnapToGrid ? "Disable Grid Snap" : "Enable Grid Snap") {
                    simulation.setNativeSnapToGrid(!simulation.nativeSnapToGrid)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!simulation.nativeNetworkEditingEnabled)

                Divider()

                Button("Customize Junction Shape") {
                    simulation.customizeSelectedNativeJunctionShape()
                }
                .disabled(simulation.selectedNativeJunction == nil || simulation.selectedNativeJunction?.hasCustomShape == true)

                Button("Add Junction Shape Point") {
                    simulation.addShapePointToSelectedNativeJunction()
                }
                .disabled(simulation.selectedNativeJunction == nil)

                Button("Remove Last Junction Shape Point") {
                    simulation.removeLastShapePointFromSelectedNativeJunction()
                }
                .disabled((simulation.selectedNativeJunction?.shapePoints.count ?? 0) <= 3)

                Button("Reset Junction Shape") {
                    simulation.resetSelectedNativeJunctionShape()
                }
                .disabled(simulation.selectedNativeJunction?.hasCustomShape != true)

                Divider()

                Button("Add Edge Geometry Point") {
                    simulation.addGeometryPointToSelectedNativeEdge()
                }
                .disabled(simulation.selectedNativeEdge == nil)

                Button("Remove Last Edge Geometry Point") {
                    simulation.removeLastGeometryPointFromSelectedNativeEdge()
                }
                .disabled(simulation.selectedNativeEdge?.geometryPoints.isEmpty ?? true)

                Button("Duplicate Selected Edge") {
                    simulation.duplicateSelectedNativeEdge()
                }
                .disabled(simulation.selectedNativeEdge == nil)

                Button("Create Reverse Edge") {
                    simulation.reverseSelectedNativeEdge()
                }
                .disabled(simulation.selectedNativeEdge == nil)

                Divider()

                Button("Delete Selected Native Objects") {
                    simulation.deleteSelectedNativeObject()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!simulation.nativeNetworkEditingEnabled || simulation.nativeEditor.selectedObjectCount == 0)

                Button("Cancel Pending Edge") {
                    simulation.clearNativePendingEdge()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!simulation.nativeNetworkEditingEnabled || simulation.nativeEditor.pendingEdgeStartJunctionID == nil)
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
