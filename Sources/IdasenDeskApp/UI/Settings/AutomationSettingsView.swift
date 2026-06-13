import IdasenDeskCore
import SwiftUI

struct AutomationSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Toggle("Auto-stand", isOn: automationEnabledBinding)

            Stepper(value: standMinutesBinding, in: 1...45) {
                Text("Stand \(model.settings.automation.standMinutesPerHour) min/hour")
            }
            .disabled(!model.settings.automation.isEnabled)

            Stepper(value: activeSecondsBinding, in: 60...1800, step: 60) {
                Text("Require activity within \(Int(model.settings.automation.requiredActiveSeconds / 60)) min")
            }
            .disabled(!model.settings.automation.isEnabled)
        }
        .formStyle(.grouped)
    }

    private var automationEnabledBinding: Binding<Bool> {
        Binding {
            model.settings.automation.isEnabled
        } set: { value in
            var automation = model.settings.automation
            automation.isEnabled = value
            model.setAutomation(automation)
        }
    }

    private var standMinutesBinding: Binding<Int> {
        Binding {
            model.settings.automation.standMinutesPerHour
        } set: { value in
            var automation = model.settings.automation
            automation.standMinutesPerHour = value
            model.setAutomation(automation)
        }
    }

    private var activeSecondsBinding: Binding<TimeInterval> {
        Binding {
            model.settings.automation.requiredActiveSeconds
        } set: { value in
            var automation = model.settings.automation
            automation.requiredActiveSeconds = value
            model.setAutomation(automation)
        }
    }
}

