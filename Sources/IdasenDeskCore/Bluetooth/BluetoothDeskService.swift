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
                self.centralManager?.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: true
                ])
            }
        }
    }

    public func connect(to id: DeskID) {
        queue.async { [weak self] in
            guard let self, let peripheral = self.discoveredPeripherals[id] else {
                self?.broadcaster.yield(.connectionStateChanged(id, .failed("Desk not found")))
                return
            }

            self.activeDeskID = id
            self.broadcaster.yield(.connectionStateChanged(id, .connecting))
            self.centralManager?.connect(peripheral, options: nil)
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

        guard
            let id = activeDeskID,
            let peripheral = discoveredPeripherals[id],
            let state = peripheralsByIdentifier[peripheral.identifier],
            let characteristic = state.controlCharacteristic
        else {
            broadcaster.yield(.error("No connected desk control characteristic is available"))
            return
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        readPosition(for: peripheral)
        broadcaster.yield(.commandSent(command))
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
            central.scanForPeripherals(withServices: nil, options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true
            ])
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
        peripheralsByIdentifier[peripheral.identifier, default: PeripheralState(peripheral: peripheral)].name = peripheral.name
        broadcaster.yield(.discovered(snapshot(for: peripheral, rssi: RSSI, state: .disconnected)))
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([
            IdasenBLEProtocol.positionServiceUUID,
            IdasenBLEProtocol.controlServiceUUID
        ])
        broadcaster.yield(.connectionStateChanged(DeskID(rawValue: peripheral.identifier.uuidString), .connected))
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if activeDeskID?.rawValue == peripheral.identifier.uuidString {
            stopPositionPolling()
            activeDeskID = nil
        }
        broadcaster.yield(.connectionStateChanged(DeskID(rawValue: peripheral.identifier.uuidString), .disconnected))
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if activeDeskID?.rawValue == peripheral.identifier.uuidString {
            stopPositionPolling()
        }
        let message = error?.localizedDescription ?? "Failed to connect"
        broadcaster.yield(.connectionStateChanged(DeskID(rawValue: peripheral.identifier.uuidString), .failed(message)))
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
        peripheralsByIdentifier[peripheral.identifier] = state

        let id = DeskID(rawValue: peripheral.identifier.uuidString)
        broadcaster.yield(.heightChanged(id, sample.height, speed: sample.speed))
        broadcaster.yield(.discovered(snapshot(for: peripheral, state: .connected)))
    }
}

private struct PeripheralState {
    var peripheral: CBPeripheral
    var name: String?
    var positionCharacteristic: CBCharacteristic?
    var controlCharacteristic: CBCharacteristic?
    var height: DeskHeight?
    var speed: Double = 0
}
