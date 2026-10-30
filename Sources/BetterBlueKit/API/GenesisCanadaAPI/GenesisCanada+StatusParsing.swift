//
//  GenesisCanada+StatusParsing.swift
//  BetterBlueKit
//
//  Genesis Canada climate status parsing, based on Hyundai Canada.
//

import Foundation

extension GenesisCanadaAPIClient {

    func parseCanadaClimateStatus(
        from statusData: [String: Any],
        modelYear: Int?
    ) -> VehicleStatus.ClimateStatus {
        let airTemp = statusData["airTemp"] as? [String: Any] ?? [:]

        return VehicleStatus.ClimateStatus(
            defrostOn: statusData["defrost"] as? Bool ?? false,
            airControlOn: (statusData["airCtrlOn"] as? Bool) ?? (statusData["airCtrl"] as? Bool) ?? false,
            steeringWheelHeatingOn: (extractNumber(from: statusData["steerWheelHeat"]) ?? 0) != 0,
            temperature: parseCanadaAirTemp(
                airTempBlock: airTemp,
                airTempUnitTopLevel: statusData["airTempUnit"] as? String,
                modelYear: modelYear
            )
        )
    }

    /// Decodes the same Gen3 `airTemp` block as Hyundai Canada.
    ///
    /// Unlike the US API (which returns `"72"` / `"70"` style numeric strings),
    /// the Canadian endpoint returns a hex-encoded code, e.g. `"00H"`, `"0EH"`,
    /// `"23H"`. The hex byte indexes into a half-degree scale whose base
    /// depends on the model year — 14°C for MY2020+, 16°C for older —
    /// matching the `hyundai_kia_connect_api` decoder's table split.
    ///
    /// Genesis gas vehicles can omit `airTemp`; return nil rather than
    /// the legacy initializer's minimum temperature when no value exists.
    private func parseCanadaAirTemp(
        airTempBlock: [String: Any],
        airTempUnitTopLevel: String?,
        modelYear: Int?
    ) -> Temperature? {
        let rawValue = stringify(airTempBlock["value"])
        let unitField: Int? = extractNumber(from: airTempBlock["unit"])

        // Canadian responses carry the human unit as a top-level string
        // ("C"/"F"). The nested `unit` field is an index into that unit's
        // scale, *not* the unit itself — many Gen3 payloads ship `unit: 0`
        // regardless of whether the top-level says "C" or "F".
        let units: Temperature.Units = {
            if let topLevel = airTempUnitTopLevel?.uppercased() {
                if topLevel == "F" { return .fahrenheit }
                if topLevel == "C" { return .celsius }
            }
            return Temperature.Units(unitField)
        }()

        // HI / LOW map to the HVAC range bounds, which Temperature.maximum/minimum
        // define in Fahrenheit (62...82). init(value:units:) does NOT convert, so
        // convert here to the resolved unit — otherwise a Celsius-resolved vehicle
        // stores an impossible 82°C / 62°C that downstream plausibility checks drop.
        if let raw = rawValue, raw == "HI" {
            return Temperature(value: Temperature.Units.fahrenheit.convert(Temperature.maximum, to: units), units: units)
        }
        if let raw = rawValue, raw == "LOW" {
            return Temperature(value: Temperature.Units.fahrenheit.convert(Temperature.minimum, to: units), units: units)
        }

        // Hex-code path: "00H", "0EH", etc.
        if let raw = rawValue,
           raw.count >= 2,
           raw.uppercased().hasSuffix("H"),
           let hex = UInt8(raw.dropLast(), radix: 16) {
            let celsius = Temperature.decodeCanadaAirTempHEX(index: Int(hex), modelYear: modelYear)
            let value = units == .fahrenheit ? celsius * 9.0 / 5.0 + 32.0 : celsius
            return Temperature(value: value, units: units)
        }

        // Plain numeric path, for payloads that don't use the hex encoding.
        if let raw = rawValue, let number = Double(raw) {
            return Temperature(value: number, units: units)
        }

        return nil
    }

    private func stringify(_ value: Any?) -> String? {
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }
}
