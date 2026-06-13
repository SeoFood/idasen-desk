import SwiftUI

@main
struct IdasenDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppContainer.model

    var body: some Scene {
        MenuBarExtra("Idasen Desk", systemImage: "arrow.up.and.down") {
            MenuBarContentView()
                .environment(model)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        Window("Diagnostics", id: "diagnostics") {
            DiagnosticsView()
                .environment(model)
        }
        .defaultSize(width: 760, height: 460)

        Settings {
            SettingsView()
                .environment(model)
        }
        .commands {
            CommandMenu("Desk") {
                Button("Move to Sit") {
                    model.movePreset(.sit)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])

                Button("Move to Stand") {
                    model.movePreset(.stand)
                }
                .keyboardShortcut("w", modifiers: [.command, .option])

                Button("Stop") {
                    model.stop()
                }
                .keyboardShortcut(.space, modifiers: [.command, .option])

                Divider()

                Button("Check for Updates...") {
                    model.checkForUpdates()
                }
            }
        }
    }
}
