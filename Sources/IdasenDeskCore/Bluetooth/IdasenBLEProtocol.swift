import CoreBluetooth
import Foundation

public struct DeskPositionSample: Equatable, Sendable {
    public var height: DeskHeight
    public var speed: Double
}

public enum IdasenBLEProtocol {
    public static let positionServiceUUIDString = "99FA0020-338A-1024-8A49-009C0215F78A"
    public static let positionCharacteristicUUIDString = "99FA0021-338A-1024-8A49-009C0215F78A"
    public static let controlServiceUUIDString = "99FA0001-338A-1024-8A49-009C0215F78A"
    public static let controlCharacteristicUUIDString = "99FA0002-338A-1024-8A49-009C0215F78A"

    public static var positionServiceUUID: CBUUID {
        CBUUID(string: positionServiceUUIDString)
    }

    public static var positionCharacteristicUUID: CBUUID {
        CBUUID(string: positionCharacteristicUUIDString)
    }

    public static var controlServiceUUID: CBUUID {
        CBUUID(string: controlServiceUUIDString)
    }

    public static var controlCharacteristicUUID: CBUUID {
        CBUUID(string: controlCharacteristicUUIDString)
    }

    public static let heightOffsetCentimeters = 61.5

    public static func parsePositionSample(from data: Data) -> DeskPositionSample? {
        guard data.count >= 4 else {
            return nil
        }

        let rawPosition = UInt16(data[0]) | (UInt16(data[1]) << 8)
        let rawSpeed = UInt16(data[2]) | (UInt16(data[3]) << 8)
        let speed = Int16(bitPattern: rawSpeed)
        let height = Double(rawPosition) / 100 + heightOffsetCentimeters

        return DeskPositionSample(height: DeskHeight(centimeters: height), speed: Double(speed))
    }

    public static func commandData(for command: DeskCommand) -> Data? {
        switch command {
        case .moveUp:
            return Data([0x47, 0x00])
        case .moveDown:
            return Data([0x46, 0x00])
        case .stop:
            return Data([0xFF, 0x00])
        case .moveToHeight, .moveToPreset:
            return nil
        }
    }
}
