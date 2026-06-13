import Foundation
import IdasenDeskCore
import Observation

@MainActor
@Observable
final class AppModel {
    var settings: AppSettings
    var discoveredDesks: [DeskSnapshot] = []
    var activeSnapshot: DeskSnapshot?
    var connectionState: DeskConnectionState = .disconnected
    var diagnostics: [String] = []
    var launchAtLoginEnabled: Bool = LoginItemController.isEnabled
    var lastError: String?

    private let service: any DeskService
    private let settingsStore: SettingsStore
    private let movementCoordinator: MovementCoordinator
    private let autoStandScheduler: AutoStandScheduler
    private let shortcutManager: ShortcutManager
    private let softwareUpdateController: SoftwareUpdateController
    private var eventTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        service: any DeskService,
        settingsStore: SettingsStore,
        autoStandScheduler: AutoStandScheduler,
        shortcutManager: ShortcutManager,
        softwareUpdateController: SoftwareUpdateController
    ) {
        self.service = service
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
        self.autoStandScheduler = autoStandScheduler
        self.shortcutManager = shortcutManager
        self.softwareUpdateController = softwareUpdateController
        self.movementCoordinator = MovementCoordinator(transport: ServiceTransport(service: service))
        configureAutomation()
        configureShortcuts()
    }

    static func live() -> AppModel {
        AppModel(
            service: BluetoothDeskService(),
            settingsStore: SettingsStore(),
            autoStandScheduler: AutoStandScheduler(),
            shortcutManager: ShortcutManager(),
            softwareUpdateController: SoftwareUpdateController()
        )
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true
        consumeEvents()
        service.scan()
    }

    func scan() {
        service.scan()
    }

    func saveAndConnect(_ snapshot: DeskSnapshot) {
        updateSettings { settings in
            if !settings.savedDesks.contains(where: { $0.id == snapshot.id }) {
                settings.savedDesks.append(SavedDesk(id: snapshot.id, displayName: snapshot.name, lastSeen: snapshot.lastSeen))
            }
            settings.activeDeskID = snapshot.id
            settings.hasCompletedOnboarding = true
        }
        service.connect(to: snapshot.id)
    }

    func connect(to id: DeskID) {
        updateSettings { $0.activeDeskID = id }
        service.connect(to: id)
    }

    func forgetDesk(_ id: DeskID) {
        updateSettings { settings in
            settings.savedDesks.removeAll { $0.id == id }
            if settings.activeDeskID == id {
                settings.activeDeskID = settings.savedDesks.first?.id
            }
        }
    }

    func renameDesk(_ id: DeskID, name: String) {
        updateSettings { settings in
            guard let index = settings.savedDesks.firstIndex(where: { $0.id == id }) else {
                return
            }
            settings.savedDesks[index].displayName = name
        }
    }

    func setPreset(_ kind: DeskPresetKind, height: DeskHeight, for id: DeskID) {
        updateSettings { settings in
            guard let deskIndex = settings.savedDesks.firstIndex(where: { $0.id == id }) else {
                return
            }

            if let presetIndex = settings.savedDesks[deskIndex].presets.firstIndex(where: { $0.kind == kind }) {
                settings.savedDesks[deskIndex].presets[presetIndex].height = height
            } else {
                settings.savedDesks[deskIndex].presets.append(DeskPreset(kind: kind, height: height))
            }
        }
    }

    func movePreset(_ kind: DeskPresetKind) {
        guard
            let activeDeskID = settings.activeDeskID,
            let desk = settings.savedDesks.first(where: { $0.id == activeDeskID }),
            let height = desk.presetHeight(for: kind)
        else {
            lastError = "No active desk preset found"
            return
        }

        Task {
            await movementCoordinator.move(to: height)
        }
    }

    func moveUp() {
        Task {
            await movementCoordinator.moveUp()
        }
    }

    func moveDown() {
        Task {
            await movementCoordinator.moveDown()
        }
    }

    func stop() {
        Task {
            await movementCoordinator.stop()
        }
    }

    func perform(_ command: DeskCommand) {
        switch command {
        case .moveUp:
            moveUp()
        case .moveDown:
            moveDown()
        case .stop:
            stop()
        case .moveToHeight(let height):
            Task {
                await movementCoordinator.move(to: height)
            }
        case .moveToPreset(let kind):
            movePreset(kind)
        }
    }

    func setMeasurementSystem(_ system: MeasurementSystem) {
        updateSettings { $0.measurementSystem = system }
    }

    func setAutomation(_ automation: AutomationSettings) {
        updateSettings { $0.automation = automation }
        configureAutomation()
    }

    func setShortcuts(_ shortcuts: [ShortcutBinding]) {
        updateSettings { $0.shortcuts = shortcuts }
        configureShortcuts()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemController.setEnabled(enabled)
            launchAtLoginEnabled = LoginItemController.isEnabled
        } catch {
            lastError = error.localizedDescription
            launchAtLoginEnabled = LoginItemController.isEnabled
        }
    }

    func checkForUpdates() {
        softwareUpdateController.checkForUpdates()
    }

    func stopForLifecycleEvent() {
        service.send(.stop)
        autoStandScheduler.stop()
    }

    private func consumeEvents() {
        eventTask = Task { [weak self, service] in
            for await event in service.events {
                await MainActor.run {
                    self?.handle(event)
                }
            }
        }
    }

    private func handle(_ event: DeskEvent) {
        diagnostics.insert(describe(event), at: 0)
        diagnostics = Array(diagnostics.prefix(200))

        switch event {
        case .scanStarted:
            connectionState = .scanning
        case .discovered(let snapshot):
            upsert(snapshot)
        case .connectionStateChanged(let id, let state):
            connectionState = state
            if id == settings.activeDeskID {
                activeSnapshot?.connectionState = state
            }
        case .heightChanged(let id, let height, let speed):
            guard id == settings.activeDeskID else {
                return
            }
            var snapshot = activeSnapshot ?? DeskSnapshot(id: id, name: activeDeskName)
            snapshot.currentHeight = height
            snapshot.speed = speed
            snapshot.connectionState = .connected
            snapshot.lastSeen = Date()
            activeSnapshot = snapshot
            Task {
                await movementCoordinator.handleSnapshot(snapshot)
            }
        case .commandSent:
            break
        case .error(let message):
            lastError = message
        }
    }

    private func upsert(_ snapshot: DeskSnapshot) {
        if let index = discoveredDesks.firstIndex(where: { $0.id == snapshot.id }) {
            discoveredDesks[index] = snapshot
        } else {
            discoveredDesks.append(snapshot)
        }

        if snapshot.id == settings.activeDeskID {
            activeSnapshot = snapshot
        }
    }

    private var activeDeskName: String {
        guard let activeDeskID = settings.activeDeskID else {
            return "IDASEN Desk"
        }
        return settings.savedDesks.first(where: { $0.id == activeDeskID })?.displayName ?? "IDASEN Desk"
    }

    private func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&settings)
        do {
            try settingsStore.save(settings)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func configureAutomation() {
        autoStandScheduler.onCommand = { command in
            Task { @MainActor in
                AppContainer.model.perform(command)
            }
        }
        autoStandScheduler.update(settings: settings.automation)
    }

    private func configureShortcuts() {
        shortcutManager.onAction = { action in
            Task { @MainActor in
                AppContainer.model.performShortcut(action)
            }
        }
        shortcutManager.apply(bindings: settings.shortcuts)
    }

    private func performShortcut(_ action: ShortcutAction) {
        switch action {
        case .moveToSit:
            movePreset(.sit)
        case .moveToStand:
            movePreset(.stand)
        case .stop:
            stop()
        case .showMenu:
            diagnostics.insert("Show menu shortcut triggered", at: 0)
        case .moveToCustomHeight(let height):
            perform(.moveToHeight(height))
        }
    }

    private func describe(_ event: DeskEvent) -> String {
        switch event {
        case .scanStarted:
            return "Scan started"
        case .discovered(let snapshot):
            return "Discovered \(snapshot.name)"
        case .connectionStateChanged(_, let state):
            return "Connection changed: \(state.displayName)"
        case .heightChanged(_, let height, let speed):
            return "Height \(Int(height.centimeters.rounded())) cm, speed \(Int(speed))"
        case .commandSent(let command):
            return "Command sent: \(command.displayName)"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

private struct ServiceTransport: DeskCommandTransport {
    let service: any DeskService

    func send(_ command: DeskCommand) async {
        service.send(command)
    }
}

private extension DeskCommand {
    var displayName: String {
        switch self {
        case .moveUp:
            return "move up"
        case .moveDown:
            return "move down"
        case .stop:
            return "stop"
        case .moveToHeight(let height):
            return "move to \(Int(height.centimeters.rounded())) cm"
        case .moveToPreset(let preset):
            return "move to \(preset.rawValue)"
        }
    }
}

extension DeskConnectionState {
    var displayName: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .bluetoothUnavailable:
            return "Bluetooth unavailable"
        case .unauthorized:
            return "Bluetooth unauthorized"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}
