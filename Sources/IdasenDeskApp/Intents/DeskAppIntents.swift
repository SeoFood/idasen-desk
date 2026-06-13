import AppIntents
import Foundation
import IdasenDeskCore

struct MoveDeskToSitIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Desk to Sit"
    static let description = IntentDescription("Moves the active desk to the saved sitting preset.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppContainer.model.movePreset(.sit)
        }
        return .result()
    }
}

struct MoveDeskToStandIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Desk to Stand"
    static let description = IntentDescription("Moves the active desk to the saved standing preset.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppContainer.model.movePreset(.stand)
        }
        return .result()
    }
}

struct StopDeskIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Desk"
    static let description = IntentDescription("Stops the active desk.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppContainer.model.stop()
        }
        return .result()
    }
}

struct MoveDeskUpIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Desk Up"
    static let description = IntentDescription("Starts moving the active desk up.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppContainer.model.moveUp()
        }
        return .result()
    }
}

struct MoveDeskDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Desk Down"
    static let description = IntentDescription("Starts moving the active desk down.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppContainer.model.moveDown()
        }
        return .result()
    }
}

struct MoveDeskToHeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Desk to Height"
    static let description = IntentDescription("Moves the active desk to a height in centimeters.")

    @Parameter(title: "Centimeters")
    var centimeters: Double

    func perform() async throws -> some IntentResult {
        let height = DeskHeight(centimeters: centimeters)
        await MainActor.run {
            AppContainer.model.perform(.moveToHeight(height))
        }
        return .result()
    }
}

struct IdasenDeskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MoveDeskToSitIntent(),
            phrases: ["Move \(.applicationName) to sit"],
            shortTitle: "Sit",
            systemImageName: "chair"
        )
        AppShortcut(
            intent: MoveDeskToStandIntent(),
            phrases: ["Move \(.applicationName) to stand"],
            shortTitle: "Stand",
            systemImageName: "figure.stand"
        )
        AppShortcut(
            intent: StopDeskIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop",
            systemImageName: "stop.fill"
        )
    }
}
