import Foundation

enum UnitConversion {
    static func percent(fromFraction value: Double?) -> Double? {
        value.map { $0 * 100 }
    }

    static func centimeters(fromMeters value: Double?) -> Double? {
        value.map { $0 * 100 }
    }

    static func kilometers(fromMeters value: Double?) -> Double? {
        value.map { $0 / 1000 }
    }
}
