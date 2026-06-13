import IdasenDeskCore
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Idasen Desk")
                        .font(.largeTitle.bold())
                    Text("Pair a desk")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.scan()
                } label: {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }
            }

            if model.discoveredDesks.isEmpty {
                ContentUnavailableView("No desks found", systemImage: "deskclock", description: Text(model.connectionState.displayName))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.discoveredDesks) { desk in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(desk.name)
                                .font(.headline)
                            Text(desk.id.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Connect") {
                            model.saveAndConnect(desk)
                            OnboardingWindowPresenter.shared.close()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 440)
    }
}

