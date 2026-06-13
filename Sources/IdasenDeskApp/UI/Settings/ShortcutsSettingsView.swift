import IdasenDeskCore
import SwiftUI

struct ShortcutsSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Table(model.settings.shortcuts) {
                TableColumn("Enabled") { binding in
                    Toggle("", isOn: enabledBinding(for: binding))
                        .labelsHidden()
                }
                .width(70)
                TableColumn("Action") { binding in
                    Text(binding.action.displayName)
                }
                TableColumn("Shortcut") { binding in
                    Text(shortcutLabel(binding))
                        .foregroundStyle(.secondary)
                }
            }

            let duplicates = ShortcutValidation.duplicates(in: model.settings.shortcuts)
            if !duplicates.isEmpty {
                Text("Duplicate shortcut: \(duplicates.first?.action.displayName ?? "Unknown")")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func enabledBinding(for binding: ShortcutBinding) -> Binding<Bool> {
        Binding {
            model.settings.shortcuts.first(where: { $0.id == binding.id })?.isEnabled ?? false
        } set: { value in
            var shortcuts = model.settings.shortcuts
            guard let index = shortcuts.firstIndex(where: { $0.id == binding.id }) else {
                return
            }
            shortcuts[index].isEnabled = value
            model.setShortcuts(shortcuts)
        }
    }

    private func shortcutLabel(_ binding: ShortcutBinding) -> String {
        var parts = [String]()
        if binding.modifiers.contains(.control) {
            parts.append("Control")
        }
        if binding.modifiers.contains(.option) {
            parts.append("Option")
        }
        if binding.modifiers.contains(.shift) {
            parts.append("Shift")
        }
        if binding.modifiers.contains(.command) {
            parts.append("Command")
        }
        parts.append("Key \(binding.keyCode)")
        return parts.joined(separator: " + ")
    }
}

