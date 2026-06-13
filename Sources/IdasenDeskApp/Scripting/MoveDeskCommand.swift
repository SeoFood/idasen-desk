import Foundation
import IdasenDeskCore

final class MoveDeskCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let parameter = directParameter as? String,
              let command = DeskCommandParser.parseMove(parameter)
        else {
            return nil
        }

        Task { @MainActor in
            AppCommandBus.shared.perform(command)
        }
        return nil
    }
}

