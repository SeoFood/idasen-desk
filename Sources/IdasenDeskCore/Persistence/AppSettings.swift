import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var hasCompletedOnboarding: Bool
    public var measurementSystem: MeasurementSystem
    public var activeDeskID: DeskID?
    public var savedDesks: [SavedDesk]
    public var automation: AutomationSettings
    public var shortcuts: [ShortcutBinding]

    public init(
        hasCompletedOnboarding: Bool = false,
        measurementSystem: MeasurementSystem = Locale.current.measurementSystem == .metric ? .metric : .imperial,
        activeDeskID: DeskID? = nil,
        savedDesks: [SavedDesk] = [],
        automation: AutomationSettings = AutomationSettings(),
        shortcuts: [ShortcutBinding] = ShortcutBinding.defaults
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.measurementSystem = measurementSystem
        self.activeDeskID = activeDeskID
        self.savedDesks = savedDesks
        self.automation = automation
        self.shortcuts = shortcuts
    }
}

public struct AutomationSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var standMinutesPerHour: Int
    public var requiredActiveSeconds: TimeInterval

    public init(
        isEnabled: Bool = false,
        standMinutesPerHour: Int = 10,
        requiredActiveSeconds: TimeInterval = 5 * 60
    ) {
        self.isEnabled = isEnabled
        self.standMinutesPerHour = standMinutesPerHour
        self.requiredActiveSeconds = requiredActiveSeconds
    }
}

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.seofood.IdasenDesk.settings.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return AppSettings()
        }

        do {
            return try decoder.decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    public func save(_ settings: AppSettings) throws {
        let data = try encoder.encode(settings)
        defaults.set(data, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}

