import SwiftUI

struct DiagnosticsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Diagnostics")
                        .font(.title2.bold())
                    Text(model.connectionState.displayName)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.scan()
                } label: {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }
            }

            List(model.diagnostics, id: \.self) { item in
                Text(item)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(20)
    }
}

