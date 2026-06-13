import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Connection")
                Spacer()
                Text(model.connectionState.displayName)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    model.scan()
                } label: {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }
                Button {
                    model.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                Button {
                    model.checkForUpdates()
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
            }

            Divider()

            List(model.diagnostics.prefix(8), id: \.self) { entry in
                Text(entry)
                    .font(.caption.monospaced())
            }
        }
    }
}
