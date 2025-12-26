//
//  MeasurementsTests.swift
//  BetterBlueKit
//
//  Distance and Temperature measurement tests
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Measurements Tests")
struct MeasurementsTests {

    // MARK: - Distance Tests

    @Test("Distance creation with miles")
    func testDistanceCreationMiles() {
        let distance = Distance(length: 100.0, units: .miles)
        #expect(distance.length == 100.0)
        #expect(distance.units == .miles)
    }

    @Test("Distance creation with kilometers")
    func testDistanceCreationKilometers() {
        let distance = Distance(length: 160.9344, units: .kilometers)
        #expect(distance.length == 160.9344)
        #expect(distance.units == .kilometers)
    }

    @Test("Distance Units initialization from integer")
    func testDistanceUnitsFromInteger() {
        #expect(Distance.Units(1) == .kilometers)
        #expect(Distance.Units(0) == .miles)
        #expect(Distance.Units(2) == .miles) // default
        #expect(Distance.Units(-1) == .miles) // default
    }

    @Test("Distance Units display properties")
    func testDistanceUnitsDisplayProperties() {
        #expect(Distance.Units.miles.displayName == "Miles")
        #expect(Distance.Units.kilometers.displayName == "Kilometers")

        #expect(Distance.Units.miles.abbreviation == "mi")
        #expect(Distance.Units.kilometers.abbreviation == "km")

        #expect(Distance.Units.miles.id == "miles")
        #expect(Distance.Units.kilometers.id == "kilometers")
    }

    @Test("Distance Units conversion miles to kilometers")
    func testDistanceUnitsConversionMilesToKm() {
        let miles = Distance.Units.miles
        let converted = miles.convert(100.0, to: .kilometers)
        #expect(abs(converted - 160.9344) < 0.0001)
    }

    @Test("Distance Units conversion kilometers to miles")
    func testDistanceUnitsConversionKmToMiles() {
        let kilometers = Distance.Units.kilometers
        let converted = kilometers.convert(160.9344, to: .miles)
        #expect(abs(converted - 100.0) < 0.0001)
    }

    @Test("Distance Units conversion same units")
    func testDistanceUnitsConversionSameUnits() {
        let miles = Distance.Units.miles
        let converted = miles.convert(100.0, to: .miles)
        #expect(converted == 100.0)

        let kilometers = Distance.Units.kilometers
        let converted2 = kilometers.convert(160.0, to: .kilometers)
        #expect(converted2 == 160.0)
    }

    @Test("Distance Units format with conversion")
    func testDistanceUnitsFormat() {
        let miles = Distance.Units.miles
        let formatted = miles.format(100.0, to: .kilometers)
        #expect(formatted == "161 km")

        let kilometers = Distance.Units.kilometers
        let formatted2 = kilometers.format(160.9344, to: .miles)
        #expect(formatted2 == "100 mi")
    }

    @Test("Distance Units format same units")
    func testDistanceUnitsFormatSameUnits() {
        let miles = Distance.Units.miles
        let formatted = miles.format(100.0, to: .miles)
        #expect(formatted == "100 mi")
    }

    @Test("Distance Codable")
    func testDistanceCodable() throws {
        let original = Distance(length: 150.5, units: .kilometers)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Distance.self, from: encoded)

        #expect(decoded.length == original.length)
        #expect(decoded.units == original.units)
    }

    // MARK: - Temperature Tests

    @Test("Temperature creation with fahrenheit")
    func testTemperatureCreationFahrenheit() {
        let temp = Temperature(value: 72.0, units: .fahrenheit)
        #expect(temp.value == 72.0)
        #expect(temp.units == .fahrenheit)
    }

    @Test("Temperature creation with celsius")
    func testTemperatureCreationCelsius() {
        let temp = Temperature(value: 22.2, units: .celsius)
        #expect(temp.value == 22.2)
        #expect(temp.units == .celsius)
    }

    @Test("Temperature Units initialization from integer")
    func testTemperatureUnitsFromInteger() {
        #expect(Temperature.Units(1) == .fahrenheit)
        #expect(Temperature.Units(0) == .celsius)
        #expect(Temperature.Units(nil) == .celsius)
        #expect(Temperature.Units(2) == .celsius) // default
    }

    @Test("Temperature Units display properties")
    func testTemperatureUnitsDisplayProperties() {
        #expect(Temperature.Units.fahrenheit.displayName == "Fahrenheit")
        #expect(Temperature.Units.celsius.displayName == "Celsius")

        #expect(Temperature.Units.fahrenheit.symbol == "°F")
        #expect(Temperature.Units.celsius.symbol == "°C")

        #expect(Temperature.Units.fahrenheit.id == "fahrenheit")
        #expect(Temperature.Units.celsius.id == "celsius")
    }

    @Test("Temperature Units integer conversion")
    func testTemperatureUnitsIntegerConversion() {
        #expect(Temperature.Units.fahrenheit.integer() == 1)
        #expect(Temperature.Units.celsius.integer() == 0)
    }

    @Test("Temperature Units HVAC ranges")
    func testTemperatureUnitsHVACRanges() {
        let fahrenheitRange = Temperature.Units.fahrenheit.hvacRange
        #expect(fahrenheitRange.lowerBound == 62.0)
        #expect(fahrenheitRange.upperBound == 82.0)

        let celsiusRange = Temperature.Units.celsius.hvacRange
        #expect(celsiusRange.lowerBound == 16.0)
        #expect(celsiusRange.upperBound == 28.0)
    }

    @Test("Temperature Units format celsius to fahrenheit")
    func testTemperatureUnitsFormatCelsiusToFahrenheit() {
        let celsius = Temperature.Units.celsius
        let formatted = celsius.format(22.0, to: .fahrenheit)
        #expect(formatted == "72°F")
    }

    @Test("Temperature Units format fahrenheit to celsius")
    func testTemperatureUnitsFormatFahrenheitToCelsius() {
        let fahrenheit = Temperature.Units.fahrenheit
        let formatted = fahrenheit.format(72.0, to: .celsius)
        #expect(formatted == "22°C")
    }

    @Test("Temperature Units format same units")
    func testTemperatureUnitsFormatSameUnits() {
        let fahrenheit = Temperature.Units.fahrenheit
        let formatted = fahrenheit.format(72.0, to: .fahrenheit)
        #expect(formatted == "72°F")

        let celsius = Temperature.Units.celsius
        let formatted2 = celsius.format(22.0, to: .celsius)
        #expect(formatted2 == "22°C")
    }

    @Test("Temperature initialization from string and int")
    func testTemperatureInitFromStringAndInt() {
        let temp1 = Temperature(units: 1, value: "72")
        #expect(temp1.units == .fahrenheit)
        #expect(temp1.value == 72.0)

        let temp2 = Temperature(units: 0, value: "22")
        #expect(temp2.units == .celsius)
        #expect(temp2.value == 22.0)

        let temp3 = Temperature(units: nil, value: nil)
        #expect(temp3.units == .celsius)
        #expect(temp3.value == Temperature.minimum)
    }

    @Test("Temperature initialization with HI value")
    func testTemperatureInitWithHI() {
        let temp = Temperature(units: 1, value: "HI")
        #expect(temp.units == .fahrenheit)
        #expect(temp.value == Temperature.maximum)
    }

    @Test("Temperature initialization with invalid value")
    func testTemperatureInitWithInvalidValue() {
        let temp = Temperature(units: 1, value: "invalid")
        #expect(temp.units == .fahrenheit)
        #expect(temp.value == Temperature.minimum)
    }

    @Test("Temperature constants")
    func testTemperatureConstants() {
        #expect(Temperature.minimum == 62.0)
        #expect(Temperature.maximum == 82.0)
    }

    @Test("Temperature Codable")
    func testTemperatureCodable() throws {
        let original = Temperature(value: 23.5, units: .celsius)

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Temperature.self, from: encoded)

        #expect(decoded.value == original.value)
        #expect(decoded.units == original.units)
    }

    // MARK: - Edge Cases and Error Handling

    @Test("Distance conversion edge cases")
    func testDistanceConversionEdgeCases() {
        let miles = Distance.Units.miles

        // Zero conversion
        #expect(miles.convert(0.0, to: .kilometers) == 0.0)

        // Large numbers
        let largeResult = miles.convert(1000000.0, to: .kilometers)
        #expect(abs(largeResult - 1609344.0) < 1.0)

        // Small numbers
        let smallResult = miles.convert(0.001, to: .kilometers)
        #expect(abs(smallResult - 0.001609344) < 0.000001)
    }

    @Test("Temperature conversion edge cases")
    func testTemperatureConversionEdgeCases() {
        let fahrenheit = Temperature.Units.fahrenheit
        let celsius = Temperature.Units.celsius

        // Freezing point
        let freezing = celsius.format(0.0, to: .fahrenheit)
        #expect(freezing == "32°F")

        // Boiling point
        let boiling = celsius.format(100.0, to: .fahrenheit)
        #expect(boiling == "212°F")

        // Absolute zero
        let absoluteZero = celsius.format(-273.15, to: .fahrenheit)
        #expect(absoluteZero == "-460°F")
    }
}
