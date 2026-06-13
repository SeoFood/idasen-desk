import Foundation

public enum DeskCommandParser {
    public static func parseMove(_ input: String) -> DeskCommand? {
        switch input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "to-sit", "sit":
            return .moveToPreset(.sit)
        case "to-stand", "stand":
            return .moveToPreset(.stand)
        case "up":
            return .moveUp
        case "down":
            return .moveDown
        case "stop":
            return .stop
        default:
            return nil
        }
    }

    public static func parseMoveToHeight(_ input: String, measurementSystem: MeasurementSystem) -> DeskCommand? {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.hasSuffix("cm"), let value = Double(normalized.dropLast(2)) {
            return .moveToHeight(DeskHeight(centimeters: value))
        }

        if normalized.hasSuffix("in"), let value = Double(normalized.dropLast(2)) {
            return .moveToHeight(DeskHeight(centimeters: UnitConversion.centimeters(fromInches: value)))
        }

        guard let value = Double(normalized) else {
            return nil
        }

        return .moveToHeight(UnitConversion.height(fromDisplayValue: value, system: measurementSystem))
    }
}

