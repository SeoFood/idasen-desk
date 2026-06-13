import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            DesksSettingsView()
                .tabItem { Label("Desks", systemImage: "table.furniture") }
            AutomationSettingsView()
                .tabItem { Label("Automation", systemImage: "clock.arrow.circlepath") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}

