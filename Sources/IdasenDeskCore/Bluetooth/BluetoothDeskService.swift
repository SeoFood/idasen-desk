import CoreBluetooth
import Foundation

public final class BluetoothDeskService: NSObject, DeskService, @unchecked Sendable {
    public var events: AsyncStream<DeskEvent> {
        broadcaster.stream()
    }

    private let queue = DispatchQueue(label: "com.seofood.IdasenDesk.bluetooth")
    private let broadcaster = EventBroadcaster<DeskEvent>()

    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [DeskID: CBPeripheral] = [:]
    private var peripheralsByIdentifier: [UUID: PeripheralState] = [:]
    private var activeDeskID: DeskID?
    private var positionPollTimer: DispatchSourceTimer?
    private var pendingCommands = BluetoothPendingCommandQueue()
    private var inFlightCommandsByPeripheralIdentifier: [UUID: DeskCommand] = [:]
    private var commandRecoveryTimersByPeripheralIdentifier: [UUID: DispatchSourceTimer] = [:]
    private var readinessRecoveryTimersByPeripheralIdentifier: [UUID: DispatchSourceTimer] = [:]
    private var recoveringPeripheralIdentifiers = Set<UUID>()
    private let commandPositionResponseTimeout: TimeInterval = 2.0
    private let commandReadinessTimeout: TimeInterval = 4.0

    public override init() {
        super.init()
    }

    public func scan() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.broadcaster.yield(.scanStarted)
            if self.centralManager == nil {
                self.centralManager = CBCentralManager(delegate: self, queue: self.queue)
            } else if self.centralManager?.state == .poweredOn {
                self.centralManager?.scanForPeripherals(withServices: nil, options: nil)
            }
        }
    }

    public func connect(to id: DeskID) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.activeDeskID = id
            self.broadcaster.yield(.connectionStateChanged(id, .connecting))
            if self.centralManager == nil {
                self.centralManager = CBCentralManager(delegate: self, queue: self.queue)
            }

            guard let peripheral = self.peripheral(for: id) else {
                if self.centralManager?.state == .poweredOn {
                    self.centralManager?.scanForPeripherals(withServices: nil, options: nil)
                }
                return
            }

            self.reconnectIfNeeded(to: id, peripheral: peripheral)
            self.flushPendingCommandIfReady(for: peripheral)
        }
    }

    public func disconnect() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.stopPositionPolling()
            self.sendOnQueue(.stop)
            if let id = self.activeDeskID, let peripheral = self.discoveredPeripherals[id] {
                self.centralManager?.cancelPeripheralConnection(peripheral)
            }
            self.activeDeskID = nil
            self.pendingCommands.clear()
            self.cancelAllCommandRecoveryTimers()
            self.cancelAllReadinessRecoveryTimers()
            self.recoveringPeripheralIdentifiers.removeAll()
            self.broadcaster.yield(.connectionStateChanged(nil, .disconnected))
        }
    }

    public func send(_ command: DeskCommand) {
        queue.async { [weak self] in
            self?.sendOnQueue(command)
        }
    }

    private func sendOnQueue(_ command: DeskCommand) {
        guard let data = IdasenBLEProtocol.commandData(for: command) else {
            broadcaster.yield(.error("Targeted movement must be handled by MovementCoordinator"))
            return
        }

        guard let id = activeDeskID else {
            if command == .stop {
                pendingCommands.clear()
                return
            }
            broadcaster.yield(.error("No connected desk control characteristic is available"))
            return
        }

        guard let peripheral = peripheral(for: id) else {
            pendingCommands.enqueue(command)
            guard command.isRetryableAfterReconnect else {
                return
            }

            if centralManager == nil {
                centralManager = CBCentralManager(delegate: self, queue: queue)
            } else if centralManager?.state == .poweredOn {
                broadcaster.yield(.connectionStateChanged(id, .connecting))
                centralManager?.scanForPeripherals(withServices: nil, options: nil)
            }
            return
        }

        guard peripheral.state == .connected else {
            queueForReconnect(command, id: id, peripheral: peripheral)
            return
        }

        guard
            let state = peripheralsByIdentifier[peripheral.identifier],
            let characteristic = state.controlCharacteristic
        else {
            queueForReconnect(command, id: id, peripheral: peripheral)
            peripheral.discoverServices([
                IdasenBLEProtocol.positionServiceUUID,
                IdasenBLEProtocol.controlServiceUUID
            ])
            return
        }

        var updatedState = state
        updatedState.commandHealth.recordCommand(command, at: Date())
        peripheralsByIdentifier[peripheral.identifier] = updatedState
        inFlightCommandsByPeripheralIdentifier[peripheral.identifier] = command
        scheduleCommandRecoveryWatchdog(for: peripheral)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        readPosition(for: peripheral)
        broadcaster.yield(.commandSent(command))
    }

    private func queueForReconnect(_ command: DeskCommand, id: DeskID, peripheral: CBPeripheral) {
        pendingCommands.enqueue(command)

        guard command.isRetryableAfterReconnect else {
            return
        }

        scheduleReadinessRecoveryWatchdog(for: peripheral)
        reconnectIfNeeded(to: id, peripheral: peripheral)
    }

    private func reconnectIfNeeded(to id: DeskID, peripheral: CBPeripheral) {
        guard let centralManager else {
            broadcaster.yield(.error("Bluetooth is not ready"))
            return
        }

        guard centralManager.state == .poweredOn else {
            return
        }

        switch peripheral.state {
        case .connected:
            scheduleReadinessRecoveryWatchdog(for: peripheral)
            peripheral.discoverServices([
                IdasenBLEProtocol.positionServiceUUID,
                IdasenBLEProtocol.controlServiceUUID
            ])
        case .connecting, .disconnecting:
            scheduleReadinessRecoveryWatchdog(for: peripheral)
            broadcaster.yield(.connectionStateChanged(id, .connecting))
        case .disconnected:
            scheduleReadinessRecoveryWatchdog(for: peripheral)
            broadcaster.yield(.connectionStateChanged(id, .connecting))
            centralManager.connect(peripheral, options: nil)
        @unknown default:
            scheduleReadinessRecoveryWatchdog(for: peripheral)
            broadcaster.yield(.connectionStateChanged(id, .connecting))
            centralManager.connect(peripheral, options: nil)
        }
    }

    private func recoverCommandConnection(to id: DeskID, peripheral: CBPeripheral) {
        guard let centralManager else {
            broadcaster.yield(.error("Bluetooth is not ready"))
            return
        }

        guard centralManager.state == .poweredOn else {
            return
        }

        let inserted = recoveringPeripheralIdentifiers.insert(peripheral.identifier).inserted
        guard inserted else {
            broadcaster.yield(.connectionStateChanged(id, .connecting))
            return
        }

        resetConnectionState(for: peripheral)
        broadcaster.yield(.connectionStateChanged(id, .connecting))

        switch peripheral.state {
        case .connected, .connecting:
            centralManager.cancelPeripheralConnection(peripheral)
        case .disconnecting:
            break
        case .disconnected:
            centralManager.connect(peripheral, options: nil)
        @unknown default:
            centralManager.cancelPeripheralConnection(peripheral)
        }

        centralManager.scanForPeripherals(withServices: nil, options: nil)
    }

    private func resetConnectionState(for peripheral: CBPeripheral) {
        stopPositionPolling()
        cancelCommandRecoveryTimer(for: peripheral)
        cancelReadinessRecoveryTimer(for: peripheral)
        var state = peripheralsByIdentifier[peripheral.identifier] ?? PeripheralState(peripheral: peripheral)
        state.peripheral = peripheral
        state.positionCharacteristic = nil
        state.controlCharacteristic = nil
        state.speed = 0
        state.commandHealth.resetCommand()
        peripheralsByIdentifier[peripheral.identifier] = state
        inFlightCommandsByPeripheralIdentifier[peripheral.identifier] = nil
    }

    private func flushPendingCommandIfReady(for peripheral: CBPeripheral) {
        guard
            peripheral.state == .connected,
            let state = peripheralsByIdentifier[peripheral.identifier],
            state.isReadyForCommands,
            let command = pendingCommands.take()
        else {
            return
        }

        sendOnQueue(command)
    }

    private func peripheral(for id: DeskID) -> CBPeripheral? {
        if let peripheral = discoveredPeripherals[id] {
            return peripheral
        }

        guard
            let centralManager,
            let uuid = UUID(uuidString: id.rawValue),
            let peripheral = centralManager.retrievePeripherals(withIdentifiers: [uuid]).first
        else {
            return nil
        }

        discoveredPeripherals[id] = peripheral
        var state = peripheralsByIdentifier[peripheral.identifier] ?? PeripheralState(peripheral: peripheral)
        state.peripheral = peripheral
        state.name = peripheral.name
        peripheralsByIdentifier[peripheral.identifier] = state
        return peripheral
    }

    private func scheduleReadinessRecoveryWatchdog(for peripheral: CBPeripheral) {
        guard readinessRecoveryTimersByPeripheralIdentifier[peripheral.identifier] == nil else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(Int(commandReadinessTimeout * 1_000)))
        timer.setEventHandler { [weak self, weak peripheral] in
            guard let self, let peripheral else {
                return
            }
            self.handleReadinessRecoveryTimeout(for: peripheral)
        }
        readinessRecoveryTimersByPeripheralIdentifier[peripheral.identifier] = timer
        timer.resume()
    }

    private func handleReadinessRecoveryTimeout(for peripheral: CBPeripheral) {
        readinessRecoveryTimersByPeripheralIdentifier[peripheral.identifier] = nil

        guard
            let id = activeDeskID,
            id.rawValue == peripheral.identifier.uuidString
        else {
            return
        }

        if
            peripheral.state == .connected,
            let state = peripheralsByIdentifier[peripheral.identifier],
            state.isReadyForCommands
        {
            return
        }

        broadcaster.yield(.error("Desk connection stayed unavailable; reconnecting Bluetooth"))
        recoverCommandConnection(to: id, peripheral: peripheral)
    }

    private func startPositionPolling(for peripheral: CBPeripheral) {
        stopPositionPolling()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self, weak peripheral] in
            guard let self, let peripheral else {
                return
            }
            self.readPosition(for: peripheral)
        }
        positionPollTimer = timer
        timer.resume()
    }

    private func stopPositionPolling() {
        positionPollTimer?.cancel()
        positionPollTimer = nil
    }

    private func readPosition(for peripheral: CBPeripheral) {
        guard
            activeDeskID?.rawValue == peripheral.identifier.uuidString,
            let state = peripheralsByIdentifier[peripheral.identifier],
            let characteristic = state.positionCharacteristic
        else {
            return
        }

        peripheral.readValue(for: characteristic)
    }

    private func scheduleCommandRecoveryWatchdog(for peripheral: CBPeripheral) {
        cancelCommandRecoveryTimer(for: peripheral)

        guard
            let state = peripheralsByIdentifier[peripheral.identifier],
            state.commandHealth.isAwaitingPositionSample
        else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(Int(commandPositionResponseTimeout * 1_000)))
        timer.setEventHandler { [weak self, weak peripheral] in
            guard let self, let peripheral else {
                return
            }
            self.handleCommandRecoveryTimeout(for: peripheral)
        }
        commandRecoveryTimersByPeripheralIdentifier[peripheral.identifier] = timer
        timer.resume()
    }

    private func handleCommandRecoveryTimeout(for peripheral: CBPeripheral) {
        commandRecoveryTimersByPeripheralIdentifier[peripheral.identifier] = nil

        guard
            let id = activeDeskID,
            id.rawValue == peripheral.identifier.uuidString,
            var state = peripheralsByIdentifier[peripheral.identifier],
            let command = state.commandHealth.timedOutCommand(at: Date(), timeout: commandPositionResponseTimeout)
        else {
            return
        }

        peripheralsByIdentifier[peripheral.identifier] = state
        pendingCommands.enqueue(command)
        broadcaster.yield(.error("Desk did not respond to movement command; reconnecting Bluetooth"))
        recoverCommandConnection(to: id, peripheral: peripheral)
    }

    private func cancelCommandRecoveryTimer(for peripheral: CBPeripheral) {
        commandRecoveryTimersByPeripheralIdentifier[peripheral.identifier]?.cancel()
        commandRecoveryTimersByPeripheralIdentifier[peripheral.identifier] = nil
    }

    private func cancelAllCommandRecoveryTimers() {
        for timer in commandRecoveryTimersByPeripheralIdentifier.values {
            timer.cancel()
        }
        commandRecoveryTimersByPeripheralIdentifier.removeAll()
    }

    private func cancelReadinessRecoveryTimer(for peripheral: CBPeripheral) {
        readinessRecoveryTimersByPeripheralIdentifier[peripheral.identifier]?.cancel()
        readinessRecoveryTimersByPeripheralIdentifier[peripheral.identifier] = nil
    }

    private func cancelAllReadinessRecoveryTimers() {
        for timer in readinessRecoveryTimersByPeripheralIdentifier.values {
            timer.cancel()
        }
        readinessRecoveryTimersByPeripheralIdentifier.removeAll()
    }

    private func snapshot(for peripheral: CBPeripheral, rssi: NSNumber? = nil, state: DeskConnectionState) -> DeskSnapshot {
        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        let existing = peripheralsByIdentifier[peripheral.identifier]
        return DeskSnapshot(
            id: id,
            name: peripheral.name ?? existing?.name ?? "IDASEN Desk",
            rssi: rssi?.intValue,
            currentHeight: existing?.height,
            speed: existing?.speed ?? 0,
            connectionState: state,
            lastSeen: Date()
        )
    }

    private func isLikelyDesk(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           name.localizedCaseInsensitiveContains("desk") || name.localizedCaseInsensitiveContains("idasen") {
            return true
        }

        let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        return serviceUUIDs.contains(IdasenBLEProtocol.positionServiceUUID)
            || serviceUUIDs.contains(IdasenBLEProtocol.controlServiceUUID)
    }
}

extension BluetoothDeskService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            broadcaster.yield(.connectionStateChanged(nil, .scanning))
            central.scanForPeripherals(withServices: nil, options: nil)
            if let id = activeDeskID, let peripheral = discoveredPeripherals[id] {
                reconnectIfNeeded(to: id, peripheral: peripheral)
            }
        case .unauthorized:
            broadcaster.yield(.connectionStateChanged(nil, .unauthorized))
        case .poweredOff, .unsupported:
            broadcaster.yield(.connectionStateChanged(nil, .bluetoothUnavailable))
        case .resetting, .unknown:
            broadcaster.yield(.connectionStateChanged(nil, .disconnected))
        @unknown default:
            broadcaster.yield(.connectionStateChanged(nil, .failed("Unknown Bluetooth state")))
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isLikelyDesk(peripheral: peripheral, advertisementData: advertisementData) else {
            return
        }

        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        discoveredPeripherals[id] = peripheral
        var state = peripheralsByIdentifier[peripheral.identifier] ?? PeripheralState(peripheral: peripheral)
        state.peripheral = peripheral
        state.name = peripheral.name
        peripheralsByIdentifier[peripheral.identifier] = state
        broadcaster.yield(.discovered(snapshot(for: peripheral, rssi: RSSI, state: .disconnected)))

        if id == activeDeskID, peripheral.state == .disconnected {
            reconnectIfNeeded(to: id, peripheral: peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        recoveringPeripheralIdentifiers.remove(peripheral.identifier)
        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        discoveredPeripherals[id] = peripheral
        var state = peripheralsByIdentifier[peripheral.identifier] ?? PeripheralState(peripheral: peripheral)
        state.peripheral = peripheral
        peripheralsByIdentifier[peripheral.identifier] = state
        peripheral.discoverServices([
            IdasenBLEProtocol.positionServiceUUID,
            IdasenBLEProtocol.controlServiceUUID
        ])
        broadcaster.yield(.connectionStateChanged(id, .connecting))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        recoveringPeripheralIdentifiers.remove(peripheral.identifier)
        if activeDeskID?.rawValue == peripheral.identifier.uuidString {
            resetConnectionState(for: peripheral)
            broadcaster.yield(.connectionStateChanged(id, .disconnected))
            reconnectIfNeeded(to: id, peripheral: peripheral)
            return
        }
        resetConnectionState(for: peripheral)
        broadcaster.yield(.connectionStateChanged(id, .disconnected))
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        recoveringPeripheralIdentifiers.remove(peripheral.identifier)
        if activeDeskID?.rawValue == peripheral.identifier.uuidString {
            resetConnectionState(for: peripheral)
            central.scanForPeripherals(withServices: nil, options: nil)
        }
        let message = error?.localizedDescription ?? "Failed to connect"
        broadcaster.yield(.connectionStateChanged(id, .failed(message)))
    }
}

extension BluetoothDeskService: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            broadcaster.yield(.error(error?.localizedDescription ?? "Failed to discover services"))
            return
        }

        for service in services where service.uuid == IdasenBLEProtocol.positionServiceUUID || service.uuid == IdasenBLEProtocol.controlServiceUUID {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            broadcaster.yield(.error(error?.localizedDescription ?? "Failed to discover characteristics"))
            return
        }

        var state = peripheralsByIdentifier[peripheral.identifier] ?? PeripheralState(peripheral: peripheral)

        for characteristic in characteristics {
            if characteristic.uuid == IdasenBLEProtocol.positionCharacteristicUUID {
                state.positionCharacteristic = characteristic
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
                startPositionPolling(for: peripheral)
            }

            if characteristic.uuid == IdasenBLEProtocol.controlCharacteristicUUID {
                state.controlCharacteristic = characteristic
            }
        }

        peripheralsByIdentifier[peripheral.identifier] = state

        if state.isReadyForCommands {
            let id = DeskID(rawValue: peripheral.identifier.uuidString)
            cancelReadinessRecoveryTimer(for: peripheral)
            broadcaster.yield(.connectionStateChanged(id, .connected))
            flushPendingCommandIfReady(for: peripheral)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == IdasenBLEProtocol.positionCharacteristicUUID, let data = characteristic.value else {
            if let error {
                broadcaster.yield(.error(error.localizedDescription))
            }
            return
        }

        guard let sample = IdasenBLEProtocol.parsePositionSample(from: data) else {
            broadcaster.yield(.error("Invalid position sample"))
            return
        }

        var state = peripheralsByIdentifier[peripheral.identifier] ?? PeripheralState(peripheral: peripheral)
        state.height = sample.height
        state.speed = sample.speed
        state.commandHealth.recordPositionSample(at: Date())
        peripheralsByIdentifier[peripheral.identifier] = state
        cancelCommandRecoveryTimer(for: peripheral)

        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        broadcaster.yield(.heightChanged(id, sample.height, speed: sample.speed))
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let error else {
            inFlightCommandsByPeripheralIdentifier[peripheral.identifier] = nil
            return
        }

        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        if let command = inFlightCommandsByPeripheralIdentifier[peripheral.identifier] {
            pendingCommands.enqueue(command)
        }
        resetConnectionState(for: peripheral)
        broadcaster.yield(.error("Bluetooth write failed: \(error.localizedDescription)"))

        if activeDeskID == id {
            if peripheral.state == .connected {
                centralManager?.cancelPeripheralConnection(peripheral)
            } else {
                reconnectIfNeeded(to: id, peripheral: peripheral)
            }
        }
    }
}

struct BluetoothPendingCommandQueue: Sendable, Equatable {
    private(set) var command: DeskCommand?

    mutating func enqueue(_ command: DeskCommand) {
        guard command.isRetryableAfterReconnect else {
            clear()
            return
        }

        self.command = command
    }

    mutating func take() -> DeskCommand? {
        defer { clear() }
        return command
    }

    mutating func clear() {
        command = nil
    }
}

private struct PeripheralState {
    var peripheral: CBPeripheral
    var name: String?
    var positionCharacteristic: CBCharacteristic?
    var controlCharacteristic: CBCharacteristic?
    var height: DeskHeight?
    var speed: Double = 0
    var commandHealth = BluetoothCommandHealthTracker()

    var isReadyForCommands: Bool {
        positionCharacteristic != nil && controlCharacteristic != nil
    }
}

struct BluetoothCommandHealthTracker: Sendable, Equatable {
    private(set) var commandAwaitingPosition: DeskCommand?
    private(set) var commandStartedAt: Date?
    private(set) var lastPositionSampleAt: Date?

    var isAwaitingPositionSample: Bool {
        commandAwaitingPosition != nil
    }

    mutating func recordCommand(_ command: DeskCommand, at date: Date) {
        guard command.isRetryableAfterReconnect else {
            resetCommand()
            return
        }

        commandAwaitingPosition = command
        commandStartedAt = date
    }

    mutating func recordPositionSample(at date: Date) {
        lastPositionSampleAt = date
        resetCommand()
    }

    mutating func timedOutCommand(at date: Date, timeout: TimeInterval) -> DeskCommand? {
        guard
            let command = commandAwaitingPosition,
            let commandStartedAt,
            date.timeIntervalSince(commandStartedAt) >= timeout
        else {
            return nil
        }

        resetCommand()
        return command
    }

    mutating func resetCommand() {
        commandAwaitingPosition = nil
        commandStartedAt = nil
    }
}

extension DeskCommand {
    var isRetryableAfterReconnect: Bool {
        switch self {
        case .moveUp, .moveDown:
            return true
        case .stop, .moveToHeight, .moveToPreset:
            return false
        }
    }
}
