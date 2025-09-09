//
//  Measurements.swift
//  BetterBlueKit
//
//  Distance and temperature measurement types
//

import Foundation

// MARK: - Measurements

public struct Distance: Codable, Equatable, Sendable {
    public enum Units: String, Codable, CaseIterable, Identifiable, Sendable {
        case miles, kilometers

        init(_ integer: Int) { self = integer == 1 ? .kilometers : .miles }

        public var id: String { rawValue }
        public var displayName: String { self == .miles ? "Miles" : "Kilometers" }
        public var abbreviation: String { self == .miles ? "mi" : "km" }

        public func convert(_ length: Double, to targetUnits: Units) -> Double {
            if self == targetUnits {
                length
            } else if self == .miles, targetUnits == .kilometers {
                length * 1.609344
            } else if self == .kilometers, targetUnits == .miles {
                length / 1.609344
            } else {
                length
            }
        }

        public func format(_ length: Double, to targetUnits: Units) -> String {
            let convertedLength = convert(length, to: targetUnits)

            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 0
            let formattedNumber = formatter.string(from: NSNumber(value: convertedLength)) ?? "0"

            return "\(formattedNumber) \(targetUnits.abbreviation)"
        }
    }

    public var length: Double, units: Units

    public init(length: Double, units: Units) {
        (self.length, self.units) = (length, units)
    }
}

public struct Temperature: Codable, Equatable, Sendable {
    public enum Units: String, Codable, CaseIterable, Equatable, Identifiable, Sendable {
        case celsius, fahrenheit

        public init(_ number: Int?) { self = number == 1 ? .fahrenheit : .celsius }

        public func integer() -> Int { self == .fahrenheit ? 1 : 0 }
        public var id: String { rawValue }
        public var displayName: String { self == .fahrenheit ? "Fahrenheit" : "Celsius" }
        public var symbol: String { self == .fahrenheit ? "°F" : "°C" }
        public var hvacRange: ClosedRange<Double> {
            switch self {
            case .fahrenheit: 62.0 ... 82.0 // Standard HVAC range in Fahrenheit
            case .celsius: 16.0 ... 28.0 // Standard HVAC range in Celsius
            }
        }

        public func format(_ temperature: Double, to targetUnits: Units) -> String {
            let convertedTemperature: Double

            convertedTemperature = switch (self, targetUnits) {
            case (.celsius, .fahrenheit): (temperature * 9.0 / 5.0) + 32.0
            case (.fahrenheit, .celsius): (temperature - 32.0) * 5.0 / 9.0
            default: temperature
            }

            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 0
            let formattedNumber = formatter.string(from: NSNumber(value: convertedTemperature)) ?? "0"

            return "\(formattedNumber)\(targetUnits.symbol)"
        }
    }

    public var units: Units, value: Double
    public static let minimum = 62.0, maximum = 82.0

    public init(units: Int?, value: String?) {
        self.units = Units(units)
        self.value = if let value, let number = Double(value) {
            number
        } else if value == "HI" {
            Temperature.maximum
        } else {
            Temperature.minimum
        }
    }

    public init(value: Double, units: Units) {
        (self.value, self.units) = (value, units)
    }
}
