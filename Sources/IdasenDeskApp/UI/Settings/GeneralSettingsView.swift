import IdasenDeskCore
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Picker("Units", selection: measurementSystemBinding) {
                Text("Centimeters").tag(MeasurementSystem.metric)
                Text("Inches").tag(MeasurementSystem.imperial)
            }
            .pickerStyle(.segmented)

            Toggle("Launch at login", isOn: launchAtLoginBinding)

            if let lastError = model.lastError {
                Text(lastError)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private var measurementSystemBinding: Binding<MeasurementSystem> {
        Binding {
            model.settings.measurementSystem
        } set: { value in
            model.setMeasurementSystem(value)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            model.launchAtLoginEnabled
        } set: { value in
            model.setLaunchAtLogin(value)
        }
    }
}

