//
//  Measurements.swift
//  BetterBlueKit
//
//  Distance and temperature measurement types
//

import Foundation

// MARK: - Measurements

public struct Distance: Codable, Hashable, Sendable {
    public enum Units: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
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

/// Which lookup table the vehicle's HVAC controller uses to map
/// between Celsius and Fahrenheit. Decompiled from Hyundai's
/// Android app (Bluelink / KiaConnect):
///
/// - `.standard`  — older Hyundai/Kia USA + Hyundai Canada vehicles.
///   Mostly linear but with two known non-linearities (17.5°C and
///   18.0°C both round to 63°F; 31.0°C and 31.5°C both round to 89°F).
/// - `.european` — CCS2 EU vehicles (Hyundai EU, Kia EU). Strictly
///   0.5°C → integer °F with no duplicate mappings.
///
/// The car only accepts values that exist in its table. Sending a
/// linear-formula result like 22.22°C (from 72°F) silently no-ops
/// — that's the bug the EU temperature cleanup is fixing.
public enum HVACTemperatureTable: Sendable {
    case standard, european
}

public struct Temperature: Codable, Hashable, Sendable {
    public enum Units: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
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
            let convertedTemperature = self.convert(temperature, to: targetUnits)

            let formatter = NumberFormatter()
            formatter.maximumFractionDigits = 0
            let formattedNumber = formatter.string(from: NSNumber(value: convertedTemperature)) ?? "0"

            return "\(formattedNumber)\(targetUnits.symbol)"
        }

        /// Pure mathematical F↔C conversion. General-purpose; do NOT
        /// use this for values you'll send to the HVAC controller —
        /// the car only accepts values from its lookup table, and a
        /// raw conversion can land off-grid (e.g. 72°F → 22.22°C is
        /// silently rejected by EU CCS2 cars). Use
        /// `Temperature.hvacConvert(_:from:to:table:)` for HVAC values.
        public func convert(_ temperature: Double, to targetUnits: Units) -> Double {
            switch (self, targetUnits) {
            case (.celsius, .fahrenheit): (temperature * 9.0 / 5.0) + 32.0
            case (.fahrenheit, .celsius): (temperature - 32.0) * 5.0 / 9.0
            default: temperature
            }
        }
    }

    public var units: Units, value: Double
    public static let minimum = 62.0, maximum = 82.0

    public init(units: Int?, value: String?) {
        self.units = Units(units)
        self.value = if let value, let number = Double(value) {
            number
        } else if value == "HI" {
            Units.fahrenheit.convert(Temperature.maximum, to: self.units)
        } else if let value, !value.isEmpty, value.hasSuffix("H") {
            Temperature.parseAirTempFromHEX(value, to: self.units)
        } else {
            Units.fahrenheit.convert(Temperature.minimum, to: self.units)
        }
    }

    public init(value: Double, units: Units) {
        (self.value, self.units) = (value, units)
    }

    private static func parseAirTempFromHEX(_ rawValue: String, to targetUnits: Units) -> Double {
        // Hyundai/Kia HEX format "02H", "0AH", ...
        let hexPart = String(rawValue.dropLast())
        guard let index = Int(hexPart, radix: 16), (0..<32).contains(index) else {
            return Units.fahrenheit.convert(Temperature.minimum, to: targetUnits)
        }

        // => tempC = (28 + index) * 0.5
        let tempC = Double(28 + index) * 0.5
        return Units.celsius.convert(tempC, to: targetUnits)
    }

    // MARK: - HVAC conversion (table-based)

    /// Convert a temperature between °C and °F for use with the HVAC
    /// controller. Uses the car's lookup table so the result is
    /// guaranteed to land on a value the controller will accept.
    ///
    /// The reverse direction (°F → °C) returns the canonical Celsius
    /// grid value that the source Fahrenheit would map to under the
    /// same table — i.e. round-tripping `c → f → c` is the identity
    /// for any in-range Celsius value on the 0.5°C grid.
    public static func hvacConvert(
        _ value: Double,
        from sourceUnits: Units,
        to targetUnits: Units,
        table: HVACTemperatureTable = .european
    ) -> Double {
        if sourceUnits == targetUnits { return value }
        let pairs = celsiusFahrenheitPairs(for: table)
        switch (sourceUnits, targetUnits) {
        case (.celsius, .fahrenheit):
            let snapped = snapToHalfDegreeCelsius(value)
            // Nearest entry by Celsius distance, then return its °F.
            return Double(pairs.min { abs($0.celsius - snapped) < abs($1.celsius - snapped) }!.fahrenheit)
        case (.fahrenheit, .celsius):
            let rounded = value.rounded()
            // Nearest entry by Fahrenheit distance, then return its °C.
            // Ties (e.g. 63°F under .standard, which maps from both
            // 17.5°C and 18.0°C) resolve to the FIRST match — which
            // is the lower Celsius value, matching Hyundai's own UI.
            return pairs.min { abs(Double($0.fahrenheit) - rounded) < abs(Double($1.fahrenheit) - rounded) }!.celsius
        default:
            return value
        }
    }

    /// Snap a Celsius value to the 0.5°C grid the HVAC controller
    /// uses. Exposed so callers can ensure values are aligned before
    /// sending them to APIs that take raw Celsius (Hyundai EU /
    /// Kia EU CCS2 climate start).
    public static func snapToHalfDegreeCelsius(_ celsius: Double) -> Double {
        (celsius * 2).rounded() / 2
    }

    /// Encode a 0.5°C-grid Celsius value as the HEX form the older
    /// Hyundai/Kia APIs (USA + Canada non-CCS2) expect — e.g. 17.0°C
    /// → "06H", 22.0°C → "10H", 27.0°C → "1AH". Inverse of
    /// `parseAirTempFromHEX`. Clamped to the [14.0°C, 31.5°C] range
    /// the HEX scheme can represent (32 values, 0x00–0x1F).
    public static func encodeAirTempToHEX(celsiusValue celsius: Double) -> String {
        let snapped = snapToHalfDegreeCelsius(celsius)
        // tempC = (28 + index) * 0.5  →  index = tempC * 2 - 28
        let index = Int((snapped * 2).rounded()) - 28
        let clamped = max(0, min(31, index))
        return String(format: "%02XH", clamped)
    }

    // MARK: - Lookup tables

    /// Standard table (`hvacTempType != 1`) — Hyundai/Kia USA + older
    /// vehicles + Hyundai Canada. Decompiled from the Android app.
    /// Note the two duplicate-target rows: 17.5/18.0 → 63°F and
    /// 31.0/31.5 → 89°F. Round-tripping F→C from those F values lands
    /// on the lower Celsius value (the `.min` tie-break in
    /// `hvacConvert` matches Hyundai's UI behavior).
    private static let standardTable: [(celsius: Double, fahrenheit: Int)] = [
        (14.5, 57), (15.0, 58), (15.5, 59), (16.0, 60), (16.5, 61),
        (17.0, 62), (17.5, 63), (18.0, 63),
        (18.5, 64), (19.0, 65), (19.5, 66), (20.0, 67), (20.5, 68),
        (21.0, 69), (21.5, 70), (22.0, 71), (22.5, 72), (23.0, 73),
        (23.5, 74), (24.0, 75), (24.5, 76), (25.0, 77), (25.5, 78),
        (26.0, 79), (26.5, 80), (27.0, 81), (27.5, 82), (28.0, 83),
        (28.5, 84), (29.0, 85), (29.5, 86), (30.0, 87), (30.5, 88),
        (31.0, 89), (31.5, 89),
        (32.0, 90), (32.5, 91)
    ]

    /// EU table (`hvacTempType == 1`) — Hyundai EU + Kia EU CCS2
    /// vehicles. Strict 0.5°C → integer °F, no duplicates. This is
    /// the default for `hvacConvert` since the EU vehicles are the
    /// ones that silently no-op on off-grid values.
    private static let euTable: [(celsius: Double, fahrenheit: Int)] = [
        (15.0, 58), (15.5, 59), (16.0, 60), (16.5, 61), (17.0, 62),
        (17.5, 63), (18.0, 64), (18.5, 65), (19.0, 66), (19.5, 67),
        (20.0, 68), (20.5, 69), (21.0, 70), (21.5, 71), (22.0, 72),
        (22.5, 73), (23.0, 74), (23.5, 75), (24.0, 76), (24.5, 77),
        (25.0, 78), (25.5, 79), (26.0, 80), (26.5, 81), (27.0, 82),
        (27.5, 83), (28.0, 84), (28.5, 85), (29.0, 86), (29.5, 87),
        (30.0, 88)
    ]

    private static func celsiusFahrenheitPairs(
        for table: HVACTemperatureTable
    ) -> [(celsius: Double, fahrenheit: Int)] {
        switch table {
        case .standard: standardTable
        case .european: euTable
        }
    }
}
