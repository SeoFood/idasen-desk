import Foundation

public enum UnitConversion {
    public static func inches(fromCentimeters centimeters: Double) -> Double {
        Measurement(value: centimeters, unit: UnitLength.centimeters)
            .converted(to: .inches)
            .value
    }

    public static func centimeters(fromInches inches: Double) -> Double {
        Measurement(value: inches, unit: UnitLength.inches)
            .converted(to: .centimeters)
            .value
    }

    public static func displayValue(for height: DeskHeight, system: MeasurementSystem) -> Double {
        switch system {
        case .metric:
            return height.centimeters
        case .imperial:
            return inches(fromCentimeters: height.centimeters)
        }
    }

    public static func height(fromDisplayValue value: Double, system: MeasurementSystem) -> DeskHeight {
        switch system {
        case .metric:
            return DeskHeight(centimeters: value)
        case .imperial:
            return DeskHeight(centimeters: centimeters(fromInches: value))
        }
    }
}

