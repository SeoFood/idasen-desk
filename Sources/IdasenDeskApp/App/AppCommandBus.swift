import Foundation
import IdasenDeskCore

@MainActor
final class AppCommandBus {
    static let shared = AppCommandBus()

    private init() {}

    func perform(_ command: DeskCommand) {
        AppContainer.model.perform(command)
    }
}

