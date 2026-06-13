import IdasenDeskCore
import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            activeDeskPicker
            heightSection
            movementControls
            Divider()
            footer
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Idasen Desk")
                    .font(.headline)
                Text(model.connectionState.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Circle()
                .fill(model.connectionState.isConnected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
                .accessibilityLabel(model.connectionState.displayName)
        }
    }

    private var activeDeskPicker: some View {
        Picker("Desk", selection: activeDeskSelection) {
            Text("No desk").tag(Optional<DeskID>.none)
            ForEach(model.settings.savedDesks) { desk in
                Text(desk.displayName).tag(Optional(desk.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }

    private var heightSection: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(displayHeight)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(unitLabel)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.scan()
            } label: {
                Label("Scan", systemImage: "dot.radiowaves.left.and.right")
            }
            .labelStyle(.iconOnly)
            .help("Scan")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var movementControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    model.movePreset(.sit)
                } label: {
                    Label("Sit", systemImage: "chair")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    model.movePreset(.stand)
                } label: {
                    Label("Stand", systemImage: "figure.stand")
                        .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                HoldButton(title: "Down", systemImage: "arrow.down", press: model.moveDown, release: model.stop)
                HoldButton(title: "Up", systemImage: "arrow.up", press: model.moveUp, release: model.stop)
                Button {
                    model.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            Button {
                openWindow(id: "diagnostics")
            } label: {
                Label("Diagnostics", systemImage: "waveform.path.ecg")
            }
            Button {
                model.checkForUpdates()
            } label: {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            Spacer()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
    }

    private var activeDeskSelection: Binding<DeskID?> {
        Binding {
            model.settings.activeDeskID
        } set: { id in
            guard let id else {
                return
            }
            model.connect(to: id)
        }
    }

    private var displayHeight: String {
        guard let height = model.activeSnapshot?.currentHeight else {
            return "--"
        }
        let value = UnitConversion.displayValue(for: height, system: model.settings.measurementSystem)
        return "\(Int(value.rounded()))"
    }

    private var unitLabel: String {
        model.settings.measurementSystem == .metric ? "cm" : "in"
    }
}

private struct HoldButton: View {
    let title: String
    let systemImage: String
    let press: () -> Void
    let release: () -> Void

    @State private var isPressed = false

    var body: some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(isPressed ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else {
                            return
                        }
                        isPressed = true
                        press()
                    }
                    .onEnded { _ in
                        isPressed = false
                        release()
                    }
            )
            .accessibilityAddTraits(.isButton)
    }
}
