import Foundation

public struct DeskID: RawRepresentable, Codable, Hashable, Identifiable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var id: String { rawValue }
    public var description: String { rawValue }
}

public struct DeskHeight: Codable, Hashable, Comparable, Sendable {
    public var centimeters: Double

    public init(centimeters: Double) {
        self.centimeters = centimeters
    }

    public static func < (lhs: DeskHeight, rhs: DeskHeight) -> Bool {
        lhs.centimeters < rhs.centimeters
    }
}

public enum MeasurementSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial
}

public enum DeskPresetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case sit
    case stand

    public var id: String { rawValue }
}

public struct DeskPreset: Codable, Hashable, Sendable, Identifiable {
    public var kind: DeskPresetKind
    public var height: DeskHeight

    public init(kind: DeskPresetKind, height: DeskHeight) {
        self.kind = kind
        self.height = height
    }

    public var id: DeskPresetKind { kind }
}

public enum DeskConnectionState: Codable, Hashable, Sendable {
    case disconnected
    case scanning
    case connecting
    case connected
    case bluetoothUnavailable
    case unauthorized
    case failed(String)

    public var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

public struct DeskSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: DeskID
    public var name: String
    public var rssi: Int?
    public var currentHeight: DeskHeight?
    public var speed: Double
    public var connectionState: DeskConnectionState
    public var lastSeen: Date

    public init(
        id: DeskID,
        name: String,
        rssi: Int? = nil,
        currentHeight: DeskHeight? = nil,
        speed: Double = 0,
        connectionState: DeskConnectionState = .disconnected,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.rssi = rssi
        self.currentHeight = currentHeight
        self.speed = speed
        self.connectionState = connectionState
        self.lastSeen = lastSeen
    }
}

public enum DeskCommand: Codable, Hashable, Sendable {
    case moveUp
    case moveDown
    case stop
    case moveToHeight(DeskHeight)
    case moveToPreset(DeskPresetKind)
}

public enum DeskEvent: Sendable {
    case scanStarted
    case discovered(DeskSnapshot)
    case connectionStateChanged(DeskID?, DeskConnectionState)
    case heightChanged(DeskID, DeskHeight, speed: Double)
    case commandSent(DeskCommand)
    case error(String)
}

public struct SavedDesk: Codable, Hashable, Identifiable, Sendable {
    public var id: DeskID
    public var displayName: String
    public var lastSeen: Date?
    public var presets: [DeskPreset]

    public init(
        id: DeskID,
        displayName: String,
        lastSeen: Date? = nil,
        presets: [DeskPreset] = SavedDesk.defaultPresets
    ) {
        self.id = id
        self.displayName = displayName
        self.lastSeen = lastSeen
        self.presets = presets
    }

    public static let defaultPresets: [DeskPreset] = [
        DeskPreset(kind: .sit, height: DeskHeight(centimeters: 70)),
        DeskPreset(kind: .stand, height: DeskHeight(centimeters: 110))
    ]

    public func presetHeight(for kind: DeskPresetKind) -> DeskHeight? {
        presets.first { $0.kind == kind }?.height
    }
}

