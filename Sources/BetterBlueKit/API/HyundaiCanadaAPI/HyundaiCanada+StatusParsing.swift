//
//  HyundaiCanada+StatusParsing.swift
//  BetterBlueKit
//
//  Hyundai Canada status parsing helpers
//

import Foundation

extension HyundaiCanadaAPIClient {

    // MARK: - Status Parsing Helpers

    func detectFuelType(from vehicleData: [String: Any]) -> FuelType {
        if let evStatus = vehicleData["evStatus"] as? String {
            let status = evStatus.uppercased()
            if status.hasPrefix("E") { return .electric }
            if status.hasPrefix("P") { return .phev }
            return .gas
        }
        // `vhcllst` entries carry the powertrain as `fuelKindCode` ("G" gas,
        // "E" electric, "P" plug-in hybrid) — the same codes Hyundai Europe
        // uses. Without this branch every Canadian ICE vehicle fell through to
        // the `.electric` default below, which hid its fuel range and gave it a
        // phantom charge port (BetterBlue#98).
        if let fuelKindCode = (vehicleData["fuelKindCode"] as? String)?.uppercased() {
            switch fuelKindCode {
            case "E", "EV": return .electric
            case "P", "PE", "PHEV": return .phev
            case "G", "GS", "D": return .gas
            default: break
            }
        }
        if let fuelTypeNum: Int = extractNumber(from: vehicleData["fuelType"]) {
            return FuelType(number: fuelTypeNum)
        }
        if let modelName = (vehicleData["modelName"] as? String)?.lowercased() {
            if modelName.contains("ev") || modelName.contains("electric") { return .electric }
        }
        return .electric
    }

    /// Decodes a Canada distance `unit`. Canadian hyundai_kia_connect_api
    /// logs show the usual integer code — `'dte': {'value': 481.0,
    /// 'unit': 1}` on a Tucson PHEV (kia_uvo#1190), 1 = kilometers.
    /// BetterBlue#98's export showed `"unit": true`, but that build's
    /// exporter wrote every JSON 0/1 as a boolean, so the wire value was
    /// most likely 1. A real boolean is still accepted (`true` =
    /// kilometers); a numeric 0/1 also matches `as? Bool` and lands on the
    /// same unit `Distance.Units` gives it. Defaults to kilometers, which
    /// is what this region actually serves.
    func canadaDistanceUnits(from value: Any?) -> Distance.Units {
        if let flag = value as? Bool { return flag ? .kilometers : .miles }
        if let code: Int = extractNumber(from: value) { return Distance.Units(code) }
        return .kilometers
    }

    func parseCanadaEVStatus(
        from statusData: [String: Any],
        vehicle: Vehicle
    ) -> VehicleStatus.EVStatus? {
        guard vehicle.fuelType.hasElectricCapability,
              let evStatusData = statusData["evStatus"] as? [String: Any] else {
            return nil
        }

        let batteryStatus: Double = extractNumber(from: evStatusData["batteryStatus"]) ?? 0
        let chargeTimeMinutes = parseChargeTimeMinutes(from: evStatusData)
        let batteryPlugin: Int = extractNumber(from: evStatusData["batteryPlugin"]) ?? 0
        let charging = evStatusData["batteryCharge"] as? Bool ?? false
        let chargeSpeed = parseChargeSpeed(from: evStatusData)
        let range = parseCanadaEVRange(from: evStatusData) ?? Distance(length: 0, units: .kilometers)
        let (targetSocAC, targetSocDC) = parseTargetSOCs(from: evStatusData)

        return VehicleStatus.EVStatus(
            charging: charging,
            chargeSpeed: chargeSpeed,
            evRange: VehicleStatus.FuelRange(range: range, percentage: batteryStatus),
            plugType: VehicleStatus.PlugType(fromBatteryPlugin: batteryPlugin),
            chargeTime: .seconds(60 * chargeTimeMinutes),
            targetSocAC: targetSocAC,
            targetSocDC: targetSocDC
        )
    }

    func parseCanadaGasRange(
        from statusData: [String: Any],
        vehicle: Vehicle
    ) -> VehicleStatus.FuelRange? {
        guard vehicle.fuelType == .gas,
              let fuelLevel: Double = extractNumber(from: statusData["fuelLevel"]) else {
            return nil
        }

        // Canada names this `dte` ({"value": 481.0, "unit": 1} in
        // kia_uvo#1190); the `distanceToEmpty` spelling is kept as a
        // fallback in case some firmware still uses it. Reading only the
        // latter meant gas vehicles never showed a range even though the
        // value was right there in the payload (BetterBlue#98).
        let distanceToEmpty = (statusData["dte"] as? [String: Any])
            ?? (statusData["distanceToEmpty"] as? [String: Any])
        if let distanceToEmpty,
           let value: Double = extractNumber(from: distanceToEmpty["value"]) {
            return VehicleStatus.FuelRange(
                range: Distance(length: value, units: canadaDistanceUnits(from: distanceToEmpty["unit"])),
                percentage: fuelLevel
            )
        }

        if let evStatus = statusData["evStatus"] as? [String: Any],
           let drvDistance = evStatus["drvDistance"] as? [[String: Any]] {
            for entry in drvDistance {
                let rangeByFuel = entry["rangeByFuel"] as? [String: Any] ?? [:]
                let totalRange = rangeByFuel["totalAvailableRange"] as? [String: Any] ?? [:]
                if let value: Double = extractNumber(from: totalRange["value"]) {
                    let unit: Int = extractNumber(from: totalRange["unit"]) ?? 1
                    return VehicleStatus.FuelRange(
                        range: Distance(length: value, units: Distance.Units(unit)),
                        percentage: fuelLevel
                    )
                }
            }
        }

        return nil
    }

    func parseCanadaLocation(from statusData: [String: Any]) -> VehicleStatus.Location {
        let vehicleLocation = statusData["vehicleLocation"] as? [String: Any] ?? [:]
        let coord = vehicleLocation["coord"] as? [String: Any] ?? statusData["coord"] as? [String: Any] ?? [:]

        return VehicleStatus.Location(
            latitude: extractNumber(from: coord["lat"]) ?? 0,
            longitude: extractNumber(from: coord["lon"]) ?? 0
        )
    }

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

    /// Decodes Hyundai Canada's Gen3 `airTemp` block.
    ///
    /// Unlike the US API (which returns `"72"` / `"70"` style numeric strings),
    /// the Canadian endpoint returns a hex-encoded code, e.g. `"00H"`, `"0EH"`,
    /// `"23H"`. The hex byte indexes into a half-degree scale whose base
    /// depends on the model year — 14°C for MY2020+, 16°C for older —
    /// matching the `hyundai_kia_connect_api` decoder's table split.
    ///
    /// Missing or unparseable values fall through to the legacy
    /// `Temperature(units:value:)` initializer so downstream display code
    /// still gets a value (albeit one `TemperatureDisplay.isPlausibleForDisplay`
    /// will likely reject).
    private func parseCanadaAirTemp(
        airTempBlock: [String: Any],
        airTempUnitTopLevel: String?,
        modelYear: Int?
    ) -> Temperature {
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

        // Fall back to the legacy initializer so we always return something.
        return Temperature(units: unitField, value: rawValue)
    }

    func parseCanadaSyncDate(from statusData: [String: Any]) -> Date? {
        if let dateTime = statusData["dateTime"] as? String,
           let isoDate = ISO8601DateFormatter().date(from: dateTime) {
            return isoDate
        }

        if let lastStatusDate = statusData["lastStatusDate"] as? String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMddHHmmss"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            return formatter.date(from: lastStatusDate)
        }

        return nil
    }

    func parseCanadaBattery12V(from statusData: [String: Any]) -> Int? {
        guard let battery = statusData["battery"] as? [String: Any] else {
            return nil
        }
        return extractNumber(from: battery["batSoc"])
    }

    func parseCanadaDoorStatus(from statusData: [String: Any]) -> VehicleStatus.DoorStatus? {
        let doorData =
            statusData["doorOpen"] as? [String: Any] ??
            statusData["doorStatus"] as? [String: Any] ?? [:]

        if doorData.isEmpty {
            return nil
        }

        let frontLeft: Int = extractNumber(from: doorData["frontLeft"]) ?? 0
        let frontRight: Int = extractNumber(from: doorData["frontRight"]) ?? 0
        let backLeft: Int = extractNumber(from: doorData["backLeft"]) ?? 0
        let backRight: Int = extractNumber(from: doorData["backRight"]) ?? 0

        return VehicleStatus.DoorStatus(
            frontLeft: frontLeft != 0,
            frontRight: frontRight != 0,
            backLeft: backLeft != 0,
            backRight: backRight != 0
        )
    }

    func parseCanadaTrunkOpen(from statusData: [String: Any]) -> Bool? {
        parseOpenStatus(statusData, directKey: "trunkOpen", doorStatusKey: "trunk")
    }

    func parseCanadaHoodOpen(from statusData: [String: Any]) -> Bool? {
        parseOpenStatus(statusData, directKey: "hoodOpen", doorStatusKey: "hood")
    }

    func parseCanadaTirePressureWarning(
        from statusData: [String: Any]
    ) -> VehicleStatus.TirePressureWarning? {
        guard let tireData = statusData["tirePressureLamp"] as? [String: Any] else { return nil }

        func warning(_ long: String, _ short: String) -> Bool {
            let value: Int = extractNumber(from: tireData[long]) ?? extractNumber(from: tireData[short]) ?? 0
            return value != 0
        }

        return VehicleStatus.TirePressureWarning(
            frontLeft: warning("tirePressureWarningLampFrontLeft", "frontLeft"),
            frontRight: warning("tirePressureWarningLampFrontRight", "frontRight"),
            rearLeft: warning("tirePressureWarningLampRearLeft", "rearLeft"),
            rearRight: warning("tirePressureWarningLampRearRight", "rearRight"),
            all: warning("tirePressureWarningLampAll", "all")
        )
    }

    // MARK: - Private Helpers

    private func parseCanadaEVRange(from evStatusData: [String: Any]) -> Distance? {
        let drvDistance = evStatusData["drvDistance"] as? [[String: Any]] ?? []
        for entry in drvDistance {
            let rangeByFuel = entry["rangeByFuel"] as? [String: Any] ?? [:]
            let evModeRange = rangeByFuel["evModeRange"] as? [String: Any]
            let totalRange = rangeByFuel["totalAvailableRange"] as? [String: Any]
            let preferred = evModeRange ?? totalRange ?? [:]

            if let value: Double = extractNumber(from: preferred["value"]) {
                let unit: Int = extractNumber(from: preferred["unit"]) ?? 1
                return Distance(length: value, units: Distance.Units(unit))
            }
        }
        return nil
    }

    private func parseChargeSpeed(from evStatusData: [String: Any]) -> Double {
        if let batteryPower = evStatusData["batteryPower"] as? [String: Any] {
            let fast: Double = extractNumber(from: batteryPower["batteryFstChrgPower"]) ?? 0
            let standard: Double = extractNumber(from: batteryPower["batteryStndChrgPower"]) ?? 0
            return max(fast, standard)
        }

        let fast: Double = extractNumber(from: evStatusData["batteryFstChrgPower"]) ?? 0
        let standard: Double = extractNumber(from: evStatusData["batteryStndChrgPower"]) ?? 0
        return max(fast, standard)
    }

    private func parseChargeTimeMinutes(from evStatusData: [String: Any]) -> Int {
        // `atc` is the current session's ETA; hyundai_kia_connect_api
        // reads it as minutes (Canadian logs tag it `unit: 1`).
        let remainTime2 = evStatusData["remainTime2"] as? [String: Any] ?? [:]
        let atc = remainTime2["atc"] as? [String: Any] ?? [:]
        if let value: Int = extractNumber(from: atc["value"]) {
            return value
        }

        // No Canadian payload with `remainChargeTime` has turned up — the
        // Python Canada client reads only `remainTime2`, which the
        // kia_uvo#1017 and #1190 logs carry. This fallback is for firmware
        // that sends Kia USA's array instead, whose every known entry nests
        // its minutes under `timeInterval` (unit 4). A flat
        // `first?["value"]` read never finds them — the bug behind the
        // missing Kia ETA in BetterBlue#107.
        return Int(remainingChargeMinutes(in: evStatusData["remainChargeTime"]).rounded())
    }

    private func parseTargetSOCs(from evStatusData: [String: Any]) -> (Double?, Double?) {
        let reserveChargeInfos = evStatusData["reservChargeInfos"] as? [String: Any] ?? [:]
        let targetSocList = reserveChargeInfos["targetSOClist"] as? [[String: Any]] ??
            evStatusData["targetSOC"] as? [[String: Any]] ?? []

        var targetSocAC: Double?
        var targetSocDC: Double?

        for target in targetSocList {
            if let plugType = target["plugType"] as? Int,
               let soc: Double = extractNumber(from: target["targetSOClevel"]) {
                if plugType == 1 {
                    targetSocAC = soc
                } else if plugType == 0 {
                    targetSocDC = soc
                }
            }
        }

        return (targetSocAC, targetSocDC)
    }

    private func parseOpenStatus(_ data: [String: Any], directKey: String, doorStatusKey: String) -> Bool? {
        if let value = data[directKey] as? Bool { return value }
        let doorStatus = data["doorStatus"] as? [String: Any] ?? [:]
        if let intValue: Int = extractNumber(from: doorStatus[doorStatusKey]) { return intValue != 0 }
        return nil
    }

    private func stringify(_ value: Any?) -> String? {
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    func parseBoolOrInt(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool { return boolValue }
        if let intValue: Int = extractNumber(from: value) { return intValue != 0 }
        return nil
    }
}
