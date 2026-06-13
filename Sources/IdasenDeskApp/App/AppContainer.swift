import Foundation

@MainActor
enum AppContainer {
    static let model = AppModel.live()
}

