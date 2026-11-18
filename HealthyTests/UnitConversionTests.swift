import Foundation
import Testing

struct UnitConversionTests {
    @Test func fractionToPercent() {
        #expect(UnitConversion.percent(fromFraction: 0.9636) == 96.36)
        #expect(UnitConversion.percent(fromFraction: nil) == nil)
    }

    @Test func metersToCentimeters() {
        #expect(UnitConversion.centimeters(fromMeters: 0.72) == 72)
    }

    @Test func metersToKilometers() {
        #expect(UnitConversion.kilometers(fromMeters: 5_500) == 5.5)
    }
}
