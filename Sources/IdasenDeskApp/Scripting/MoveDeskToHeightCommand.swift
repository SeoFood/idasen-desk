import Foundation
import IdasenDeskCore

final class MoveDeskToHeightCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let parameter = directParameter as? String else {
            return nil
        }

        Task { @MainActor in
            let system = AppContainer.model.settings.measurementSystem
            guard let command = DeskCommandParser.parseMoveToHeight(parameter, measurementSystem: system) else {
                return
            }
            AppCommandBus.shared.perform(command)
        }
        return nil
    }
}

